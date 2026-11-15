using System.Diagnostics;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace WhaleChat;

public sealed record ChatLine(string speaker, string text);
public sealed record BridgeKey(int key,int mods);
public sealed class Packet
{
    public int inputGuardVersion {get;set;}
    public double inputSample {get;set;}
    public WorldState? worldState { get; set; }
    public string bridgeTransport { get; set; } = "";
    public BridgeKey[] bridgeDataKeys { get; set; } = [];
    public string session { get; set; } = "";
    public string player { get; set; } = "";
    public string status { get; set; } = "";
    public string detail { get; set; } = "";
    public int protocol { get; set; }
    public int replyMaxChars { get; set; } = 30;
    public int reconnectNonce { get; set; }
    public int receiverLength { get; set; }
    public int receiverProgressChecksum { get; set; }
    public int bridgeRevision { get; set; }
    public string bridgeRxDiagnostic { get; set; }="";
    public bool combat { get; set; }
    public bool professionBusy { get; set; }
    public int craftGuardVersion { get; set; }
    public bool bindingsReady { get; set; }
    public int bridgeOpenKey { get; set; }
    public int bridgeExecuteKey { get; set; }
    public int bridgeOpenMods { get; set; }
    public int bridgeExecuteMods { get; set; }
    public bool receiverOpen { get; set; }
    public int receiverNonce { get; set; }
    public int bridgeReadyNonce { get; set; }
    public int bridgeReadyChecksum { get; set; }
    public int bridgeAck { get; set; }
    public int bridgeAckChecksum { get; set; }
    public string bridgeError { get; set; } = "";
    public bool typing { get; set; }
    public bool auto { get; set; }
    public int requestId { get; set; }
    public bool submitted { get; set; }
    public bool confirmed { get; set; }
    public bool automatic { get; set; }
    public string channel { get; set; } = "";
    public string target { get; set; } = "";
    public int channelNumber { get; set; }
    public string reply { get; set; } = "";
    public string speaker { get; set; } = "";
    public string text { get; set; } = "";
    public bool eventFlavor { get; set; }
    public string eventReply { get; set; } = "";
    public string eventKind { get; set; } = "";
    public string addonVersion { get; set; } = "";
    public string replyPrefix { get; set; } = "";
    public bool whisperAuto { get; set; }
    public int sendUnconfirmed { get; set; }
    public string whisperDiagnostic { get; set; } = "";
    public int whisperQueued { get; set; }
    public int whisperReceivedBN { get; set; }
    public string generationMode { get; set; } = "reply";
    public ChatLine[] recent { get; set; } = [];
    public string Key => session + ":" + requestId;
}

public static class PixelCodec
{
    public const int Width = 256, Height = 130, FontWidth = 384;
    public static byte[] Encode(string text)
    {
        var bytes = Encoding.UTF8.GetBytes(text);
        if (bytes.Length > 6136) throw new InvalidDataException("Packet exceeds pixel capacity");
        var output = new byte[6144];
        Encoding.ASCII.GetBytes("DFY1").CopyTo(output, 0);
        output[4] = (byte)(bytes.Length >> 8); output[5] = (byte)bytes.Length;
        int sum = 0; for (int i = 0; i < bytes.Length; i++) sum = (sum + bytes[i] * (i + 1)) & 65535;
        output[6] = (byte)(sum >> 8); output[7] = (byte)sum;
        bytes.CopyTo(output, 8); return output;
    }
    public static Bitmap Render(byte[] bytes)
    {
        var b = new Bitmap(Width, Height);
        using var g = Graphics.FromImage(b);
        g.Clear(Color.Black);
        void Cell(int index, int r, int green, int blue) { using var brush = new SolidBrush(Color.FromArgb(r, green, blue)); g.FillRectangle(brush, index % 128 * 2, index / 128 * 2, 2, 2); }
        for (int i = 0; i < 4; i++) Cell(i, i * 32, i * 32, i * 32);
        for (int i = 0; i < 8192; i++) { int bit = i * 6, n = bit / 8, shift = bit % 8; int value = ((bytes[n] << 8 | (n + 1 < bytes.Length ? bytes[n + 1] : 0)) >> (10 - shift)) & 63; Cell(i + 4, (value >> 4) * 32, ((value >> 2) & 3) * 32, (value & 3) * 32); }
        return b;
    }
    public static string? Decode(Bitmap b)
    {
        if ((b.Width != Width && b.Width != FontWidth) || b.Height != Height) return null;
        int cellPitch = b.Width / 128; // Native font: 2px ink + 1px gap; legacy fixtures: 2px.
        byte[] data = new byte[6144];
        // Copy once instead of thousands of GDI GetPixel calls per poll.
        int bpp=Image.GetPixelFormatSize(b.PixelFormat)/8;
        if(bpp is not (3 or 4))return null;
        var locked=b.LockBits(new Rectangle(0,0,b.Width,b.Height),ImageLockMode.ReadOnly,b.PixelFormat);
        int stride=locked.Stride,pitch=Math.Abs(stride);var pixels=new byte[pitch*b.Height];
        try{var start=stride<0?IntPtr.Add(locked.Scan0,stride*(b.Height-1)):locked.Scan0;Marshal.Copy(start,pixels,0,pixels.Length);}finally{b.UnlockBits(locked);}
        Color Pixel(int x,int y){int n=(stride<0?b.Height-1-y:y)*pitch+x*bpp;return Color.FromArgb(pixels[n+2],pixels[n+1],pixels[n]);}
        var levels = Enumerable.Range(0, 4).Select(i => Pixel(i * cellPitch + 1, 1)).ToArray();
        for (int i = 1; i < 4; i++) if (levels[i].R - levels[i-1].R < 12 || levels[i].G - levels[i-1].G < 12 || levels[i].B - levels[i-1].B < 12) return null;
        int Quantize(int value, Func<Color,int> select) { int best = 0, distance = 256; for (int i = 0; i < 4; i++) { int d = Math.Abs(value-select(levels[i])); if (d < distance) { best = i; distance = d; } } return distance <= 10 ? best : -1; }
        for (int i = 0; i < 8192; i++) { int cell = i + 4; var c = Pixel(cell % 128 * cellPitch + 1, cell / 128 * 2 + 1); int r=Quantize(c.R,x=>x.R),g=Quantize(c.G,x=>x.G),blue=Quantize(c.B,x=>x.B); if(r<0||g<0||blue<0) return null; int value=(r<<4)|(g<<2)|blue; for(int j=0;j<6;j++){int bit=i*6+j; data[bit/8]|=(byte)(((value>>(5-j))&1)<<(7-bit%8));} }
        if (Encoding.ASCII.GetString(data, 0, 4) != "DFY1") return null;
        int n = data[4] * 256 + data[5]; if (n is < 2 or > 6136) return null;
        int sum = 0; for (int i = 0; i < n; i++) sum = (sum + data[i + 8] * (i + 1)) & 65535;
        if (sum != data[6] * 256 + data[7]) return null;
        try { return new UTF8Encoding(false, true).GetString(data, 8, n); } catch { return null; }
    }
}

internal static class Native
{
    internal static NativeInputGuard? InputGuard;
    internal static string LastReadDiagnostic = "not_sampled";
    internal static string? LastDecodedPlayer;
    [DllImport("user32.dll")] internal static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] input, int size);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint size, tick; }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION data; }
    [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public KEYBDINPUT key; [FieldOffset(0)] public MOUSEINPUT mouse; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int x, y; public uint mouseData, flags, time; public UIntPtr extra; }
    internal static bool IsGame(IntPtr h, Config c)
    {
        try { GetWindowThreadProcessId(h, out uint pid); using var p = Process.GetProcessById((int)pid); return string.Equals(p.MainModule?.FileName, c.gameExe, StringComparison.OrdinalIgnoreCase); } catch { return false; }
    }
    internal static (IntPtr window, Packet packet)? Read(Config c, string? saveImage = null)
    {
        InputGuard?.Invalidate(); // A failed/torn/covered read must not leave stale permission.
        LastDecodedPlayer = null;
        var h = GetForegroundWindow(); if (!IsGame(h, c)) { LastReadDiagnostic="foreground_not_expected_game"; return null; }
        if (!GetClientRect(h, out var r) || r.right < PixelCodec.FontWidth+16 || r.bottom < PixelCodec.Height+16) { LastReadDiagnostic="client_rect_invalid"; return null; }
        var p = new POINT { x = 8, y = 8 }; if (!ClientToScreen(h, ref p)) { LastReadDiagnostic="client_origin_failed"; return null; }
        using var b = new Bitmap(PixelCodec.FontWidth, PixelCodec.Height, PixelFormat.Format24bppRgb);
        using (var g = Graphics.FromImage(b)) g.CopyFromScreen(p.x, p.y, 0, 0, b.Size, CopyPixelOperation.SourceCopy);
        if (saveImage != null) b.Save(saveImage, ImageFormat.Png);
        var data = PixelCodec.Decode(b); if (data == null) { LastReadDiagnostic="pixel_calibration_or_checksum_failed"; return null; }
        try { var packet = JsonSerializer.Deserialize<Packet>(data); LastDecodedPlayer=packet?.player; if (packet == null || packet.player != c.character) { LastReadDiagnostic="character_mismatch"; return null; } InputGuard?.Observe(packet,h);LastReadDiagnostic="decoded"; return (h, packet); } catch { LastReadDiagnostic="packet_json_invalid"; return null; }
    }
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint mapType);
    static INPUT Key(ushort vk, bool up = false)
    {
        // Raw-input clients need the physical scan code for extended function keys.
        // Only function keys are allowed; never synthesize user modifier releases.
        if (vk is >=124 and <=135)
        {
            uint scan = MapVirtualKey(vk, 0);
            if (scan == 0 || scan > 255) throw new InvalidOperationException("Unsupported extended function-key scan code");
            return new() { type=1, data=new UNION { key=new KEYBDINPUT { scan=(ushort)scan, flags=8u|(up?2u:0u),extra=NativeInputGuard.Tag } } };
        }
        uint extended=vk is 33 or 34 or 35 or 36 or 45 or 46 or 111 ? 1u : 0u;
        return new() { type=1, data=new UNION { key=new KEYBDINPUT { vk=vk, flags=extended|(up?2u:0u),extra=NativeInputGuard.Tag } } };
    }
    static void InputStrokes((ushort key,bool up)[] plan)
    {
        BridgeStrokeWriter.Write(plan, strokes=>{
            var events=strokes.Select(x=>Key(x.key,x.up)).ToArray();
            int inserted=(int)SendInput((uint)events.Length,events,Marshal.SizeOf<INPUT>());
            int error=Marshal.GetLastWin32Error();return (inserted,error);
        });
    }
    internal static bool KeysReleased()
    {
        for(int key=1;key<255;key++) if((GetAsyncKeyState(key)&0x8000)!=0) return false; return true;
    }
    internal static bool CanUseBridge(Packet? p)=>InputGuard?.Clear==true&&p?.professionBusy!=true&&BridgeInputPolicy.Clear(p,key=>(GetAsyncKeyState(key)&0x8000)!=0);
    internal static string BridgeWaitReason(Packet p)=>p.typing?"input_box_focused":InputGuard?.Clear!=true?"input_transition_guard":"bridge_modifier_or_reserved_key_held";
    static bool InputClear(bool extended)=>BridgeInputPolicy.Clear(extended,key=>(GetAsyncKeyState(key)&0x8000)!=0);
    internal static bool UserIdle(int ms) { var value=new LASTINPUTINFO { size=(uint)Marshal.SizeOf<LASTINPUTINFO>() }; return GetLastInputInfo(ref value)&&unchecked((uint)Environment.TickCount-value.tick)>=(uint)ms; }
    internal static ushort[] ReceiverKeys(int key,int modifiers)
    {
        if(!BridgeInputPolicy.AllowedKey(key)||modifiers!=0) throw new InvalidDataException("Invalid function-key chord");
        return new[]{(ushort)key};
    }
    internal static (ushort key,bool up)[] ReceiverStrokePlan(int key,int modifiers)
    {
        var keys=ReceiverKeys(key,modifiers);
        return keys.Select(k=>(k,false)).Concat(keys.Reverse().Select(k=>(k,true))).ToArray();
    }
    internal static Task ReceiverChord(Config c,int key,int modifiers,bool extended=false,Packet? source=null)
    {
        var keys=ReceiverKeys(key,modifiers);
        if(extended&&(!BridgeInputPolicy.AllowedKey(key)||modifiers!=0))throw new NativeInputNotStartedException("Invalid extended key");
        if(InputGuard?.Clear!=true||!IsGame(GetForegroundWindow(),c)||!(source==null?InputClear(extended):CanUseBridge(source))) throw new NativeInputNotStartedException("Unsafe receiver key state; no native input issued");
        // One ordered stroke, like the already-working data-key stream. No modifier hold or blind post-key sleep.
        // Completion is verified by the dispatcher's existing pixel ACK, not a fixed delay.
        InputStrokes(ReceiverStrokePlan(key,modifiers));
        return Task.CompletedTask;
    }
    internal static Task ReceiverText(Config c,string text,Packet source,Func<bool> enabled)
    {
        long suppressed=InputGuard?.Suppressed??0;
        return BridgeFlow.Transfer(text,source,()=>Read(c)?.packet,CanUseBridge,enabled,
            events=>{
                if(!enabled()||!IsGame(GetForegroundWindow(),c)||!CanUseBridge(source))
                    throw new NativeInputNotStartedException("Input changed before native batch; no input issued");
                InputStrokes(events);
            },()=>Task.Delay(BridgeTiming.AckPollMs),
            (nonce,count,total,events)=>Program.Log("bridge_chunk",new{source.session,nonce,bytes=count,total,nativeEvents=events}),
            ()=>InputGuard==null||InputGuard.Suppressed!=suppressed);
    }
    internal static Task<bool> Command(Config c, string session, string command, Func<bool> enabled, int? requestId = null) => new BridgeDispatcher(new NativeBridgePort(c,enabled)).Send(session,command,requestId);
}

internal sealed class NativeBridgePort(Config config,Func<bool> enabled):IBridgePort
{
    Packet? last;
    public Packet? Read()=>last=Native.Read(config)?.packet;
    public bool Enabled=>enabled();
    public bool Idle=>true; // No elapsed idle gate; actual keys/focus still verified.
    public bool KeysUp=>Native.CanUseBridge(last);
    public Task OpenReceiver(int key,int modifiers){Program.Log("bridge_stage",new{stage="open",key,modifiers});return Native.ReceiverChord(config,key,modifiers,BridgeInputPolicy.Extended(last),last);}
    public Task TypeReceiver(string text){Program.Log("bridge_stage",new{stage="text",length=text.Length,checksum=text[(text.LastIndexOf(';')+1)..^1]});return Native.ReceiverText(config,text,last??throw new InvalidOperationException("Missing packet"),()=>enabled());}
    public Task ExecutePrepared(int key,int modifiers){Program.Log("bridge_stage",new{stage="execute",key,modifiers});return Native.ReceiverChord(config,key,modifiers,BridgeInputPolicy.Extended(last),last);}
    public Task Delay()=>Task.Delay(BridgeTiming.AckPollMs);
}
