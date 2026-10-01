//
// STM32F7_SDMMC - model of the STM32F7 SDMMC host (RM0385, chapter 35) for
// dmod-boot's emulation tests.
//
// Renode's own STM32 SDMMC model (1.15.3) targets the STM32 HAL/Zephyr
// drivers and differs from the hardware where dmsdio relies on it: CMD8 gets
// no R7 echo, CMDSENT is never set, DATAEND only comes once the CPU has
// drained the FIFO and RXDAVL does not exist. This model follows the
// reference manual for what dmsdio uses:
//
// - commands complete at once: CMDREND (CMDSENT without a response), or
//   CTIMEOUT when no card answers; CMD8 returns the R7 echo of its argument
// - a read moves DLEN bytes from the card into the FIFO as soon as both the
//   read command was sent and the DPSM is enabled (in either order), sets
//   DATAEND/DBCKEND, and - with DMAEN - requests the DMA until the FIFO is
//   empty
// - a write takes DLEN bytes from the FIFO, whenever they were written
//   (Renode's STM32 DMA fills it as soon as the stream is enabled, i.e.
//   before the write command), once the command was sent and the DPSM is
//   enabled
// - RXDAVL/TXDAVL, the FIFO empty/full flags, FIFOCNT and DCOUNT follow the
//   FIFO contents; the interrupt line is STA & MASK
//
// It also covers for Renode's SD card model, which publishes RCA 0 (reserved
// by the specification) and an all-zero SD Status (whose DAT_BUS_WIDTH must
// confirm the width ACMD6 selected).
//
// Not modelled: CRC errors, data timeouts, SDIO, hardware flow control.
//
// Loaded at run time by renode.resc (include @...cs), it replaces the
// platform's sysbus.sdmmc.
//
using System.Collections.Generic;
using Antmicro.Renode.Core;
using Antmicro.Renode.Core.Structure;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals.Bus;

namespace Antmicro.Renode.Peripherals.SD
{
    public class STM32F7_SDMMC : NullRegistrationPointPeripheralContainer<SDCard>, IDoubleWordPeripheral, IKnownSize
    {
        public STM32F7_SDMMC(IMachine machine) : base(machine)
        {
            IRQ = new GPIO();
            DMAReceive = new GPIO();
            Reset();
        }

        public override void Reset()
        {
            power = 0;
            clockControl = 0;
            argument = 0;
            command = 0;
            responseCommand = 0;
            response = new uint[4];
            dataTimer = 0;
            dataLength = 0;
            dataControl = 0;
            dataCount = 0;
            flags = 0;
            mask = 0;
            rxFifo.Clear();
            txFifo.Clear();
            pendingRead = false;
            pendingWrite = false;
            nextIsAppCommand = false;
            wideBus = false;
            lastReadCommand = 0;
            UpdateInterrupts();
        }

        public uint ReadDoubleWord(long offset)
        {
            if(offset >= (long)Registers.Fifo && offset < (long)Registers.Fifo + FifoWindowSize)
            {
                return ReadFifo();
            }
            switch((Registers)offset)
            {
            case Registers.Power:
                return power;
            case Registers.ClockControl:
                return clockControl;
            case Registers.Argument:
                return argument;
            case Registers.Command:
                return command;
            case Registers.ResponseCommand:
                return responseCommand;
            case Registers.Response1:
            case Registers.Response2:
            case Registers.Response3:
            case Registers.Response4:
                return response[(offset - (long)Registers.Response1) / 4];
            case Registers.DataTimer:
                return dataTimer;
            case Registers.DataLength:
                return dataLength;
            case Registers.DataControl:
                return dataControl;
            case Registers.DataCount:
                return dataCount;
            case Registers.Status:
                return Status;
            case Registers.InterruptClear:
                return 0;
            case Registers.Mask:
                return mask;
            case Registers.FifoCount:
                return (uint)((rxFifo.Count + txFifo.Count) / 4);
            default:
                this.Log(LogLevel.Warning, "Unhandled read from offset 0x{0:X}", offset);
                return 0;
            }
        }

        public void WriteDoubleWord(long offset, uint value)
        {
            if(offset >= (long)Registers.Fifo && offset < (long)Registers.Fifo + FifoWindowSize)
            {
                WriteFifo(value);
                return;
            }
            switch((Registers)offset)
            {
            case Registers.Power:
                power = value & 0x3;
                break;
            case Registers.ClockControl:
                clockControl = value & 0x7FFF;
                break;
            case Registers.Argument:
                argument = value;
                break;
            case Registers.Command:
                command = value & 0xFFF;
                if((value & CommandPathEnable) != 0)
                {
                    SendCommand();
                }
                break;
            case Registers.DataTimer:
                dataTimer = value;
                break;
            case Registers.DataLength:
                dataLength = value & 0x1FFFFFF;
                break;
            case Registers.DataControl:
                WriteDataControl(value & 0xFFF);
                break;
            case Registers.InterruptClear:
                flags &= ~(value & StaticFlags);
                UpdateInterrupts();
                break;
            case Registers.Mask:
                mask = value;
                UpdateInterrupts();
                break;
            default:
                this.Log(LogLevel.Warning, "Unhandled write to offset 0x{0:X}, value 0x{1:X}", offset, value);
                break;
            }
        }

        public long Size { get { return 0x400; } }

        public GPIO IRQ { get; private set; }

        // DMA request line (DMA2 stream 3/6 channel 4 on the STM32F7)
        public GPIO DMAReceive { get; private set; }

        private uint Status
        {
            get
            {
                var status = flags;
                var rxWords = rxFifo.Count / 4;
                var txWords = txFifo.Count / 4;
                status |= (txWords <= FifoWords / 2) ? StatusBits.TxFifoHalfEmpty : 0;
                status |= (rxWords >= FifoWords / 4) ? StatusBits.RxFifoHalfFull : 0;
                status |= (txWords >= FifoWords) ? StatusBits.TxFifoFull : 0;
                status |= (rxWords >= FifoWords) ? StatusBits.RxFifoFull : 0;
                status |= (txWords == 0) ? StatusBits.TxFifoEmpty : 0;
                status |= (rxWords == 0) ? StatusBits.RxFifoEmpty : 0;
                status |= (txWords > 0) ? StatusBits.TxDataAvailable : 0;
                status |= (rxWords > 0) ? StatusBits.RxDataAvailable : 0;
                return status;
            }
        }

        private void SendCommand()
        {
            var index = command & 0x3F;
            var waitResponse = (command >> 6) & 0x3;
            var expectsResponse = (waitResponse == ShortResponse || waitResponse == LongResponse);
            var isAppCommand = nextIsAppCommand;
            nextIsAppCommand = false;

            var card = RegisteredPeripheral;
            if(card == null)
            {
                flags |= expectsResponse ? StatusBits.CommandTimeout : StatusBits.CommandSent;
                UpdateInterrupts();
                return;
            }

            if(!isAppCommand && index == SendRelativeAddress && card.CardAddress == 0)
            {
                // Renode 1.15's SD card publishes RCA 0, which the specification
                // reserves (it deselects all cards) - give it a valid one
                card.CardAddress = DefaultRelativeCardAddress;
            }
            var result = card.HandleCommand(index, argument);
            this.Log(LogLevel.Debug, "{0}CMD{1} arg 0x{2:X8}", isAppCommand ? "A" : "", index, argument);

            if(!isAppCommand && index == SendInterfaceCondition)
            {
                // R7: voltage accepted and check pattern echo of the argument
                SetShortResponse(index, argument & 0xFFF);
            }
            else if(waitResponse == LongResponse)
            {
                response[3] = result.AsUInt32(0) & ~1u;
                response[2] = result.AsUInt32(32);
                response[1] = result.AsUInt32(64);
                response[0] = result.AsUInt32(96);
                responseCommand = 0x3F;
            }
            else if(waitResponse == ShortResponse)
            {
                SetShortResponse(index, result.AsUInt32(0));
            }
            flags |= expectsResponse ? StatusBits.CommandResponseReceived : StatusBits.CommandSent;
            this.Log(LogLevel.Debug, "  response 0x{0:X8} 0x{1:X8} 0x{2:X8} 0x{3:X8} ({4} bits from the card)",
                     response[0], response[1], response[2], response[3], result.Length);

            if(isAppCommand && index == SetBusWidth)
            {
                wideBus = (argument & 0x3) == AcmdBusWidth4Bit;
            }
            else if(!isAppCommand && index == GoIdleState)
            {
                wideBus = false;
            }

            if(index == AppCommand)
            {
                nextIsAppCommand = true;
            }
            else if(index == GoIdleState)
            {
                StopData();
            }
            else if(IsReadCommand(index, isAppCommand))
            {
                lastReadCommand = isAppCommand ? index : index | NotAppCommand;
                pendingRead = true;
                pendingWrite = false;
            }
            else if(IsWriteCommand(index, isAppCommand))
            {
                pendingWrite = true;
                pendingRead = false;
            }
            UpdateInterrupts();
            TryStartData();
        }

        private void SetShortResponse(uint index, uint value)
        {
            response[0] = value;
            response[1] = 0;
            response[2] = 0;
            response[3] = 0;
            responseCommand = index;
        }

        private static bool IsReadCommand(uint index, bool isAppCommand)
        {
            if(isAppCommand)
            {
                return index == SendSdStatus
                    || index == SendScr;
            }
            return index == SwitchFunction
                || index == ReadSingleBlock
                || index == ReadMultipleBlocks;
        }

        private static bool IsWriteCommand(uint index, bool isAppCommand)
        {
            return !isAppCommand
                && (index == WriteSingleBlock
                    || index == WriteMultipleBlocks);
        }

        private void WriteDataControl(uint value)
        {
            dataControl = value;
            if((value & DataTransferEnable) == 0)
            {
                StopData();
                return;
            }
            dataCount = dataLength;
            TryStartData();
        }

        // Runs the data phase once both the data command was sent and the DPSM
        // enabled: dmsdio enables the DPSM before a read command and after a
        // write command, the ST HAL after both
        private void TryStartData()
        {
            if((dataControl & DataTransferEnable) == 0)
            {
                return;
            }
            var fromCard = (dataControl & DataDirectionFromCard) != 0;
            if(fromCard && pendingRead)
            {
                pendingRead = false;
                ReceiveFromCard();
            }
            else if(!fromCard && pendingWrite)
            {
                TransmitToCard();
            }
        }

        private void ReceiveFromCard()
        {
            var card = RegisteredPeripheral;
            if(card == null)
            {
                flags |= StatusBits.DataTimeout;
                UpdateInterrupts();
                return;
            }
            var data = card.ReadData(dataLength);
            if(lastReadCommand == SendSdStatus && data.Length > 0)
            {
                // Renode's SD card returns an all-zero SD Status; DAT_BUS_WIDTH
                // (bits 511:510) has to report the width ACMD6 selected
                data[0] = (byte)((data[0] & 0x3F) | (wideBus ? SsrBusWidth4Bit : 0));
            }
            foreach(var b in data)
            {
                rxFifo.Enqueue(b);
            }
            dataCount = 0;
            flags |= StatusBits.DataEnd | StatusBits.DataBlockEnd;
            UpdateInterrupts();
            if((dataControl & DmaEnable) != 0)
            {
                RequestDma();
            }
        }

        private void TransmitToCard()
        {
            if(txFifo.Count < dataLength)
            {
                // Not all data is in the FIFO yet - request the DMA, then wait
                // for the rest of the FIFO writes
                if((dataControl & DmaEnable) != 0)
                {
                    RequestDma();
                }
                if(txFifo.Count < dataLength)
                {
                    return;
                }
            }
            var card = RegisteredPeripheral;
            if(card == null)
            {
                flags |= StatusBits.DataTimeout;
                UpdateInterrupts();
                return;
            }
            var data = new byte[dataLength];
            for(var i = 0; i < data.Length; i++)
            {
                data[i] = txFifo.Dequeue();
            }
            card.WriteData(data);
            pendingWrite = false;
            dataCount = 0;
            flags |= StatusBits.DataEnd | StatusBits.DataBlockEnd;
            UpdateInterrupts();
        }

        // Each request moves as much as the DMA model takes per request: keep
        // requesting while the FIFO drains (reads) or fills (writes)
        private void RequestDma()
        {
            for(var i = 0; i < MaxDmaRequests; i++)
            {
                var before = rxFifo.Count + txFifo.Count;
                DMAReceive.Blink();
                var after = rxFifo.Count + txFifo.Count;
                if(after == before || rxFifo.Count == 0 && (dataControl & DataDirectionFromCard) != 0)
                {
                    break;
                }
            }
        }

        private void StopData()
        {
            pendingRead = false;
            pendingWrite = false;
            txFifo.Clear();
        }

        private uint ReadFifo()
        {
            if(rxFifo.Count == 0)
            {
                this.Log(LogLevel.Warning, "Read from an empty receive FIFO");
                return 0;
            }
            uint value = 0;
            for(var i = 0; i < 4 && rxFifo.Count > 0; i++)
            {
                value |= (uint)rxFifo.Dequeue() << (8 * i);
            }
            UpdateInterrupts();
            return value;
        }

        private void WriteFifo(uint value)
        {
            for(var i = 0; i < 4; i++)
            {
                txFifo.Enqueue((byte)(value >> (8 * i)));
            }
            if(pendingWrite && (dataControl & DataTransferEnable) != 0 && (dataControl & DataDirectionFromCard) == 0
               && txFifo.Count >= dataLength)
            {
                TransmitToCard();
            }
            else
            {
                UpdateInterrupts();
            }
        }

        private void UpdateInterrupts()
        {
            IRQ.Set((Status & mask) != 0);
        }

        private uint power;
        private uint clockControl;
        private uint argument;
        private uint command;
        private uint responseCommand;
        private uint[] response;
        private uint dataTimer;
        private uint dataLength;
        private uint dataControl;
        private uint dataCount;
        private uint flags;
        private uint mask;
        private bool pendingRead;
        private bool pendingWrite;
        private bool nextIsAppCommand;
        private bool wideBus;
        private uint lastReadCommand;
        private readonly Queue<byte> rxFifo = new Queue<byte>();
        private readonly Queue<byte> txFifo = new Queue<byte>();

        // SD command indices (SD Physical Layer Simplified Specification) - the
        // SDCard model's own enums are not public in every Renode version
        private const uint GoIdleState = 0;
        private const uint SendRelativeAddress = 3;
        private const uint SwitchFunction = 6;
        private const uint SendInterfaceCondition = 8;
        private const uint ReadSingleBlock = 17;
        private const uint ReadMultipleBlocks = 18;
        private const uint WriteSingleBlock = 24;
        private const uint WriteMultipleBlocks = 25;
        private const uint AppCommand = 55;
        private const uint SetBusWidth = 6;             // ACMD6
        private const uint SendSdStatus = 13;           // ACMD13
        private const uint SendScr = 51;                // ACMD51

        private const ushort DefaultRelativeCardAddress = 1;
        private const uint AcmdBusWidth4Bit = 2;
        private const byte SsrBusWidth4Bit = 0x80;
        // Keeps CMDx distinct from ACMDx in lastReadCommand
        private const uint NotAppCommand = 0x100;

        private const uint CommandPathEnable = 1u << 10;
        private const uint ShortResponse = 1;
        private const uint LongResponse = 3;
        private const uint DataTransferEnable = 1u << 0;
        private const uint DataDirectionFromCard = 1u << 1;
        private const uint DmaEnable = 1u << 3;
        // CCRCFAIL..DBCKEND (bits 0-10) and SDIOIT, cleared through ICR
        private const uint StaticFlags = 0x7FFu | (1u << 22);
        private const int FifoWords = 32;
        private const long FifoWindowSize = 0x80;
        private const int MaxDmaRequests = 1 << 20;

        private static class StatusBits
        {
            public const uint CommandTimeout = 1u << 2;
            public const uint DataTimeout = 1u << 3;
            public const uint CommandResponseReceived = 1u << 6;
            public const uint CommandSent = 1u << 7;
            public const uint DataEnd = 1u << 8;
            public const uint DataBlockEnd = 1u << 10;
            public const uint TxFifoHalfEmpty = 1u << 14;
            public const uint RxFifoHalfFull = 1u << 15;
            public const uint TxFifoFull = 1u << 16;
            public const uint RxFifoFull = 1u << 17;
            public const uint TxFifoEmpty = 1u << 18;
            public const uint RxFifoEmpty = 1u << 19;
            public const uint TxDataAvailable = 1u << 20;
            public const uint RxDataAvailable = 1u << 21;
        }

        private enum Registers : long
        {
            Power = 0x00,
            ClockControl = 0x04,
            Argument = 0x08,
            Command = 0x0C,
            ResponseCommand = 0x10,
            Response1 = 0x14,
            Response2 = 0x18,
            Response3 = 0x1C,
            Response4 = 0x20,
            DataTimer = 0x24,
            DataLength = 0x28,
            DataControl = 0x2C,
            DataCount = 0x30,
            Status = 0x34,
            InterruptClear = 0x38,
            Mask = 0x3C,
            FifoCount = 0x48,
            Fifo = 0x80,
        }
    }
}
