/**
 * @brief Fault handling for the Xtensa LX7 (ESP32-S3)
 *
 * The architecture's part of the dmosi Fault API (see dmosi.h) - what src/arch/armv7/fault.c is for the Cortex-M: every
 * general exception of the core that the port of FreeRTOS does not take for itself (the interrupts, the window overflow
 * and underflow, alloca, the system call, the coprocessors) lands here, is described as a dmosi_fault_t and is offered to
 * the OS with dmosi_thread_fault().
 *
 * If the OS can contain the fault to the process of the thread that was interrupted, the code that faulted is abandoned:
 * the exception frame the vector saved on the stack of the thread is rewritten so that the return from the exception
 * continues in the entry the OS chose, on the thread's own stack rewound to the top, as if the thread had just been
 * started there. Otherwise nothing can vouch for the state of the system any more, and it halts with the fault in the
 * kernel log.
 *
 * What makes a stack overflow fault at the moment it happens is the data breakpoints of the core: the stack guard of the
 * thread that runs (dmosi_stack_guard_select()) is the lowest part of its stack above a stretch of room to handle the
 * overflow in, and a write to it is a debug exception. It arrives at the debug level, where nothing of the OS can run, and is
 * turned into a call on a stack of its own (fault_asm.S) from where the OS is asked what to do the same way as for the
 * general exceptions.
 */
#include "dmod.h"
#include "dmosi.h"
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "FreeRTOS.h"
#include "xtensa/corebits.h"
#include "xtensa/config/core.h"
#include "xtensa_context.h"

/* The table of the handlers of the exceptions of xtensa_intr_asm.S, and the one it starts with */
typedef void ( * exception_handler_t )( XtExcFrame * );
extern exception_handler_t _xt_exception_table[ XCHAL_EXCCAUSE_NUM ];
extern void xt_unhandled_exception( void * frame );

/* Where an exception returns to when the thread is resumed in an entry (fault_asm.S) */
extern void dmboot_fault_trampoline( void );

/* port.c of the port: the core is running a handler of an interrupt */
extern BaseType_t xPortInIsrContext( void );

/**
 * @brief Describe the exception the core has just taken
 *
 * @param fault Description to fill in
 * @param frame Frame the vector saved on the stack of the thread
 */
static void describe_fault( dmosi_fault_t* fault, const XtExcFrame* frame )
{
    const uint32_t cause = (uint32_t)frame->exccause;

    fault->thread = NULL;
    fault->pc = (uintptr_t)frame->pc;
    fault->sp = (uintptr_t)frame->a1;
    fault->has_address = false;
    fault->address = 0;

    switch( cause )
    {
        case EXCCAUSE_DIVIDE_BY_ZERO:
            fault->type = DMOSI_FAULT_ARITHMETIC;
            break;

        case EXCCAUSE_ILLEGAL:
        case EXCCAUSE_PRIVILEGED:
        case EXCCAUSE_EXTREG_PRIVILEGE:
            fault->type = DMOSI_FAULT_ILLEGAL_INSTRUCTION;
            break;

        /* A fetch of an instruction from where there is none: the address is the one of the instruction */
        case EXCCAUSE_INSTR_ERROR:
        case EXCCAUSE_INSTR_DATA_ERROR:
        case EXCCAUSE_INSTR_ADDR_ERROR:
        case EXCCAUSE_ITLB_MISS:
        case EXCCAUSE_ITLB_MULTIHIT:
        case EXCCAUSE_INSTR_RING:
        case EXCCAUSE_INSTR_PROHIBITED:
        case EXCCAUSE_PC_ERROR:
            fault->type = DMOSI_FAULT_MEMORY_ACCESS;
            fault->has_address = true;
            fault->address = (uintptr_t)frame->excvaddr;
            break;

        case EXCCAUSE_LOAD_STORE_ERROR:
        case EXCCAUSE_UNALIGNED:
        case EXCCAUSE_EXCLUSIVE_ERROR:
        case EXCCAUSE_LOAD_STORE_DATA_ERROR:
        case EXCCAUSE_LOAD_STORE_ADDR_ERROR:
        case EXCCAUSE_DTLB_MISS:
        case EXCCAUSE_DTLB_MULTIHIT:
        case EXCCAUSE_LOAD_STORE_RING:
        case EXCCAUSE_LOAD_PROHIBITED:
        case EXCCAUSE_STORE_PROHIBITED:
            fault->type = DMOSI_FAULT_MEMORY_ACCESS;
            fault->has_address = true;
            fault->address = (uintptr_t)frame->excvaddr;
            break;

        default:
            fault->type = DMOSI_FAULT_UNKNOWN;
            break;
    }
}

/**
 * @brief Check whether the exception interrupted a thread that can be taken off its code path
 *
 * It cannot when the exception did not interrupt a thread at all (it interrupted the handler of an interrupt), or
 * interrupted it with interrupts masked: a critical section protects a state that is then left half-updated, and nobody
 * would ever unmask the interrupts.
 *
 * @param frame Frame the vector saved on the stack of the thread
 * @return bool true if the interrupted context is a thread with interrupts enabled
 */
static bool interrupted_preemptible_thread( const XtExcFrame* frame )
{
    return xPortInIsrContext() == pdFALSE && ( (uint32_t)frame->ps & PS_INTLEVEL_MASK ) == 0U;
}

/**
 * @brief Make the return from the exception continue in the entry the OS chose for the faulting thread
 *
 * The frame is what the vector restores the registers from: the thread continues where the frame says, with what it
 * says, on the stack that it says - the stack of the thread rewound to the top. The entry is not called from the
 * handler but from a trampoline (fault_asm.S) that first forgets the register windows of the abandoned code, and passes
 * the argument.
 *
 * @param frame Frame the vector saved on the stack of the thread
 * @param recovery Where the thread continues, from dmosi_thread_fault()
 */
static void resume_thread( XtExcFrame* frame, const dmosi_fault_recovery_t* recovery )
{
    frame->pc = (UBaseType_t)dmboot_fault_trampoline;
    frame->a0 = 0;
    frame->a1 = (UBaseType_t)( (uintptr_t)recovery->stack_top & ~(uintptr_t)0xFU );
    frame->a2 = (UBaseType_t)(uintptr_t)recovery->arg;
    frame->a3 = (UBaseType_t)(uintptr_t)recovery->entry;

    /* No call is pending (the entry is not called, it is returned to), and no zero-overhead loop of the abandoned code */
    frame->ps &= ~(UBaseType_t)PS_CALLINC_MASK;
#if XCHAL_HAVE_LOOPS
    frame->lcount = 0;
#endif
}

/**
 * @brief Halt the system on a fault that cannot be contained
 *
 * @param fault Description of the fault
 * @param frame Frame the vector saved on the stack of the thread
 */
static void halt_system( const dmosi_fault_t* fault, const XtExcFrame* frame )
{
    /* System state is suspect, and the normal Dmod_Printf path (Dmod_LockStdio ->
     * dmosi_process_current() -> ...) can fault a second time on it: raw kernel writes only */
    Dmod_SetForceKernelWrite( true );
    DMOD_LOG_ERROR( "Fatal fault: pc=0x%08lX a0=0x%08lX sp=0x%08lX exccause=%lu excvaddr=0x%08lX ps=0x%08lX\n",
                    (unsigned long)frame->pc, (unsigned long)frame->a0, (unsigned long)frame->a1,
                    (unsigned long)frame->exccause, (unsigned long)fault->address, (unsigned long)frame->ps );
    DMOD_ASSERT_MSG( false, "A fault that cannot be contained to a process occurred. System halted." );
    for( ;; )
    {
    }
}

/**
 * @brief Handler of the general exceptions of the core
 *
 * Called by the user exception vector of the port (xtensa_vectors.S) on the stack of the thread, with the frame it
 * saved the registers of the thread in. If it returns, the registers are restored from the frame.
 *
 * @param frame Frame the vector saved on the stack of the thread
 */
static void fault_exception( XtExcFrame* frame )
{
    dmosi_fault_t fault;
    dmosi_fault_recovery_t recovery;

    describe_fault( &fault, frame );

    if( interrupted_preemptible_thread( frame ) && dmosi_thread_fault( &fault, &recovery ) )
    {
        resume_thread( frame, &recovery );
        return;
    }

    halt_system( &fault, frame );
}

/**
 * @brief Take over the exceptions of the core that nobody has a handler for
 *
 * Called before the scheduler starts. The ones the port handles itself never reach the table; an exception that has a
 * handler of its own installed keeps it.
 */
void dmboot_xtensa_fault_init( void )
{
    for( size_t cause = 0; cause < XCHAL_EXCCAUSE_NUM; cause++ )
    {
        if( _xt_exception_table[ cause ] == (exception_handler_t)xt_unhandled_exception )
        {
            _xt_exception_table[ cause ] = fault_exception;
        }
    }
}

/* Where the data breakpoints of the core put the guard of a stack: the room below it is where the overflow is handled, and the
 * exception frame is saved, while the thread is still on that stack (the guard is hit before the end of the stack) */
#define STACK_GUARD_SLACK       512U
#define STACK_GUARD_REGION      64U     /* the size of a data breakpoint of the core; there are two of them */
#define STACK_GUARD_MIN_ROOM    512U    /* the stack above the guard that is worth guarding */
#define DBREAKC_STORE           ( 1UL << 31 )

/**
 * @brief Move the stack guard to the stack of the thread that is switched to
 *
 * Two data breakpoints over STACK_GUARD_REGION bytes each, side by side, which break on a store (a load of the guard is
 * harmless, and the kernel's own check reads it). A stack that has no room for the guard is left unguarded.
 *
 * @param stack_base Lowest address of the stack of the thread
 * @param stack_size Size of the stack in bytes
 */
void dmosi_stack_guard_select( const void* stack_base, size_t stack_size )
{
    const uintptr_t base = (uintptr_t)stack_base;
    const uintptr_t start = ( base + STACK_GUARD_SLACK + STACK_GUARD_REGION - 1U ) & ~( (uintptr_t)STACK_GUARD_REGION - 1U );
    const bool fits = stack_base != NULL && stack_size >= ( start - base ) + 2U * STACK_GUARD_REGION + STACK_GUARD_MIN_ROOM;
    const uint32_t control = fits ? DBREAKC_STORE : 0U;   /* mask 0: the whole region, none of the low bits compared */

    __asm__ volatile(
        "wsr.dbreakc0 %2\n"
        "wsr.dbreakc1 %2\n"
        "wsr.dbreaka0 %0\n"
        "wsr.dbreaka1 %1\n"
        "isync\n"
        :
        : "r"( (uint32_t)start ), "r"( (uint32_t)( start + STACK_GUARD_REGION ) ), "r"( control )
        : "memory" );
}

/* Where the debug exception left what it took from the abandoned code, and where the thread continues (fault_asm.S) */
struct guard_hit
{
    uint32_t pc;
    uint32_t sp;
    uint32_t ps;
};
struct guard_recovery
{
    uint32_t stack_top;
    uint32_t arg;
    uint32_t entry;
};
struct guard_hit dmboot_guard_hit;
struct guard_recovery dmboot_guard_recovery;

/* The stack the overflow is handled on (the interrupts are masked, so there is one user at a time) */
static uint8_t g_guard_stack[ 2048 ] __attribute__( ( aligned( 16 ) ) );
uint8_t* const dmboot_guard_stack_top = g_guard_stack + sizeof( g_guard_stack );

/**
 * @brief Handle the overflow of a stack that the guard caught (called from fault_asm.S on its own stack)
 *
 * Returns only when the thread can be contained: it is resumed in the entry that is put in dmboot_guard_recovery.
 */
void dmboot_xtensa_guard_fault( void )
{
    dmosi_fault_t fault;
    dmosi_fault_recovery_t recovery;

    fault.type = DMOSI_FAULT_STACK_OVERFLOW;
    fault.thread = NULL;
    fault.pc = dmboot_guard_hit.pc;
    fault.sp = dmboot_guard_hit.sp;
    fault.has_address = false;
    fault.address = 0;

    /* Interrupts masked (INTLEVEL of the abandoned code), or the exception not of a thread: not containable */
    if( xPortInIsrContext() == pdFALSE && ( dmboot_guard_hit.ps & PS_INTLEVEL_MASK ) == 0U &&
        dmosi_thread_fault( &fault, &recovery ) )
    {
        dmboot_guard_recovery.stack_top = (uint32_t)( (uintptr_t)recovery.stack_top & ~(uintptr_t)0xFU );
        dmboot_guard_recovery.arg = (uint32_t)(uintptr_t)recovery.arg;
        dmboot_guard_recovery.entry = (uint32_t)(uintptr_t)recovery.entry;
        return;
    }

    Dmod_SetForceKernelWrite( true );
    DMOD_LOG_ERROR( "Fatal stack overflow: pc=0x%08lX sp=0x%08lX ps=0x%08lX\n", (unsigned long)dmboot_guard_hit.pc,
                    (unsigned long)dmboot_guard_hit.sp, (unsigned long)dmboot_guard_hit.ps );
    DMOD_ASSERT_MSG( false, "A fault that cannot be contained to a process occurred. System halted." );
    for( ;; )
    {
    }
}
