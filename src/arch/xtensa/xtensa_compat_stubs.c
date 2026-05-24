#include <stdarg.h>
#include <stdint.h>

#define DM_WEAK __attribute__((weak))

DM_WEAK volatile unsigned port_xSchedulerRunning = 0;

DM_WEAK unsigned _xtos_set_intlevel(int intlevel)
{
    (void)intlevel;
    return 0;
}

DM_WEAK unsigned xthal_get_ccount(void)
{
    unsigned count;
    __asm__ volatile("rsr.ccount %0" : "=a"(count));
    return count;
}

DM_WEAK void xthal_window_spill_nw(void)
{
}

DM_WEAK void xthal_save_extra_nw(void)
{
}

DM_WEAK void xthal_restore_extra_nw(void)
{
}

DM_WEAK void vPortSetupTimer(void)
{
}

DM_WEAK void esp_crosscore_int_send_yield(int core_id)
{
    (void)core_id;
}

DM_WEAK int esp_rom_printf(const char *format, ...)
{
    (void)format;
    return 0;
}

DM_WEAK void esp_cpu_set_watchpoint(int watchpoint_no,
                                    const void *watchpoint_addr,
                                    int size,
                                    int flags)
{
    (void)watchpoint_no;
    (void)watchpoint_addr;
    (void)size;
    (void)flags;
}

DM_WEAK void esp_startup_start_app_common(void)
{
}

DM_WEAK uint32_t esp_log_system_timestamp(void)
{
    return 0;
}

DM_WEAK void esp_log_write(int level, const char *tag, const char *format, ...)
{
    (void)level;
    (void)tag;
    (void)format;
}

DM_WEAK void xt_unhandled_interrupt(void *arg)
{
    (void)arg;
    for (;;) {
    }
}

DM_WEAK void xt_unhandled_exception(void *arg)
{
    (void)arg;
    for (;;) {
    }
}

DM_WEAK void panicHandler(void *frame)
{
    (void)frame;
    for (;;) {
    }
}
