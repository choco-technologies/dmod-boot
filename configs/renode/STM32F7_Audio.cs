//
// Renode models for audio playback on the STM32F746G-DISCO: a DMA controller
// with circular mode and half-transfer interrupts, the SAI and the WM8994
// codec on I2C3.
//
// STM32F7_AudioDMA replaces the platform's DMA2: Renode's STM32DMA moves
// memory-to-peripheral data at once and has neither CIRC nor HTIF, which the
// SAI stream (dmsai) depends on. Peripheral-to-memory requests behave as in
// Renode's model, so the SD host keeps working. A non-circular
// memory-to-peripheral or memory-to-memory stream is still copied at once.
//
// STM32F7_SAI paces block A (master TX) and block B (synchronous slave RX) at
// the frame rate derived from the SAI kernel clock (PLLSAI/PLLI2S, read from
// RCC) and MCKDIV. Each frame is serialized bit by bit from SAI_xFRCR/SLOTR/CR1
// (data size, slots, FS definition, polarity, offset) and handed to the codec
// with its LRCLK level per bit, so a format mismatch between SAI and codec is
// heard exactly as on hardware.
//
// WM8994 is an I2C register file (16-bit registers, auto-increment) that
// decodes the bit stream according to AIF1_CONTROL1 (format, word length,
// LRCLK/BCLK inversion) and writes the DAC1 samples it receives to OutputFile
// as raw stereo s16le (silence while DAC1 is muted).
//
// Not wired into renode.resc yet. To use it, add to the script before
// LoadELF (the codec node also needs dmsai/dmwm8994 in the firmware and the
// FT5336 touch config left out, since both own I2C3):
//
//   include @configs/renode/STM32F7_Audio.cs
//   sysbus Unregister sysbus.dma2
//   machine LoadPlatformDescriptionFromString "dma2: DMA.STM32F7_AudioDMA @ sysbus 0x40026400 { [0-7] -> nvic@[56-60,68-70] }"
//   machine LoadPlatformDescriptionFromString "wm8994: Sound.WM8994 @ i2c3 0x1A { outputFile: \"/tmp/codec.pcm\" }"
//   machine LoadPlatformDescriptionFromString "sai2: Sound.STM32F7_SAI @ sysbus 0x40015C00 { codec: wm8994; DmaRequestA -> dma2@4; DmaRequestB -> dma2@6 }"
//
// and convert the capture with e.g. "sox -t raw -r 48000 -e signed -b 16 -c 2 /tmp/codec.pcm out.wav".
//
using System;
using System.Collections.Generic;
using System.IO;
using Antmicro.Renode.Core;
using Antmicro.Renode.Logging;
using Antmicro.Renode.Peripherals.Bus;
using Antmicro.Renode.Peripherals.I2C;
using Antmicro.Renode.Time;
using Antmicro.Renode.Peripherals.Timers;

namespace Antmicro.Renode.Peripherals.DMA
{
    public class STM32F7_AudioDMA : IDoubleWordPeripheral, IKnownSize, IGPIOReceiver, INumberedGPIOOutput
    {
        public STM32F7_AudioDMA(IMachine machine)
        {
            sysbus = machine.GetSystemBus(this);
            var irqs = new Dictionary<int, IGPIO>();
            for(var i = 0; i < StreamCount; i++)
            {
                streams[i] = new Stream();
                irqs[i] = new GPIO();
            }
            Connections = irqs;
            Reset();
        }

        public void Reset()
        {
            foreach(var s in streams)
            {
                s.Reset();
            }
            Update();
        }

        public uint ReadDoubleWord(long offset)
        {
            if(offset == 0x0 || offset == 0x4)
            {
                var first = offset == 0x0 ? 0 : 4;
                uint value = 0;
                for(var i = 0; i < 4; i++)
                {
                    value |= (uint)streams[first + i].Flags << FlagShift[i];
                }
                return value;
            }
            if(!TryGetStream(offset, out var s, out var reg))
            {
                return 0;
            }
            switch(reg)
            {
            case 0x0: return s.CR;
            case 0x4: return s.NDTR;
            case 0x8: return s.PAR;
            case 0xC: return s.M0AR;
            case 0x10: return s.M1AR;
            case 0x14: return s.FCR | (s.Enabled ? 0u : 0x20u); /* FS: FIFO empty */
            }
            return 0;
        }

        public void WriteDoubleWord(long offset, uint value)
        {
            if(offset == 0x8 || offset == 0xC)
            {
                var first = offset == 0x8 ? 0 : 4;
                for(var i = 0; i < 4; i++)
                {
                    streams[first + i].Flags &= ~(int)((value >> FlagShift[i]) & 0x3D);
                }
                Update();
                return;
            }
            if(!TryGetStream(offset, out var s, out var reg))
            {
                return;
            }
            switch(reg)
            {
            case 0x0:
                var wasEnabled = s.Enabled;
                s.CR = value;
                if(!wasEnabled && s.Enabled)
                {
                    s.Start();
                    if(s.Direction == 2 || (s.Direction == 1 && !s.Circular))
                    {
                        while(s.Enabled && s.NDTR > 0)
                        {
                            TransferUnit(s);
                        }
                    }
                }
                break;
            case 0x4: if(!s.Enabled) s.NDTR = value & 0xFFFF; break;
            case 0x8: if(!s.Enabled) s.PAR = value; break;
            case 0xC: s.M0AR = value; break;
            case 0x10: s.M1AR = value; break;
            case 0x14: s.FCR = value & 0xBF; break;
            }
            Update();
        }

        public void OnGPIO(int number, bool value)
        {
            if(!value || number < 0 || number >= StreamCount)
            {
                return;
            }
            var s = streams[number];
            if(!s.Enabled || s.NDTR == 0)
            {
                return;
            }
            var bytes = s.PeripheralSize;
            if(s.Direction == 0 && (s.FCR & 0x4) != 0)
            {
                bytes = (int)((s.FCR & 0x3) + 1) * 4; /* FIFO threshold, like Renode's STM32DMA */
            }
            for(var done = 0; done < bytes && s.Enabled && s.NDTR > 0; done += s.PeripheralSize)
            {
                TransferUnit(s);
            }
            Update();
        }

        public long Size => 0x400;

        public IReadOnlyDictionary<int, IGPIO> Connections { get; }

        private void TransferUnit(Stream s)
        {
            var toPeripheral = s.Direction == 1;
            var size = s.PeripheralSize;
            ulong peripheral = s.PAR + (s.PeripheralIncrement ? s.PeripheralOffset : 0);
            ulong memory = s.M0AR + (s.MemoryIncrement ? s.MemoryOffset : 0);
            if(s.Direction == 2)
            {
                /* Memory to memory: PAR is the source. */
                Write(memory, Read(peripheral, size), size);
            }
            else if(toPeripheral)
            {
                Write(peripheral, Read(memory, size), size);
            }
            else
            {
                Write(memory, Read(peripheral, size), size);
            }
            s.PeripheralOffset += (ulong)size;
            s.MemoryOffset += (ulong)size;
            s.NDTR--;
            if(s.NDTR == s.InitialCount / 2)
            {
                s.Flags |= HalfTransferFlag;
            }
            if(s.NDTR == 0)
            {
                s.Flags |= TransferCompleteFlag;
                if(s.Circular)
                {
                    s.NDTR = s.InitialCount;
                    s.PeripheralOffset = 0;
                    s.MemoryOffset = 0;
                }
                else
                {
                    s.CR &= ~1u;
                }
            }
        }

        private uint Read(ulong address, int size)
        {
            switch(size)
            {
            case 1: return sysbus.ReadByte(address);
            case 2: return sysbus.ReadWord(address);
            default: return sysbus.ReadDoubleWord(address);
            }
        }

        private void Write(ulong address, uint value, int size)
        {
            switch(size)
            {
            case 1: sysbus.WriteByte(address, (byte)value); break;
            case 2: sysbus.WriteWord(address, (ushort)value); break;
            default: sysbus.WriteDoubleWord(address, value); break;
            }
        }

        private bool TryGetStream(long offset, out Stream stream, out long reg)
        {
            stream = null;
            reg = 0;
            if(offset < 0x10 || offset >= 0x10 + StreamCount * 0x18)
            {
                return false;
            }
            stream = streams[(offset - 0x10) / 0x18];
            reg = (offset - 0x10) % 0x18;
            return true;
        }

        private void Update()
        {
            for(var i = 0; i < StreamCount; i++)
            {
                var s = streams[i];
                var irq = ((s.Flags & TransferCompleteFlag) != 0 && (s.CR & 0x10) != 0)
                    || ((s.Flags & HalfTransferFlag) != 0 && (s.CR & 0x8) != 0);
                Connections[i].Set(irq);
            }
        }

        private readonly IBusController sysbus;
        private readonly Stream[] streams = new Stream[StreamCount];

        private const int StreamCount = 8;
        private const int HalfTransferFlag = 0x10;
        private const int TransferCompleteFlag = 0x20;
        private static readonly int[] FlagShift = { 0, 6, 16, 22 };

        private class Stream
        {
            public void Reset()
            {
                CR = 0;
                NDTR = 0;
                PAR = 0;
                M0AR = 0;
                M1AR = 0;
                FCR = 0x21;
                Flags = 0;
            }

            public void Start()
            {
                InitialCount = NDTR;
                PeripheralOffset = 0;
                MemoryOffset = 0;
            }

            public bool Enabled => (CR & 1) != 0;
            public int Direction => (int)((CR >> 6) & 3);
            public bool Circular => (CR & (1 << 8)) != 0;
            public bool PeripheralIncrement => (CR & (1 << 9)) != 0;
            public bool MemoryIncrement => (CR & (1 << 10)) != 0;
            public int PeripheralSize => 1 << (int)((CR >> 11) & 3);

            public uint CR;
            public uint NDTR;
            public uint PAR;
            public uint M0AR;
            public uint M1AR;
            public uint FCR;
            public int Flags;
            public uint InitialCount;
            public ulong PeripheralOffset;
            public ulong MemoryOffset;
        }
    }
}

namespace Antmicro.Renode.Peripherals.Sound
{
    public class STM32F7_SAI : IDoubleWordPeripheral, IKnownSize
    {
        public STM32F7_SAI(IMachine machine, WM8994 codec, ulong rccAddress = 0x40023800, bool secondInstance = true,
            uint hseFrequency = 25000000)
        {
            this.machine = machine;
            this.codec = codec;
            this.rccAddress = rccAddress;
            this.secondInstance = secondInstance;
            this.hseFrequency = hseFrequency;
            sysbus = machine.GetSystemBus(this);
            DmaRequestA = new GPIO();
            DmaRequestB = new GPIO();
            blocks = new[] { new Block(), new Block() };
            timer = new LimitTimer(machine.ClockSource, 1000000, this, "frames", 1000, enabled: false, eventEnabled: true, autoUpdate: true);
            timer.LimitReached += OnTick;
            Reset();
        }

        public void Reset()
        {
            foreach(var b in blocks)
            {
                b.Reset();
            }
            timer.Enabled = false;
            frameRemainder = 0;
        }

        public uint ReadDoubleWord(long offset)
        {
            if(offset == 0)
            {
                return gcr;
            }
            if(!TryGetBlock(offset, out var b, out var reg))
            {
                return 0;
            }
            switch(reg)
            {
            case 0x00: return b.CR1;
            case 0x04: return b.CR2;
            case 0x08: return b.FRCR;
            case 0x0C: return b.SLOTR;
            case 0x10: return b.IMR;
            case 0x14: return b.Status();
            case 0x1C: return b.Pop();
            }
            return 0;
        }

        public void WriteDoubleWord(long offset, uint value)
        {
            if(offset == 0)
            {
                gcr = value;
                return;
            }
            if(!TryGetBlock(offset, out var b, out var reg))
            {
                return;
            }
            switch(reg)
            {
            case 0x00:
                b.CR1 = value;
                UpdateTimer();
                break;
            case 0x04:
                if((value & 0x8) != 0)
                {
                    b.Fifo.Clear();
                }
                b.CR2 = value & ~0x8u;
                break;
            case 0x08: b.FRCR = value; break;
            case 0x0C: b.SLOTR = value; break;
            case 0x10: b.IMR = value; break;
            case 0x18: b.Flags &= ~value; break;
            case 0x1C: b.Push(value); break;
            }
        }

        public long Size => 0x400;

        public GPIO DmaRequestA { get; }
        public GPIO DmaRequestB { get; }

        public ulong FramesSent { get; private set; }
        public uint FrameRate => frameRate;

        private void UpdateTimer()
        {
            var a = blocks[0];
            var running = a.Enabled;
            if(running && !timer.Enabled)
            {
                frameRate = ComputeFrameRate(a);
                this.Log(LogLevel.Info, "SAI block A started: {0} Hz frames, CR1=0x{1:X8} FRCR=0x{2:X8} SLOTR=0x{3:X8}",
                    frameRate, a.CR1, a.FRCR, a.SLOTR);
                codec.SetSampleRate(frameRate);
                frameRemainder = 0;
                timer.Frequency = (long)TickFrequency;
                timer.Limit = 1;
                timer.Value = 0;
                timer.Enabled = true;
            }
            else if(!running && timer.Enabled)
            {
                timer.Enabled = false;
                this.Log(LogLevel.Info, "SAI block A stopped after {0} frames", FramesSent);
            }
        }

        private uint ComputeFrameRate(Block a)
        {
            /* SAI kernel clock from RCC: DCKCFGR1.SAIxSEL picks PLLSAI_Q/DIVQ or PLLI2S_Q/DIVQ. */
            var dckcfgr = sysbus.ReadDoubleWord(rccAddress + 0x8C);
            var pllcfgr = sysbus.ReadDoubleWord(rccAddress + 0x04);
            var select = (dckcfgr >> (secondInstance ? 22 : 20)) & 3;
            var m = pllcfgr & 0x3F;
            var input = ((pllcfgr >> 22) & 1) != 0 ? hseFrequency : 16000000u;
            ulong kernel = 0;
            if(select <= 1 && m != 0)
            {
                var cfg = sysbus.ReadDoubleWord(rccAddress + (select == 0 ? 0x88UL : 0x84UL));
                var n = (cfg >> 6) & 0x1FF;
                var q = (cfg >> 24) & 0xF;
                var divq = select == 0 ? ((dckcfgr >> 8) & 0x1F) + 1 : (dckcfgr & 0x1F) + 1;
                if(q != 0)
                {
                    kernel = (ulong)input / m * n / q / divq;
                }
            }
            var mckdiv = (a.CR1 >> 20) & 0xF;
            var nodiv = (a.CR1 & (1 << 19)) != 0;
            var frameBits = (a.FRCR & 0xFF) + 1;
            uint rate;
            if(kernel == 0)
            {
                rate = 48000;
                this.Log(LogLevel.Warning, "SAI kernel clock unknown (DCKCFGR1=0x{0:X8}), assuming 48 kHz", dckcfgr);
            }
            else if(nodiv)
            {
                rate = (uint)(kernel / (mckdiv == 0 ? 1u : mckdiv) / frameBits);
            }
            else
            {
                rate = (uint)(kernel / ((mckdiv == 0 ? 1u : 2u * mckdiv) * 256u));
            }
            this.Log(LogLevel.Info, "SAI kernel clock {0} Hz, MCKDIV={1}, NODIV={2}, frame {3} bits", kernel, mckdiv, nodiv, frameBits);
            return rate;
        }

        private void OnTick()
        {
            frameRemainder += frameRate;
            var frames = frameRemainder / TickFrequency;
            frameRemainder %= TickFrequency;
            for(var i = 0u; i < frames && blocks[0].Enabled; i++)
            {
                ProcessFrame();
            }
        }

        private void ProcessFrame()
        {
            var a = blocks[0];
            var b = blocks[1];
            var frameBits = (int)(a.FRCR & 0xFF) + 1;
            var activeLength = (int)((a.FRCR >> 8) & 0x7F) + 1;
            var fsDefinition = (a.FRCR & (1 << 16)) != 0;
            var fsActiveHigh = (a.FRCR & (1 << 17)) != 0;
            var fsOffset = (a.FRCR & (1 << 18)) != 0 ? 1 : 0;
            var slotCount = (int)((a.SLOTR >> 8) & 0xF) + 1;
            var slotEnable = a.SLOTR >> 16;
            var dataSize = DataSizeBits(a.CR1);
            var slotSize = SlotSizeBits(a.SLOTR, dataSize);
            var firstBitOffset = (int)(a.SLOTR & 0x1F);
            var lsbFirst = (a.CR1 & (1 << 8)) != 0;

            /* Keep block A's FIFO fed: one DMA request per free FIFO word. */
            Refill(a, DmaRequestA, 0);

            var data = new bool[frameBits];
            var lrclk = new bool[frameBits];
            for(var bit = 0; bit < frameBits; bit++)
            {
                /* FS is asserted fsOffset bits before slot 0, for activeLength bits. */
                var position = (bit + fsOffset) % frameBits;
                var asserted = fsDefinition ? position < activeLength : position == 0;
                lrclk[bit] = asserted == fsActiveHigh;
            }
            for(var slot = 0; slot < slotCount; slot++)
            {
                if((slotEnable & (1u << slot)) == 0)
                {
                    continue;
                }
                uint word;
                if(a.Fifo.Count > 0)
                {
                    word = a.Fifo.Dequeue();
                }
                else
                {
                    word = 0;
                    a.Flags |= 1; /* OVRUDR: underrun */
                    underruns++;
                }
                var start = slot * slotSize + firstBitOffset;
                for(var i = 0; i < dataSize && start + i < frameBits; i++)
                {
                    var source = lsbFirst ? i : dataSize - 1 - i;
                    data[start + i] = ((word >> source) & 1) != 0;
                }
            }
            FramesSent++;
            codec.ReceiveFrame(data, lrclk);

            if(b.Enabled)
            {
                for(var slot = 0; slot < slotCount; slot++)
                {
                    if((b.SLOTR >> 16 & (1u << slot)) == 0)
                    {
                        continue;
                    }
                    if(b.Fifo.Count >= FifoDepth)
                    {
                        b.Flags |= 1;
                        continue;
                    }
                    b.Fifo.Enqueue(0);
                }
                Drain(b, DmaRequestB);
            }
            Refill(a, DmaRequestA, 0);
        }

        private void Refill(Block a, GPIO request, int unused)
        {
            if(!a.DmaEnabled)
            {
                return;
            }
            for(var attempts = 0; a.Fifo.Count < FifoDepth && attempts < FifoDepth; attempts++)
            {
                var before = a.Fifo.Count;
                request.Blink();
                if(a.Fifo.Count == before)
                {
                    break;
                }
            }
        }

        private void Drain(Block b, GPIO request)
        {
            if(!b.DmaEnabled)
            {
                return;
            }
            for(var attempts = 0; b.Fifo.Count > 0 && attempts < FifoDepth; attempts++)
            {
                var before = b.Fifo.Count;
                request.Blink();
                if(b.Fifo.Count == before)
                {
                    break;
                }
            }
        }

        private static int DataSizeBits(uint cr1)
        {
            switch((cr1 >> 5) & 7)
            {
            case 2: return 8;
            case 3: return 10;
            case 4: return 16;
            case 5: return 20;
            case 6: return 24;
            case 7: return 32;
            default: return 8;
            }
        }

        private static int SlotSizeBits(uint slotr, int dataSize)
        {
            switch((slotr >> 6) & 3)
            {
            case 1: return 16;
            case 2: return 32;
            default: return dataSize;
            }
        }

        private bool TryGetBlock(long offset, out Block block, out long reg)
        {
            block = null;
            reg = 0;
            if(offset >= 0x04 && offset < 0x24)
            {
                block = blocks[0];
                reg = offset - 0x04;
                return true;
            }
            if(offset >= 0x24 && offset < 0x44)
            {
                block = blocks[1];
                reg = offset - 0x24;
                return true;
            }
            return false;
        }

        private uint gcr;
        private uint frameRate;
        private ulong frameRemainder;
        private ulong underruns;

        private readonly IMachine machine;
        private readonly WM8994 codec;
        private readonly ulong rccAddress;
        private readonly bool secondInstance;
        private readonly uint hseFrequency;
        private readonly IBusController sysbus;
        private readonly Block[] blocks;
        private readonly LimitTimer timer;

        private const int FifoDepth = 8;
        private const ulong TickFrequency = 4000;

        private class Block
        {
            public void Reset()
            {
                CR1 = 0x40;
                CR2 = 0;
                FRCR = 0x7;
                SLOTR = 0;
                IMR = 0;
                Flags = 0;
                Fifo.Clear();
            }

            public uint Status()
            {
                /* FLVL: 0 empty, 1 < 1/4, 2 < 1/2, 3 < 3/4, 4 < full, 5 full */
                uint level = Fifo.Count == 0 ? 0u : Fifo.Count >= FifoDepth ? 5u : (uint)(1 + Fifo.Count * 4 / FifoDepth);
                return Flags | (level << 16);
            }

            public void Push(uint value)
            {
                if(Fifo.Count < FifoDepth)
                {
                    Fifo.Enqueue(value);
                }
            }

            public uint Pop()
            {
                return Fifo.Count > 0 ? Fifo.Dequeue() : 0;
            }

            public bool Enabled => (CR1 & (1 << 16)) != 0;
            public bool DmaEnabled => Enabled && (CR1 & (1 << 17)) != 0;

            public uint CR1;
            public uint CR2;
            public uint FRCR;
            public uint SLOTR;
            public uint IMR;
            public uint Flags;
            public readonly Queue<uint> Fifo = new Queue<uint>();
        }
    }

    public class WM8994 : II2CPeripheral
    {
        public WM8994(string outputFile = "")
        {
            OutputFile = outputFile;
            Reset();
        }

        public void Reset()
        {
            registers.Clear();
            /* Reset values that matter for the audio path (WM8994 datasheet). */
            registers[0x0300] = 0x4050; /* AIF1: I2S, 24-bit */
            registers[0x0420] = 0x0200; /* DAC1 soft mute */
            pointer = 0;
            pointerBytes = 0;
            stream.Clear();
            lastLrclk = null;
        }

        public string OutputFile
        {
            get => outputFile;
            set
            {
                output?.Dispose();
                output = null;
                outputFile = value;
                if(!string.IsNullOrEmpty(value))
                {
                    output = new FileStream(value, FileMode.Create, FileAccess.Write);
                }
            }
        }

        public ulong FramesDecoded { get; private set; }
        public uint SampleRate { get; private set; }

        public void SetSampleRate(uint rate)
        {
            SampleRate = rate;
        }

        public void Write(byte[] data)
        {
            var index = 0;
            if(pointerBytes < 2)
            {
                for(; index < data.Length && pointerBytes < 2; index++, pointerBytes++)
                {
                    pointer = (ushort)((pointer << 8) | data[index]);
                }
            }
            for(; index + 1 < data.Length; index += 2)
            {
                var value = (ushort)((data[index] << 8) | data[index + 1]);
                WriteRegister(pointer, value);
                pointer++;
            }
        }

        public byte[] Read(int count = 1)
        {
            var result = new byte[count];
            for(var i = 0; i + 1 < count; i += 2)
            {
                var value = ReadRegister(pointer);
                result[i] = (byte)(value >> 8);
                result[i + 1] = (byte)value;
                pointer++;
            }
            return result;
        }

        public void FinishTransmission()
        {
            pointerBytes = 0;
        }

        public ushort ReadRegister(ushort address)
        {
            if(address == 0)
            {
                return 0x8994;
            }
            return registers.TryGetValue(address, out var value) ? value : (ushort)0;
        }

        public void WriteRegister(ushort address, ushort value)
        {
            if(address == 0)
            {
                this.Log(LogLevel.Info, "Software reset");
                registers.Clear();
                registers[0x0300] = 0x4050;
                registers[0x0420] = 0x0200;
                return;
            }
            registers[address] = value;
            if(address == 0x0300)
            {
                this.Log(LogLevel.Info, "AIF1_CONTROL1 = 0x{0:X4}: format {1}, {2}-bit, LRCLK_INV={3}, BCLK_INV={4}",
                    value, FormatName((value >> 3) & 3), WordLength(value), (value >> 7) & 1, (value >> 8) & 1);
            }
        }

        /* One SAI frame: data and LRCLK level per bit, in BCLK order. */
        public void ReceiveFrame(bool[] data, bool[] lrclk)
        {
            var control = ReadRegister(0x0300);
            var format = (control >> 3) & 3;
            var lrclkInvert = (control & 0x80) != 0;
            for(var i = 0; i < data.Length; i++)
            {
                var level = lrclk[i] ^ lrclkInvert;
                if(lastLrclk.HasValue && level != lastLrclk.Value)
                {
                    /* I2S frames start on the falling LRCLK edge (left low),
                     * left/right justified and DSP frames on the rising one. */
                    var frameStart = format == I2S ? !level : level;
                    if(frameStart)
                    {
                        if(stream.Count > 0 && halfLength > 0)
                        {
                            DecodeFrame(format, WordLength(control));
                        }
                        stream.Clear();
                        halfLength = 0;
                    }
                    else
                    {
                        halfLength = stream.Count;
                    }
                }
                lastLrclk = level;
                stream.Add(data[i]);
            }
        }

        private void DecodeFrame(int format, int wordLength)
        {
            short left, right;
            switch(format)
            {
            case I2S:
                left = Sample(1, wordLength);
                right = Sample(halfLength + 1, wordLength);
                break;
            case LeftJustified:
                left = Sample(0, wordLength);
                right = Sample(halfLength, wordLength);
                break;
            case RightJustified:
                left = Sample(halfLength - wordLength, wordLength);
                right = Sample(stream.Count - wordLength, wordLength);
                break;
            default: /* DSP mode A */
                left = Sample(1, wordLength);
                right = Sample(1 + wordLength, wordLength);
                break;
            }
            FramesDecoded++;
            if(output == null)
            {
                return;
            }
            var muted = (ReadRegister(0x0420) & 0x0200) != 0;
            if(muted)
            {
                left = right = 0;
            }
            output.WriteByte((byte)left);
            output.WriteByte((byte)(left >> 8));
            output.WriteByte((byte)right);
            output.WriteByte((byte)(right >> 8));
            if((FramesDecoded & 0xFFF) == 0)
            {
                output.Flush();
            }
        }

        /* Top 16 bits of a wordLength-bit MSB-first sample starting at bit start. */
        private short Sample(int start, int wordLength)
        {
            int value = 0;
            for(var i = 0; i < 16; i++)
            {
                var index = start + i;
                var bit = i < wordLength && index >= 0 && index < stream.Count && stream[index];
                value = (value << 1) | (bit ? 1 : 0);
            }
            return (short)value;
        }

        private static int WordLength(int control)
        {
            switch((control >> 5) & 3)
            {
            case 0: return 16;
            case 1: return 20;
            case 2: return 24;
            default: return 32;
            }
        }

        private static string FormatName(int format)
        {
            switch(format)
            {
            case RightJustified: return "right justified";
            case LeftJustified: return "left justified";
            case I2S: return "I2S";
            default: return "DSP";
            }
        }

        private readonly Dictionary<ushort, ushort> registers = new Dictionary<ushort, ushort>();
        private readonly List<bool> stream = new List<bool>();
        private bool? lastLrclk;
        private int halfLength;
        private ushort pointer;
        private int pointerBytes;
        private string outputFile;
        private FileStream output;

        private const int RightJustified = 0;
        private const int LeftJustified = 1;
        private const int I2S = 2;
    }
}
