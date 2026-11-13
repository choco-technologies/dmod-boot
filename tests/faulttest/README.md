# faulttest

A test application that crashes on purpose, to check that a fault of a process
is contained to that process (see `src/arch/armv7/fault.c` and the Fault API of
dmosi): the fault is reported on the standard output of the process, the
process is terminated and the shell keeps working.

```
faulttest undef     execute an undefined instruction
faulttest state     jump to an address without the Thumb bit
faulttest access    read from an address nothing is mapped at (the emulator answers it, a board faults)
faulttest stack     recurse until the stack is exhausted
faulttest ok        do nothing wrong and return 0
```

It is not part of the firmware: `scripts/test_renode_fault.py` uses it in the
Renode tests, and it can be staged into `build/dmf` by hand to try the same on
a board (see the `dmod-board-debugging` skill).

```bash
cmake -S tests/faulttest -B build/faulttest -DDMOD_TOOLS_NAME=arch/armv7/cortex-m7
cmake --build build/faulttest
```
