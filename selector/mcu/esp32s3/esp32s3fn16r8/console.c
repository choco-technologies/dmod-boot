/**
 * @file console.c
 * @brief The log of the selector on the USB-Serial/JTAG of the ESP32-S3 (the port the board is connected by: /dev/ttyACM0)
 *
 * There is no debug probe that reads the ring buffer of dmlog from the RAM here, so the text also goes out of the chip as it is
 * logged. The endpoint has a 64 byte FIFO that the host empties when a program has the port open: when it does not, the
 * text is dropped (a wait of a few ms, once; the next call checks only whether the FIFO has room again).
 */
#include <stdint.h>
#include "dmsel_platform.h"

#define REG(a)                          (*(volatile uint32_t*)(a))
#define USB_SERIAL_JTAG_BASE            0x60038000u
#define USB_EP1                         REG( USB_SERIAL_JTAG_BASE + 0x0 )   // a byte to send (the FIFO)
#define USB_EP1_CONF                    REG( USB_SERIAL_JTAG_BASE + 0x4 )
#define EP1_CONF_WR_DONE                (1u << 0)                           // the bytes written are ready to be taken by the host
#define EP1_CONF_IN_EP_DATA_FREE        (1u << 1)                           // the FIFO has room

#define WAIT_STEP_US                    10
#define WAIT_STEPS                      2000                                // 20 ms

extern void ets_delay_us( uint32_t us );

static int g_host_absent;

static int wait_for_room( void )
{
    unsigned i;

    for( i = 0; i < WAIT_STEPS; i++ )
    {
        if( USB_EP1_CONF & EP1_CONF_IN_EP_DATA_FREE )
        {
            return 1;
        }
        ets_delay_us( WAIT_STEP_US );
    }
    return 0;
}

static int put_byte( char c )
{
    if( !(USB_EP1_CONF & EP1_CONF_IN_EP_DATA_FREE) )
    {
        USB_EP1_CONF = EP1_CONF_WR_DONE;
        if( !wait_for_room() )
        {
            return 0;
        }
    }
    USB_EP1 = (uint8_t)c;
    return 1;
}

void dmsel_mcu_console( const char* text )
{
    if( g_host_absent )
    {
        if( !(USB_EP1_CONF & EP1_CONF_IN_EP_DATA_FREE) )
        {
            return;
        }
        g_host_absent = 0;
    }
    for( ; *text != 0; text++ )
    {
        if( (*text == '\n' && !put_byte( '\r' )) || !put_byte( *text ) )
        {
            g_host_absent = 1;
            return;
        }
    }
    USB_EP1_CONF = EP1_CONF_WR_DONE;
}
