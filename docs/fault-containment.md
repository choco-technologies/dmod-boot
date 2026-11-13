# Containing a crash to the process that caused it

An application that runs out of stack, or that the CPU refuses to run (an invalid memory access, an undefined
instruction, ...), does not stop the system. The application is told about it on the standard output it was
working on, its process is terminated, and the system - the shell included - goes on.

```
stm32f746xg@/> faulttest undef
Executing an undefined instruction...

*** faulttest: illegal instruction in thread 'faulttest' (pid 12)
    pc=0xC0039E58 sp=0xC001C3C8
    Process terminated.
stm32f746xg@/>
```

## Who does what

The Fault API of [dmosi](https://github.com/choco-technologies/dmosi) (`dmosi.h`) splits the job by what each layer
knows. Nothing in a layer reaches into another one.

| Layer | Where | Does |
| --- | --- | --- |
| Architecture | `src/arch/armv7/fault.c` (this repo) | Takes the fault exceptions, describes the fault (`dmosi_fault_t`), asks the OS what to do, and abandons the code that faulted the way the OS says. Keeps an MPU guard under the stack of the running thread. |
| Thread backend | `dmosi-freertos` | `dmosi_thread_fault()`: decides whether the fault can be contained, and where the thread continues. Finds stack overflows that nothing faulted for. |
| Process backend | `dmosi-proc` | `dmosi_process_fault()`: reports on the standard output *of the process* and kills it. |
| Shell | `dmell` | Runs every command as a process of its own - the process is what a crash can be contained to. |

### A fault raised by the CPU

```
 CPU exception (MemManage / BusFault / UsageFault / HardFault)
   -> dmboot_fault_handler: describes the fault
   -> dmosi_thread_fault(): contained?  no -> halt, the fault in the kernel log
                                        yes -> recovery = { entry, arg, empty stack }
   -> the exception returns to recovery.entry, on the stack of the faulting thread, rewound to the top
   -> entry: hands the thread over to the fault supervisor (a thread of the system with a stack of its own) and waits
   -> supervisor: dmosi_process_fault(process, fault)
        report on stdout of the process, kill the process
        -> its threads are killed, the module it ran is unloaded (exit callback of the process)
```

The exception return is the only way out of the code that faulted: the thread is not unwound, it is resumed as if it
had just been created. Nothing it held is released - memory a module allocated is freed with the module, but a lock
it took stays taken.

The report and the termination are not done by the faulting thread. Its stack is the one of the application, sized
for what the application does; printing through the terminal and the driver underneath, running the exit callbacks
and unloading the module needs more than that (on the STM32F746G-DISCO it overran the 3 KiB stack of a process that
had just crashed, and the second fault of the same thread halted the system). The same supervisor handles a stack
overflow the kernel finds in a context switch, where nothing can be printed or killed at all.

A fault is **not** contained - the system halts, as it always did - when
- it happened in an interrupt handler, or in a thread with interrupts masked (a critical section protects a state that
  would be left half-updated),
- the scheduler is not running yet,
- the thread is not one of a process, or belongs to the system process (the firmware's own threads),
- the thread faulted again while its fault was being handled.

### The stack

A software check finds an overflow only at the next context switch, after the code has written over what lies below the
stack - in dmheap that is the metadata of the neighbouring block, and the system is gone with it. So the overflow
has to fault at the first byte:

- On every switch to a thread the RTOS tells the architecture its stack (`dmosi_stack_guard_select()`).
- The MPU (region 7, which has to win over the SDRAM region 6 of `dmfmc`) makes `DMOSI_STACK_GUARD_SIZE` (256) bytes
  above the lowest bytes of the stack **read-only**. Read-only, not inaccessible: the kernel scans the stack from its
  lowest address to find its high water mark. A push or a store there faults.
- The CPU may not even be able to push the frame of the exception (the stack pointer is in the guard): the handler copes
  with that and recognises the stack overflow by the stack pointer.
- `dmosi_thread_create()` adds `DMOSI_STACK_GUARD_RESERVE` bytes to the stack, for the guard and its alignment.
  Stacks smaller than 1 KiB (the idle task) are not guarded, and neither is the first thread the scheduler starts, until
  its first context switch.
- A function that allocates a frame larger than the guard can jump over it. `DMOSI_STACK_GUARD_SIZE` is the largest frame
  that is certain to be caught. Where there is no MPU (or no architecture code for it) the check of the kernel is what is
  left: a stack overflow it finds is handled the same way, by a supervisor thread, but whatever the overflow wrote
  over is lost.

### The Xtensa LX7 (ESP32-S3)

`src/arch/xtensa/lx7/fault.c` is what `src/arch/armv7/fault.c` is, on the same Fault API.

- The general exceptions the port of FreeRTOS does not take for itself (illegal instruction, a load, store or fetch that
  faults, ...) are taken over in its exception table. The handler runs on the stack of the thread, with the frame the
  vector saved; to contain the fault it **rewrites that frame** (pc, a1 = top of the stack, the argument and the entry) so
  that the return from the exception continues in the entry the OS chose. The way there goes through a trampoline
  (`fault_asm.S`) that first forgets the register windows of the abandoned code: WINDOWSTART would otherwise have the
  core spill them over the frames of the entry.
- The stack guard are the two **data breakpoints** of the core (64 bytes each, on stores), moved to the thread that is
  switched to. They sit above 512 bytes of room, which is where the exception frame and the handler fit when the guard is
  hit. The debug exception arrives at the debug level, where nothing of the OS can run: `xt_debugexception` saves what is
  needed, and returns onto a stack of its own where the same question is asked of the OS. Not containable (an
  interrupt handler, interrupts masked, a second fault of the thread, no supervisor): the system halts with a message.
- The data breakpoints are what a debugger uses for watchpoints: a watchpoint set from OpenOCD takes them over.
- `faulttest undef|access|stack|stackfw` were run on an ESP32-S3 board; 40 stack overflows in a row leave the shell as it was.

## Testing

- `scripts/test_renode_fault.py` (step 5b of `scripts/run_renode_tests.sh`): the board in Renode runs `tests/faulttest`,
  which crashes on purpose; the report, the end of the process, the shell and a second run are checked.
- `tests/fault_mpu/run.sh`: the guard of the stack and the handlers on an emulated Cortex-M7 with QEMU. Renode does not
  model the access rights of the MPU (a write to a read-only region goes through), so this is where they are checked.
- On a board: `faulttest stack` (recursion until the stack is gone) and `faulttest access` (a read of an address nothing
  is mapped at) - stage the module as described in the `dmod-board-debugging` skill.
