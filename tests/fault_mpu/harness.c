/**
 * @brief Test of the stack guard and of the fault exception handlers of the ARMv7-M port, on an emulated Cortex-M7
 *
 * Links the real src/arch/armv7/fault.c with a few stubs (see run.sh). A thread runs in Thread mode on the
 * process stack, the way the RTOS runs its threads, with the guard of dmosi_stack_guard_select() in place:
 *
 *  1. a write into the guard faults, and the fault is reported as a stack overflow of the thread that made it, which is
 *     resumed in the entry that dmosi_thread_fault() chose, on an empty stack;
 *  2. an exception taken with the stack pointer inside the guard - the CPU cannot push the frame of the exception -
 *     is handled the same way, with no frame to read the program counter from.
 *
 * The output goes through semihosting; run.sh checks it.
 */
#include <stdint.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdbool.h>
#include "dmosi.h"

extern void dmosi_stack_guard_select(const void*, size_t);
extern void HardFault_Handler(void);
extern void MemManage_Handler(void);
extern void BusFault_Handler(void);
extern void UsageFault_Handler(void);

/* ---- semihosting ---- */
static void sh(int op, const void* arg) { register int r0 __asm("r0") = op; register const void* r1 __asm("r1") = arg; __asm volatile("bkpt 0xAB" : "+r"(r0) : "r"(r1) : "memory"); }
static void say(const char* s) { sh(0x04, s); }
static void hex(const char* label, uint32_t v) { char b[40]; int n=0; while(*label) b[n++]=*label++; b[n++]='='; for(int i=28;i>=0;i-=4){ b[n++]="0123456789abcdef"[(v>>i)&15]; } b[n++]='\n'; b[n]=0; say(b); }
static void quit(int ok) { uint32_t blk[2] = { ok ? 0x20026u : 0x20023u, 0 }; sh(0x18, blk); for(;;); }

/* ---- stubs the fault code needs ---- */
void Dmod_SetForceKernelWrite(bool e) { (void)e; }
void Dmod_Assert(int c, const char* m, const char* f, int l, const char* fn) { (void)c;(void)f;(void)l;(void)fn; say("HALT: "); say(m); say("\n"); quit(0); }
bool Dmod_CheckLogLevel(int l) { (void)l; return true; }
void* Dmod_GetStreamLogFile(int l) { (void)l; return 0; }
int Dmod_FPrintf(void* f, const char* fmt, ...)
{
    (void)f; char b[300]; int n = 0; va_list a; va_start(a, fmt);
    for (; *fmt && n < 280; fmt++) {
        if (*fmt != '%') { b[n++] = *fmt; continue; }
        fmt++; if (*fmt == '0') { fmt++; } while (*fmt >= '0' && *fmt <= '9') fmt++; if (*fmt == 'l') fmt++;
        if (*fmt == 'X' || *fmt == 'x') { uint32_t v = va_arg(a, uint32_t); for (int i = 28; i >= 0; i -= 4) b[n++] = "0123456789ABCDEF"[(v >> i) & 15]; }
        else if (*fmt == 's') { const char* t = va_arg(a, const char*); while (*t) b[n++] = *t++; }
        else if (*fmt == 'p') { uint32_t v = (uint32_t)va_arg(a, void*); b[n++]='0'; b[n++]='x'; for (int i = 28; i >= 0; i -= 4) b[n++] = "0123456789ABCDEF"[(v >> i) & 15]; }
        else { b[n++] = '%'; b[n++] = *fmt; }
    }
    b[n] = 0; va_end(a); say(b); return 0;
}
int Dmod_Printf(const char* f, ...) { say(f); return 0; }
bool Dmod_IsInsideInterrupt(void) { return false; }

static uint8_t task_stack[4096] __attribute__((aligned(256)));
static volatile int expect_fatal;
static dmosi_fault_t last;
static volatile int phase;

static void recovered(void* arg)
{
    (void)arg;
    say("RECOVERED in thread context\n");
    hex("  type", last.type); hex("  pc", last.pc); hex("  sp", last.sp);
    hex("  has_address", last.has_address); hex("  address", last.address);
    if (phase == 1) { phase = 2; extern void run_phase2(void); run_phase2(); }
    say("ALL PHASES DONE\n");
    quit(1);
}

bool dmosi_thread_fault(const dmosi_fault_t* f, dmosi_fault_recovery_t* r)
{
    say("thread_fault called\n"); last = *f;
    r->entry = recovered; r->arg = 0; r->stack_top = task_stack + sizeof(task_stack);
    return !expect_fatal;
}

static void enter_thread(uint32_t sp, void (*fn)(void))
{
    __asm volatile("msr psp, %0\n mov r0, #2\n msr control, r0\n isb\n bx %1" :: "r"(sp), "r"(fn) : "r0");
}

static uintptr_t guard_start(void) { return ((uintptr_t)task_stack + 16 + 255) & ~255u; }

static void write_into_guard(void)
{
    say("phase1: writing into the guard from thread mode\n");
    *(volatile uint32_t*)(guard_start() + 8) = 1;
    say("NOT FAULTED (guard did not work)\n"); quit(0);
}

static void undef_with_sp_in_guard(void)
{
    say("phase2: exception with the stack pointer inside the guard (stacking fails)\n");
    __asm volatile("udf #0");
    say("NOT FAULTED\n"); quit(0);
}

void run_phase2(void)
{
    /* the thread is resumed on an empty stack; for the test, put its SP in the guard and fault again */
    enter_thread(guard_start() + 128, undef_with_sp_in_guard);
}

void reset(void)
{
    say("harness start\n");
    dmosi_stack_guard_select(task_stack, sizeof(task_stack));
    hex("MPU_RASR7", (({ *(volatile uint32_t*)0xE000ED98 = 7; *(volatile uint32_t*)0xE000EDA0; })));
    phase = 1;
    enter_thread((uint32_t)task_stack + sizeof(task_stack) - 64, write_into_guard);
}

extern uint32_t _estack;
__attribute__((section(".vectors"), used)) const void* vectors[16] = {
    &_estack, reset, 0, HardFault_Handler, MemManage_Handler, BusFault_Handler, UsageFault_Handler, 0,0,0,0,0,0,0,0,0
};
