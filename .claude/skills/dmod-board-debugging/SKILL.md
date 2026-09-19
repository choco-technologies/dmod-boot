---
name: dmod-board-debugging
description: How to build, flash, run and debug dmod-boot firmware on the STM32F746G-DISCO board that is physically attached to this machine - install-firmware/connect/monitor CMake targets, OpenOCD + arm-none-eabi-gdb, reading boot logs and driving the dmell shell over the debug probe, and loading GDB symbols for dynamically loaded .dmf modules with add-symbol-file. Load this whenever a task involves running something on the real board, flashing firmware, attaching a debugger, reading firmware logs, reproducing a runtime bug, or debugging a dynamic module on target.
---

# Debugging dmod-boot on the STM32F746G-DISCO

The board is **physically connected to this machine** over ST-Link/V2.1
(`0483:374b`, VCP at `/dev/ttyACM0`). Flashing and debugging it is a normal,
expected part of the work - don't ask whether hardware is available, just use
it. Do ask before flashing if the user is in the middle of their own session on
the board.

## Layout

| What | Where |
| --- | --- |
| Firmware repo | `/data/projects/chocotechnologies/public/dmod-boot` |
| Build dir (already configured) | `<dmod-boot>/build` |
| Firmware ELF | `<dmod-boot>/build/dmboot.elf` |
| Modules staged into the ROM image | `<dmod-boot>/build/dmf/*.dmf` |
| Source of **every** dynamic module | `/data/projects/chocotechnologies/public/<module>` (e.g. `dmudp`, `dmell`, `dmeth`) |
| dmod library itself | `/data/projects/chocotechnologies/public/dmod` (also vendored as `<dmod-boot>/lib/dmod`) |

Current build config: `-DBOARD=stm32f746g-disco` (→ `TARGET=STM32F746xG`,
`DMOD_TOOLS_NAME=arch/armv7/cortex-m7`), `CMAKE_BUILD_TYPE=Debug`.
Re-configure from scratch with:

```bash
cmake -DBOARD=stm32f746g-disco -DCMAKE_BUILD_TYPE=Debug -S . -B build
```

## Build and flash

Run everything from `<dmod-boot>/build`:

```bash
cmake --build .                          # build firmware (+ fetch modules into build/dmf)
cmake --build . --target install-firmware # flash it
```

`install-firmware` runs
`openocd -f interface/stlink.cfg -f target/stm32f7x.cfg -c "program dmboot.elf verify reset exit"`
and exits. It needs exclusive access to the probe, so **stop a running
`connect` first** - two OpenOCD instances cannot share the ST-Link.

## Debug server and GDB

```bash
cmake --build . --target connect   # terminal 1: OpenOCD (gdb :3333, telnet :4444), keep running
```

Then, in terminal 2, either attach manually:

```bash
arm-none-eabi-gdb ./dmboot.elf
(gdb) target extended-remote localhost:3333
```

or let CMake do it - `cmake --build . --target debug` starts
`arm-none-eabi-gdb -x build/gdb_init.gdb dmboot.elf`, which connects, `load`s
the firmware, enables semihosting and breaks at `main`.

## Logs and the dmell shell

Firmware logs go into a dmlog ring buffer in RAM; `dmlog_monitor` reads it over
the debug probe and also feeds keystrokes back, so it doubles as an
**interactive dmell console** - available from very early boot, before any UART
driver is up. With `connect` running:

```bash
cmake --build . --target monitor      # OpenOCD telnet backend, port 4444
cmake --build . --target monitor-gdb  # GDB-server backend, port 3333
```

The ring-buffer address is extracted automatically from `dmboot.map` into
`build/dmlog_ring_buffer.cmake`.

Pick the backend by what else you're running: `monitor` (4444) coexists with a
GDB session on 3333, while `monitor-gdb` competes with GDB for port 3333.

**Non-interactive use** (the usual case for an agent - avoids sitting on an
interactive TTY). Call the tool directly with commands from a file:

```bash
ADDR=$(sed -n 's/.*DMLOG_RING_BUFFER_ADDR "\(.*\)".*/\1/p' build/dmlog_ring_buffer.cmake)
printf 'module list\nps\n' > /tmp/cmds
lib/dmlog/build_host/tools/monitor/dmlog_monitor --addr "$ADDR" --input-file /tmp/cmds
```

`--init-script FILE` does the same but switches to stdin afterwards. Other
useful flags: `--gdb --port 3333`, `--time`, `--trace-level verbose`,
`--blocking`, `--snapshot`.

Useful dmell commands: `module list|info|load|unload|enable|disable`, `ps`,
`uptime`, `setloglevel`, `ls`, `cat`, `catini`, `export`, `cd`, `pwd`.

Note: the default `dmtty.ini` leaves `/dev/tty` **unbound**, so it forwards to
kernel stdin/stdout (i.e. the dmlog path above) rather than the ST-Link VCP.
The VCP (USART1, PA9/PB7, 921600 8N1) only carries the shell if a `backing`
device is configured for it.

## Loading a module is not the same as enabling it

These are two distinct steps, and mixing them up produces a failure with no
error message anywhere:

| | What it does |
| --- | --- |
| `module load <name>` | Creates the module's context - its code is mapped, nothing has run |
| `module enable <name>` | Runs `dmod_init()`, **and loads+enables everything the module requires** (`Dmod_RMod_EnableRequiredModules()`) |

A module that is only *loaded* never runs `dmod_init()`, so it registers
nothing, and none of the APIs it imports have been bound yet. It therefore
sits there doing nothing - and because nothing was bound, nothing crashes
either. `module list` shows it with a text address like any other module;
only the context's `Enabled` flag tells the two apart.

Dependencies come in through the enable step, not the load step. Enabling
`dmicmp` is what pulls in `dmip`; loading `dmicmp` on its own leaves `dmip`
absent entirely, which looks exactly like a broken dependency declaration
but is not one.

**Application modules get both steps for free**: running an app does the same
load-then-enable, so its required modules are there by the time `main()` runs.
The distinction only bites for library modules, which something else has to
bring up - typically a `.dme` script run by a `libsystemd` unit, and such a
script needs *both* lines:

```
module load dmicmp
module enable dmicmp
```

`module enable` alone is not enough: `Dmod_EnableModule()` looks the context
up and fails with "module not found" if nothing loaded it first.

Checking the real state from GDB (`Enabled`, and `UsageCounter` for who is
holding the module resident) beats reading `module list`:

```
set $i=0
while $i < (int)(sizeof(Dmod_Contexts)/sizeof(Dmod_Contexts[0]))
  if Dmod_Contexts[$i] != 0
    printf "%2d %-14s en=%d use=%d\n", $i, Dmod_Contexts[$i]->Header->Name, \
           Dmod_Contexts[$i]->Enabled, Dmod_Contexts[$i]->UsageCounter
  end
  set $i=$i+1
end
```

`RequiredModules[]` on the same context lists what enabling will pull in.

## Debugging a dynamic module (.dmf) on target

Modules are position-independent blobs loaded at a runtime address, so GDB needs
the module's ELF and that address.

**1. Build the module for the target, with symbols.** In the module's own repo:

```bash
cd /data/projects/chocotechnologies/public/<module>
cmake -S . -B build-m7 \
      -DDMOD_TOOLS_NAME=arch/armv7/cortex-m7 \
      -DDMOD_DIR=/data/projects/chocotechnologies/public/dmod \
      -DCMAKE_BUILD_TYPE=Debug
cmake --build build-m7
```

This produces two things that matter:
- `build-m7/<module>` - **the ELF with debug symbols** (no extension; this is
  what `add-symbol-file` needs).
- `build-m7/dmf/<module>.dmf` - the loadable blob, literally
  `objcopy -O binary` of that ELF (see `dmod/scripts/CMakeLists.txt`).

A plain host build (`cmake -S . -B build`) gives you an x86 ELF - useless for
on-target symbols, fine for `dmod_loader` tests on the host. Sanity-check what
you got before blaming GDB:

```bash
file build-m7/<module>   # ... ELF 32-bit LSB executable, ARM, ... with debug_info, not stripped
```

`-DCMAKE_BUILD_TYPE=Debug` is what gets you `-Og` instead of `-O2`.

**2. Stage the .dmf into the firmware image:**

```bash
rm -f <dmod-boot>/build/dmf/<module>.dmfc          # see below - do not skip
cp build-m7/dmf/<module>.dmf <dmod-boot>/build/dmf/
rm -f <dmod-boot>/build/modules.dmp <dmod-boot>/build/__modules_dmp.o
cmake --build <dmod-boot>/build && cmake --build <dmod-boot>/build --target install-firmware
```

Two things bite here, both silently - the build succeeds and the board runs the
*old* module:

- **Delete the `.dmfc`.** `todmp` packs the whole `build/dmf/` directory and
  prefers the compressed `.dmfc` over the `.dmf` of the same name, so a stale
  `.dmfc` shadows the `.dmf` you just staged. `module list` on target shows
  such modules with version `compressed`.
- **Delete `modules.dmp` and `__modules_dmp.o`.** An incremental build does not
  notice a `.dmf` that was dropped in or overwritten in place.

Re-running `cmake ..` (any reconfigure) rewrites `combined_flash.dmd`, which
makes `dmf-get` re-download every module and **overwrite whatever you staged**.
Re-stage after any reconfigure.

**3. Find the load address.** Two sources, both authoritative:
- The boot log line emitted on every load
  (`dmod/src/system/dmod_system.c`, `Dmod_LoadModule`):
  `To debug module 'dmudp' in gdb: add-symbol-file <MODULE_ELF_FILE> 0xc0016668`
- `module list` in dmell - the **Text Addr** column.

**4. Load the symbols:**

```
(gdb) add-symbol-file /data/projects/chocotechnologies/public/<module>/build-m7/<module> 0xc0016668
(gdb) break <module>_some_function
```

The address changes between boots and whenever a module is unloaded/reloaded -
always re-read it for the current run instead of reusing an old one.

## Inspecting RTOS state (threads, stalls, stack overflows)

OpenOCD can present FreeRTOS tasks as GDB threads - start it with RTOS
awareness instead of the plain `connect` target:

```bash
openocd -f interface/stlink.cfg -f target/stm32f7x.cfg \
        -c "stm32f7x.cpu configure -rtos FreeRTOS"
```

`info threads` then lists every task by name. Note that non-running tasks
unwind poorly (the saved PC is trustworthy, the backtrace above it usually is
not), so for "who is stuck / who is hogging the CPU" read the scheduler's own
lists rather than backtraces. `TCB_t` is in `dmboot.elf`'s debug info, so GDB
can walk them directly - do not hand-compute TCB offsets, and note that
OpenOCD's thread id is *not* the TCB address:

```
printf "current=%s prio=%d\n", pxCurrentTCB->pcTaskName, pxCurrentTCB->uxPriority
# ready lists: anything permanently here while lower-priority tasks starve is a
# task that polls without blocking
set $l = &pxReadyTasksLists[1]
set $it = $l->xListEnd.pxNext
printf "%s prio=%d\n", ((TCB_t*)$it->pvOwner)->pcTaskName, ((TCB_t*)$it->pvOwner)->uxPriority
```

Also useful: `xSuspendedTaskList` (properly blocked tasks),
`xTasksWaitingTermination` (finished processes IDLE has not reaped - a
non-empty list plus a starved IDLE means something is hogging priority 0),
and `uxSchedulerSuspended`.

**Measuring a thread's real stack usage.** FreeRTOS fills new stacks with
`0xa5`; the untouched run at the *low* end is the headroom (stacks grow down).
Dump from `pxStack` for the thread's configured size and count:

```bash
arm-none-eabi-gdb -batch -ex "target extended-remote localhost:3333" \
  -ex "monitor halt" -ex "dump binary memory /tmp/stack.bin 0x2002a794 0x2002b994" dmboot.elf
python3 -c "d=open('/tmp/stack.bin','rb').read(); n=0
for b in d:
    if b!=0xa5: break
    n+=1
print('untouched',n,'peak used',len(d)-n)"
```

This turns "the stack looks too small" into a number, which is what a stack
size should be justified by. Thread stack sizes are `<N> +
DMOSI_THREAD_STACK_OVERHEAD` (512), so the region is `N + 512` bytes.

## Gotchas that cost time

- **The dmlog ring-buffer address moves on every relink.** `--addr` from a
  previous session gives `Invalid dmlog ring buffer magic number`. Re-extract:
  `python3 scripts/extract_ring_buffer_addr.py build/dmboot.map --output
  build/dmlog_ring_buffer.cmake --format cmake`.
- **Capture logs across the reset, not after it.** Start `dmlog_monitor` first,
  then `reset run` via telnet 4444 - otherwise the ring buffer has already
  wrapped and the boot log comes back shredded.
- **`lib/dmosi` is not what gets built.** `lib/dmosi-freertos` pulls dmosi via
  FetchContent from GitHub `main` into `build/_deps/dmosi-src`, so edits to the
  `lib/dmosi` submodule are ignored (unlike `lib/dmod`, which is used because
  `dmod_inc` already exists as a target). To build against a local dmosi:
  `cmake -DFETCHCONTENT_SOURCE_DIR_DMOSI=<path-to-dmosi> ..`. Check what
  actually linked with `arm-none-eabi-nm dmboot.elf | grep <symbol>` - a `W`
  means the weak default won, `T` means the real implementation did.

## Host-side alternative

For logic bugs that don't need real peripherals, run the module under
`dmod_loader` on the host instead - `dmod_loader <module>.dmf --debug <elf>`
pauses after load and writes `dmod_debug.sh`/`dmod_gdb_script.gdb` with the
right address. See `dmod/docs/module-debugging.md`.

## Renode

`-DDMBOOT_EMULATION=ON` swaps OpenOCD for Renode; `install-firmware`, `connect`
and `monitor-gdb` behave the same way. The current `build/` is **hardware
mode** - configure a separate build dir if you want emulation, don't flip the
existing one.
