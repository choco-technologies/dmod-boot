// STM32F746 QUADSPI + the board's 16 MiB Micron N25Q128A (JEDEC 20 BA 18).
// Register layout: ST RM0385, Quad-SPI interface. Command set: Micron
// n25q_128mb_3v_65nm, extended SPI protocol. Loaded with Renode's `include`.
//
// Functional model: indirect byte/halfword/word transfers, IRQ, DMA requests,
// status polling and read-only memory mapping. Flash operations finish instantly;
// clock/pin timing, wear, protection, suspend, dual flash and DDR are not modelled.
// Unsupported commands set TEF rather than silently succeeding. A new image is
// erased (FF), never formatted. Reset preserves the array; imageFile, if supplied,
// is updated after each program/erase and must not be shared by running machines.
using System;
using System.IO;
using Antmicro.Renode.Core;
using Antmicro.Renode.Exceptions;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals.Bus;

namespace Antmicro.Renode.Peripherals.SPI
{
    public class STM32F7_QUADSPI : IDoubleWordPeripheral, IWordPeripheral, IBytePeripheral, IKnownSize
    {
        public STM32F7_QUADSPI(IMachine machine, string imageFile = null)
        {
            IRQ = new GPIO();
            DMARequest = new GPIO();
            flash = new byte[Capacity];
            this.imageFile = imageFile;
            if(!String.IsNullOrEmpty(imageFile) && File.Exists(imageFile))
            {
                if(new FileInfo(imageFile).Length != Capacity)
                    throw new ConstructionException("N25Q128A image must be exactly 16777216 bytes");
                flash = File.ReadAllBytes(imageFile);
            }
            else
            {
                for(var i = 0; i < Capacity; i++) flash[i] = 0xFF;
                Persist(0, Capacity);
            }
            Reset();
        }

        public void Reset()
        {
            Array.Clear(registers, 0, registers.Length);
            active = false;
            remaining = 0;
            flags = 0;
            ResetChip();
            IRQ.Unset();
            DMARequest.Unset();
        }

        public uint ReadDoubleWord(long offset)
        {
            if(offset == DR) return ReadData(4);
            if(offset == SR)
            {
                if(active && Mode == 2) Poll();
                return Status;
            }
            if(offset == FCR) return 0;
            return ValidRegister(offset) ? registers[offset / 4] : 0;
        }

        public void WriteDoubleWord(long offset, uint value)
        {
            if(offset == DR) { WriteData(value, 4); return; }
            if(offset == SR || !ValidRegister(offset)) return;
            if(offset == FCR)
            {
                flags &= ~(value & 0x1B);
                UpdateIRQ();
                return;
            }
            registers[offset / 4] = value;
            if(offset == CR)
            {
                if((value & 2) != 0 || (value & 1) == 0)
                {
                    active = false;
                    remaining = 0;
                    if((value & 2) != 0) flags |= TCF;
                    registers[CR / 4] &= ~2u;
                }
            }
            else if(offset == CCR)
            {
                active = false;
                remaining = 0;
                // An address phase is triggered by AR, except memory-mapped mode.
                if(Mode == 3 || ((value >> 10) & 3) == 0) StartTransfer();
            }
            else if(offset == AR && Mode != 3) StartTransfer();
            UpdateIRQ();
            RequestDMA();
        }

        public byte ReadByte(long offset)
        {
            return offset >= DR && offset < DR + 4 ? (byte)ReadData(1)
                : (byte)(ReadDoubleWord(offset & ~3L) >> (int)((offset & 3) * 8));
        }
        public ushort ReadWord(long offset)
        {
            return offset >= DR && offset < DR + 4 ? (ushort)ReadData(2)
                : (ushort)(ReadDoubleWord(offset & ~3L) >> (int)((offset & 3) * 8));
        }
        public void WriteByte(long offset, byte value)
        {
            if(offset >= DR && offset < DR + 4) WriteData(value, 1);
            else this.Log(LogLevel.Warning, "Byte write outside QUADSPI DR: 0x{0:X}", offset);
        }
        public void WriteWord(long offset, ushort value)
        {
            if(offset >= DR && offset < DR + 4) WriteData(value, 2);
            else this.Log(LogLevel.Warning, "Halfword write outside QUADSPI DR: 0x{0:X}", offset);
        }

        public byte ReadMapped(long offset)
        {
            return (registers[CR / 4] & 1) != 0 && active && Mode == 3 && IsArrayRead(Opcode)
                ? flash[(int)(offset & (Capacity - 1))] : (byte)0xFF;
        }

        public long Size { get { return 0x400; } }
        public GPIO IRQ { get; private set; }
        public GPIO DMARequest { get; private set; }
        public const int Capacity = 16 * 1024 * 1024;

        private void StartTransfer()
        {
            if((registers[CR / 4] & 1) == 0) return;
            if((registers[CR / 4] & ((1u << 6) | (1u << 7))) != 0 ||
               (registers[CCR / 4] & (1u << 31)) != 0)
            {
                Fail("dual flash, bank 2 and DDR are unsupported");
                return;
            }
            position = 0;
            address = registers[AR / 4] & 0xFFFFFF;
            var addressBytes = (int)((registers[CCR / 4] >> 12) & 3) + 1;
            if(addressBytes < 3) address &= (1u << (8 * addressBytes)) - 1;
            active = true;
            var dataMode = (registers[CCR / 4] >> 24) & 3;
            if(Opcode != 0x99 && Opcode != 0x66) resetEnabled = false;
            if(Mode == 3)
            {
                if(!IsArrayRead(Opcode)) Fail("unsupported mapped command");
                return;
            }
            if(dataMode == 0)
            {
                Command();
                if(active) Complete();
                return;
            }
            remaining = (ulong)registers[DLR / 4] + 1;
            if(Mode == 1 || Mode == 2)
            {
                if(!IsArrayRead(Opcode) && Opcode != 0x9F && Opcode != 0x9E && Opcode != 0x05 &&
                    Opcode != 0x70 && Opcode != 0x85 && Opcode != 0x65)
                    Fail("unsupported read command");
                else if(Mode == 2) Poll();
                else if(remaining <= 32) flags |= TCF;
            }
            else if(Opcode == 0x02 || Opcode == 0x32)
            {
                for(var i = 0; i < page.Length; i++) page[i] = 0xFF;
            }
            else if(Opcode != 0x81 && Opcode != 0x61)
                Fail("unsupported write command");
        }

        private void Command()
        {
            switch(Opcode)
            {
            case 0x06: writeEnabled = true; break;
            case 0x04: writeEnabled = false; break;
            case 0x66: resetEnabled = true; break;
            case 0x99: if(resetEnabled) ResetChip(); break;
            case 0x50: flagStatus = 0x80; break;
            case 0x20: Erase(4096); break;
            case 0xD8: Erase(65536); break;
            case 0xC7: Erase(Capacity); break;
            default: Fail("unsupported command"); break;
            }
        }

        private byte ReadFlash(uint index)
        {
            if(IsArrayRead(Opcode)) return flash[(address + index) & (Capacity - 1)];
            switch(Opcode)
            {
            case 0x9F: case 0x9E: return index < Jedec.Length ? Jedec[index] : (byte)0xFF;
            case 0x05: return writeEnabled ? (byte)2 : (byte)0;
            case 0x70: return flagStatus;
            case 0x85: return volatileConfig;
            case 0x65: return enhancedConfig;
            default: return 0xFF;
            }
        }

        private uint ReadData(int width)
        {
            if(!active || Mode != 1) return 0;
            uint value = 0;
            for(var i = 0; i < width && remaining > 0; i++)
            {
                value |= (uint)ReadFlash(position++) << (8 * i);
                remaining--;
            }
            if(remaining <= 32) flags |= TCF; // last serial bytes have reached the FIFO
            if(remaining == 0) Complete();
            UpdateIRQ();
            return value;
        }

        private void WriteData(uint value, int width)
        {
            if(!active || Mode != 0 || remaining == 0) return;
            for(var i = 0; i < width && remaining > 0; i++)
            {
                var data = (byte)(value >> (i * 8));
                page[(address + position) & 255] = data;
                lastData = data;
                position++;
                remaining--;
            }
            if(remaining == 0)
            {
                if(writeEnabled)
                {
                    if(Opcode == 0x02 || Opcode == 0x32)
                    {
                        var start = (int)(address & ~255u);
                        // NOR programming only clears bits; addresses wrap within a page.
                        for(var i = 0; i < page.Length; i++) flash[start + i] &= page[i];
                        Persist(start, page.Length);
                    }
                    else if(Opcode == 0x81) volatileConfig = lastData;
                    else if(Opcode == 0x61) enhancedConfig = lastData;
                    writeEnabled = false;
                }
                Complete();
            }
            UpdateIRQ();
        }

        private void Erase(int length)
        {
            if(!writeEnabled) return;
            var start = (int)address & ~(length - 1);
            for(var i = start; i < start + length; i++) flash[i] = 0xFF;
            Persist(start, length);
            writeEnabled = false;
        }

        private void Poll()
        {
            uint value = 0;
            for(uint i = 0; i < Math.Min(remaining, 4UL); i++) value |= (uint)ReadFlash(i) << (int)(i * 8);
            var mask = registers[PSMKR / 4];
            var equal = ~(value ^ registers[PSMAR / 4]) & mask;
            var matches = (registers[CR / 4] & (1u << 23)) != 0 ? equal != 0 : equal == mask;
            if(matches)
            {
                flags |= SMF;
                if((registers[CR / 4] & (1u << 22)) != 0) active = false;
            }
            UpdateIRQ();
        }

        private uint Status
        {
            get
            {
                uint level = active && Mode == 1 ? (uint)Math.Min(remaining, 32UL) : 0;
                var threshold = ((registers[CR / 4] >> 8) & 31) + 1;
                var ftf = active && ((Mode == 1 && (level >= threshold || (level > 0 && (flags & TCF) != 0))) || (Mode == 0 && remaining > 0));
                return flags | (active ? 0x20u : 0) | (level << 8) | (ftf ? FTF : 0);
            }
        }
        private void UpdateIRQ()
        {
            IRQ.Set((Status & ((registers[CR / 4] >> 16) & 0x1F)) != 0);
        }
        private void RequestDMA()
        {
            // GPIO callbacks consume DR synchronously in Renode. Stop when a stream
            // is not ready; never spin forever or recursively request from DR reads.
            if(requestingDMA || (registers[CR / 4] & 4) == 0) return;
            requestingDMA = true;
            try
            {
                while(active && (Mode == 0 || Mode == 1) && (Status & FTF) != 0)
                {
                    var before = remaining;
                    DMARequest.Blink();
                    if(remaining == before) break;
                }
            }
            finally { requestingDMA = false; }
        }
        private void Complete() { active = false; flags |= TCF; }
        private void Fail(string reason)
        {
            active = false;
            remaining = 0;
            flags |= TEF;
            this.Log(LogLevel.Warning, "QUADSPI opcode 0x{0:X2}: {1}", Opcode, reason);
        }
        private void ResetChip()
        {
            writeEnabled = false;
            resetEnabled = false;
            flagStatus = 0x80;
            volatileConfig = 0xFB;
            enhancedConfig = 0xFF;
        }
        private void Persist(int start, int length)
        {
            if(String.IsNullOrEmpty(imageFile)) return;
            using(var file = new FileStream(imageFile, FileMode.OpenOrCreate, FileAccess.Write, FileShare.Read))
            {
                file.Position = start;
                file.Write(flash, start, length);
            }
        }
        private static bool IsArrayRead(byte command)
        {
            return command == 0x03 || command == 0x0B || command == 0x6B || command == 0xEB;
        }
        private static bool ValidRegister(long offset) { return offset >= 0 && offset <= 0x30 && (offset & 3) == 0; }
        private byte Opcode { get { return (byte)registers[CCR / 4]; } }
        private uint Mode { get { return (registers[CCR / 4] >> 26) & 3; } }
        private const long CR = 0x00, SR = 0x08, FCR = 0x0C, DLR = 0x10, CCR = 0x14, AR = 0x18,
            DR = 0x20, PSMKR = 0x24, PSMAR = 0x28;
        private const uint TEF = 1, TCF = 2, FTF = 4, SMF = 8;
        private static readonly byte[] Jedec = { 0x20, 0xBA, 0x18 };
        private readonly uint[] registers = new uint[13];
        private readonly byte[] flash;
        private readonly byte[] page = new byte[256];
        private readonly string imageFile;
        private uint flags, address, position;
        private ulong remaining;
        private bool active, requestingDMA, writeEnabled, resetEnabled;
        private byte lastData, flagStatus, volatileConfig, enhancedConfig;
    }

    // Separate read-only AHB window: writes must go through QUADSPI commands.
    public class STM32F7_QSPIWindow : IBytePeripheral, IWordPeripheral, IDoubleWordPeripheral, IKnownSize
    {
        public STM32F7_QSPIWindow(STM32F7_QUADSPI controller) { this.controller = controller; }
        public void Reset() { }
        public byte ReadByte(long offset) { return controller.ReadMapped(offset); }
        public ushort ReadWord(long offset) { return (ushort)(ReadByte(offset) | (ReadByte(offset + 1) << 8)); }
        public uint ReadDoubleWord(long offset) { return (uint)ReadWord(offset) | ((uint)ReadWord(offset + 2) << 16); }
        public void WriteByte(long offset, byte value) { }
        public void WriteWord(long offset, ushort value) { }
        public void WriteDoubleWord(long offset, uint value) { }
        public long Size { get { return STM32F7_QUADSPI.Capacity; } }
        private readonly STM32F7_QUADSPI controller;
    }
}
