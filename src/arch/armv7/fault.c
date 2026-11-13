/**
 * @brief Fault handling for the ARMv7-M architecture (Cortex-M4/M7)
 *
 * The architecture's part of the dmosi Fault API (see dmosi.h): every fault
 * exception of the CPU lands here, is described as a dmosi_fault_t and is
 * offered to the OS with dmosi_thread_fault().
 *
 * If the OS can contain the fault to the process of the thread that was
 * interrupted, the code that faulted is abandoned: the exception returns to
 * the entry the OS chose, on the thread's own stack rewound to the top, as
 * if the thread had just been started there. The OS then reports the fault
 * on the standard output of the process and terminates it; the rest of the
 * system keeps running.
 *
 * Otherwise nothing can vouch for the state of the system any more, and it
 * halts with the fault in the kernel log.
 *
 * A stack overflow is made to fault at the moment it happens: the thread
 * backend tells the architecture the stack of every thread it switches to
 * (dmosi_stack_guard_select()), and an MPU region over the lowest part of it
 * makes any write there a MemManage fault.
 */
#include "dmod.h"
#include "dmosi.h"
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* System Control Block: fault status and address registers */
#define SCB_CFSR                (*(volatile uint32_t*)0xE000ED28UL)
#define SCB_HFSR                (*(volatile uint32_t*)0xE000ED2CUL)
#define SCB_MMFAR               (*(volatile uint32_t*)0xE000ED34UL)
#define SCB_BFAR                (*(volatile uint32_t*)0xE000ED38UL)
/* Memory Protection Unit */
#define MPU_TYPE                (*(volatile uint32_t*)0xE000ED90UL)
#define MPU_CTRL                (*(volatile uint32_t*)0xE000ED94UL)
#define MPU_RNR                 (*(volatile uint32_t*)0xE000ED98UL)
#define MPU_RBAR                (*(volatile uint32_t*)0xE000ED9CUL)
#define MPU_RASR                (*(volatile uint32_t*)0xE000EDA0UL)
#define SCB_SHCSR               (*(volatile uint32_t*)0xE000ED24UL)
#define SHCSR_MEMFAULTENA       (1UL << 16)
#define SHCSR_BUSFAULTENA       (1UL << 17)
#define SHCSR_USGFAULTENA       (1UL << 18)
#define MPU_TYPE_DREGION        0x0000FF00UL
#define MPU_CTRL_ENABLE         (1UL << 0)
#define MPU_CTRL_PRIVDEFENA     (1UL << 2)
#define MPU_RASR_ENABLE         (1UL << 0)
#define MPU_RASR_XN             (1UL << 28)
#define MPU_RASR_AP_PRIV_RO     (5UL << 24)     /* privileged read-only, no access from unprivileged code */
/* The same memory attributes as the SDRAM and the SRAM have (TEX=001 C=1 B=1: Normal, write-back): the guard overrides
 * the region the stack is in, and reading the stack through other attributes than it was written with would be incoherent */
#define MPU_RASR_WRITE_BACK     ( ( 1UL << 19 ) | ( 1UL << 17 ) | ( 1UL << 16 ) )

/* Floating-point context control: lazy state preservation */
#define FPU_FPCCR               (*(volatile uint32_t*)0xE000EF34UL)

/* MPU region of the stack guard: the highest one, as it has to win over the SDRAM region (6, dmfmc) the stacks are in */
#define STACK_GUARD_MPU_REGION  7U
/* A stack smaller than this is not guarded, nor is one the guard would leave less room above it than this */
#define STACK_GUARD_MIN_STACK_SIZE  ( 4U * DMOSI_STACK_GUARD_SIZE )
#define STACK_GUARD_MIN_ROOM        ( 2U * DMOSI_STACK_GUARD_SIZE )

/* The bytes at the lowest addresses of a stack that the kernel checks (stack_macros.h: the 4 words of 0xa5a5a5a5) */
#define STACK_CANARY_SIZE       16U

#define CFSR_MEMFAULT_MASK      0x000000FFUL
#define CFSR_MSTKERR            (1UL << 4)      /* MemManage fault on exception entry stacking */
#define CFSR_MMARVALID          (1UL << 7)      /* MMFAR holds the faulting address */
#define CFSR_BUSFAULT_MASK      0x0000FF00UL
#define CFSR_STKERR             (1UL << 12)     /* BusFault on exception entry stacking */
#define CFSR_BFARVALID          (1UL << 15)     /* BFAR holds the faulting address */
#define CFSR_UNDEFINSTR         (1UL << 16)
#define CFSR_INVSTATE           (1UL << 17)
#define CFSR_INVPC              (1UL << 18)
#define CFSR_NOCP               (1UL << 19)
#define CFSR_UNALIGNED          (1UL << 24)
#define CFSR_DIVBYZERO          (1UL << 25)
#define CFSR_ILLEGAL_MASK       (CFSR_UNDEFINSTR | CFSR_INVSTATE | CFSR_INVPC | CFSR_NOCP)
#define HFSR_FORCED             (1UL << 30)     /* a configurable fault escalated to HardFault */
#define FPCCR_LSPACT            (1UL << 0)      /* lazy FP state preservation is pending */

/* EXC_RETURN: the exception was taken from Thread mode running on the process stack */
#define EXC_RETURN_MODE_MASK    0x0000000FUL
#define EXC_RETURN_THREAD_PSP   0x0000000DUL
/* EXC_RETURN: return to Thread mode, process stack, basic (no FP) frame */
#define EXC_RETURN_TO_THREAD    0xFFFFFFFDUL

#define XPSR_THUMB              (1UL << 24)
/* Return address of the entry a thread is resumed in: the entry never returns, and this is not executable */
#define RETURN_ADDRESS_NONE     0xFFFFFFFFUL

/**
 * @brief Registers the CPU pushes on the stack when it takes an exception
 */
typedef struct
{
    uint32_t r0;
    uint32_t r1;
    uint32_t r2;
    uint32_t r3;
    uint32_t r12;
    uint32_t lr;
    uint32_t pc;
    uint32_t xpsr;
} exception_frame_t;

/* The guard that is set up for the thread that is running: kept to recognise an access to it as a stack overflow */
static volatile uintptr_t g_guard_start;
static volatile uintptr_t g_guard_end;

/**
 * @brief Enable the MPU and the fault exceptions of the CPU, once
 *
 * The default memory map stays in force for the privileged code (PRIVDEFENA): only the guard is added to it.
 *
 * @return bool true if the CPU has an MPU
 */
static bool enable_protection( void )
{
    if( ( MPU_TYPE & MPU_TYPE_DREGION ) == 0U )
    {
        return false;
    }

    /* Without the dedicated exceptions every fault escalates to a HardFault: it is handled the same, but the
     * fault status registers are the only way to tell them apart. The MPU may already be on (the cache setup
     * uses it for the log buffer): these are not */
    if( ( SCB_SHCSR & SHCSR_MEMFAULTENA ) == 0U )
    {
        SCB_SHCSR |= SHCSR_MEMFAULTENA | SHCSR_BUSFAULTENA | SHCSR_USGFAULTENA;
    }

    if( ( MPU_CTRL & MPU_CTRL_ENABLE ) == 0U )
    {
        MPU_CTRL |= MPU_CTRL_ENABLE | MPU_CTRL_PRIVDEFENA;
    }
    return true;
}

/**
 * @brief Make the lowest part of a stack read-only
 *
 * An overflow is a write: the push of a frame, the store to a local variable. Reading the guard harms nobody, and the
 * kernel does it (the high water mark of a stack is found by scanning it from its lowest address).
 *
 * The guard is a region of DMOSI_STACK_GUARD_SIZE bytes aligned to its size, which is the unit the MPU protects
 * in: the first such block that lies in the stack, above the pattern of the kernel. A stack too small to keep
 * a few guards' worth of room above it (the idle task's, say) runs unguarded: the guard would take most of it.
 *
 * Runs in the context switch of the RTOS: a handful of register writes, no stack to speak of.
 *
 * @param stack_base Lowest address of the stack
 * @param stack_size Size of the stack in bytes
 */
void dmosi_stack_guard_select( const void* stack_base, size_t stack_size )
{
    if( !enable_protection() )
    {
        return;
    }

    /* Not over the pattern the kernel keeps at the end of the stack and reads in every context switch, with the guard of
     * the thread it switches away from still in place */
    const uintptr_t start = ( (uintptr_t)stack_base + STACK_CANARY_SIZE + DMOSI_STACK_GUARD_SIZE - 1U ) & ~( (uintptr_t)DMOSI_STACK_GUARD_SIZE - 1U );
    const uintptr_t end = start + DMOSI_STACK_GUARD_SIZE;

    MPU_RNR = STACK_GUARD_MPU_REGION;
    MPU_RASR = 0U;
    if( stack_base != NULL && stack_size >= STACK_GUARD_MIN_STACK_SIZE && end + STACK_GUARD_MIN_ROOM <= (uintptr_t)stack_base + stack_size )
    {
        MPU_RBAR = (uint32_t)start;
        MPU_RASR = MPU_RASR_ENABLE | MPU_RASR_XN | MPU_RASR_AP_PRIV_RO | MPU_RASR_WRITE_BACK | ( ( 31U - (uint32_t)__builtin_clz( DMOSI_STACK_GUARD_SIZE ) - 1U ) << 1 );
        g_guard_start = start;
        g_guard_end = end;
    }
    else
    {
        g_guard_start = 0;
        g_guard_end = 0;
    }
    __asm volatile ( "dsb" ::: "memory" );
    __asm volatile ( "isb" ::: "memory" );
}

/**
 * @brief Check whether a fault is an access to the guard of the stack
 *
 * @param fault Description of the fault, with the stack pointer and the address filled in
 * @return bool true if the stack pointer or the address accessed is in the guard
 */
static bool hit_stack_guard( const dmosi_fault_t* fault )
{
    if( g_guard_end == 0 )
    {
        return false;
    }

    /* The CPU may have been stopped by the guard while pushing the frame of the exception itself:
     * then the stack pointer is in the guard (or just below it, by one frame) and nothing is valid but it */
    const uintptr_t margin = 64U;
    const bool sp_in_guard = fault->sp + margin >= g_guard_start && fault->sp < g_guard_end;
    const bool address_in_guard = fault->has_address && fault->address >= g_guard_start && fault->address < g_guard_end;
    return sp_in_guard || address_in_guard;
}

/**
 * @brief Describe the fault the CPU has just taken
 *
 * @param fault Description to fill in
 * @param frame Frame the CPU stacked on exception entry
 * @param cfsr Configurable Fault Status Register at the time of the fault
 */
static void describe_fault( dmosi_fault_t* fault, const exception_frame_t* frame, uint32_t cfsr )
{
    /* When stacking the frame itself faulted, there is no frame to read the PC from */
    const bool frame_valid = ( cfsr & ( CFSR_MSTKERR | CFSR_STKERR ) ) == 0;

    fault->thread = NULL;
    fault->pc = frame_valid ? frame->pc : 0;
    fault->sp = (uintptr_t)frame;
    fault->has_address = ( cfsr & ( CFSR_MMARVALID | CFSR_BFARVALID ) ) != 0;
    fault->address = ( cfsr & CFSR_MMARVALID ) ? SCB_MMFAR : ( ( cfsr & CFSR_BFARVALID ) ? SCB_BFAR : 0 );

    if( cfsr & CFSR_DIVBYZERO )
    {
        fault->type = DMOSI_FAULT_ARITHMETIC;
    }
    else if( cfsr & CFSR_ILLEGAL_MASK )
    {
        fault->type = DMOSI_FAULT_ILLEGAL_INSTRUCTION;
    }
    else if( cfsr & ( CFSR_MEMFAULT_MASK | CFSR_BUSFAULT_MASK | CFSR_UNALIGNED ) )
    {
        fault->type = DMOSI_FAULT_MEMORY_ACCESS;
    }
    else
    {
        fault->type = DMOSI_FAULT_UNKNOWN;
    }

    if( hit_stack_guard( fault ) )
    {
        fault->type = DMOSI_FAULT_STACK_OVERFLOW;
    }
}

/**
 * @brief Check whether the exception interrupted a thread that can be taken off its code path
 *
 * It cannot when the exception did not interrupt a thread at all (it
 * interrupted another handler, which uses the main stack), or interrupted
 * it with interrupts masked: a critical section protects a state that is
 * then left half-updated, and nobody would ever unmask the interrupts.
 *
 * @param exc_return EXC_RETURN value of the exception
 * @return bool true if the interrupted context is a thread with interrupts enabled
 */
static bool interrupted_preemptible_thread( uint32_t exc_return )
{
    uint32_t primask;
    uint32_t basepri;

    __asm volatile ( "mrs %0, primask" : "=r" ( primask ) );
    __asm volatile ( "mrs %0, basepri" : "=r" ( basepri ) );

    return ( exc_return & EXC_RETURN_MODE_MASK ) == EXC_RETURN_THREAD_PSP && primask == 0 && basepri == 0;
}

/**
 * @brief Make the exception return to the entry the OS chose for the faulting thread
 *
 * Builds the frame the CPU unstacks on exception return at the top of the
 * thread's stack, so the thread continues in the entry with an empty stack,
 * and forgets the fault and the floating-point state of the abandoned code.
 *
 * @param recovery Where the thread continues, from dmosi_thread_fault()
 * @return uint32_t EXC_RETURN value to return from the exception with
 */
static uint32_t resume_thread( const dmosi_fault_recovery_t* recovery )
{
    exception_frame_t* frame = (exception_frame_t*)( (uintptr_t)recovery->stack_top & ~(uintptr_t)7U );
    frame--;

    frame->r0 = (uint32_t)(uintptr_t)recovery->arg;
    frame->r1 = 0;
    frame->r2 = 0;
    frame->r3 = 0;
    frame->r12 = 0;
    frame->lr = RETURN_ADDRESS_NONE;
    frame->pc = (uint32_t)(uintptr_t)recovery->entry & ~1UL;
    frame->xpsr = XPSR_THUMB;

    __asm volatile ( "msr psp, %0" : : "r" ( frame ) );

    /* The CPU would otherwise still save the FP registers of the abandoned code,
     * lazily, into its abandoned frame - which now is the stack of the entry */
    FPU_FPCCR &= ~FPCCR_LSPACT;

    /* The status bits are sticky (write 1 to clear): the next fault must not inherit them */
    SCB_CFSR = SCB_CFSR;
    SCB_HFSR = HFSR_FORCED;

    return EXC_RETURN_TO_THREAD;
}

/**
 * @brief Halt the system on a fault that cannot be contained
 *
 * @param fault Description of the fault
 * @param frame Frame the CPU stacked on exception entry
 * @param cfsr Configurable Fault Status Register at the time of the fault
 */
static void halt_system( const dmosi_fault_t* fault, const exception_frame_t* frame, uint32_t cfsr )
{
    /* System state is suspect, and the normal Dmod_Printf path (Dmod_LockStdio ->
     * dmosi_process_current() -> ...) can fault a second time on it: raw kernel writes only */
    Dmod_SetForceKernelWrite( true );
    DMOD_LOG_ERROR( "Fatal fault: pc=0x%08lX lr=0x%08lX sp=0x%08lX cfsr=0x%08lX hfsr=0x%08lX address=0x%08lX\n",
                    (unsigned long)fault->pc, (unsigned long)( fault->pc ? frame->lr : 0 ), (unsigned long)fault->sp,
                    (unsigned long)cfsr, (unsigned long)SCB_HFSR, (unsigned long)fault->address );
    DMOD_ASSERT_MSG( false, "A fault that cannot be contained to a process occurred. System halted." );
    for( ;; )
    {
    }
}

/**
 * @brief C part of the fault exception handler
 *
 * @param frame Frame the CPU stacked on exception entry (on the stack that was in use)
 * @param exc_return EXC_RETURN value of the exception
 * @return uint32_t EXC_RETURN value to return from the exception with
 */
uint32_t dmboot_fault_dispatch( exception_frame_t* frame, uint32_t exc_return )
{
    const uint32_t cfsr = SCB_CFSR;
    dmosi_fault_t fault;
    dmosi_fault_recovery_t recovery;

    describe_fault( &fault, frame, cfsr );

    if( interrupted_preemptible_thread( exc_return ) && dmosi_thread_fault( &fault, &recovery ) )
    {
        return resume_thread( &recovery );
    }

    halt_system( &fault, frame, cfsr );
    return exc_return;
}

/**
 * @brief Handler of all the fault exceptions of the CPU
 *
 * Hands the stacked frame (on the main or the process stack, whichever was
 * in use) and EXC_RETURN to dmboot_fault_dispatch(), and returns from the
 * exception the way it says.
 */
__attribute__(( naked )) void dmboot_fault_handler( void )
{
    __asm volatile (
        "tst    lr, #4                  \n"
        "ite    eq                      \n"
        "mrseq  r0, msp                 \n"
        "mrsne  r0, psp                 \n"
        "mov    r1, lr                  \n"
        "bl     dmboot_fault_dispatch   \n"
        "bx     r0                      \n"
    );
}

void HardFault_Handler( void )  __attribute__(( alias( "dmboot_fault_handler" ) ));
void MemManage_Handler( void )  __attribute__(( alias( "dmboot_fault_handler" ) ));
void BusFault_Handler( void )   __attribute__(( alias( "dmboot_fault_handler" ) ));
void UsageFault_Handler( void ) __attribute__(( alias( "dmboot_fault_handler" ) ));
