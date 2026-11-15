using System.Runtime.InteropServices;
namespace WhaleChat;

// No text/key history is stored. This latch closes the pixel-sampling/input race.
internal sealed class InputGuardState
{
 internal const int SettleMs=350;
 string session="";double sample,barrier;long activityAt,observedAt;bool allowed;
 readonly HashSet<int> ownDown=[];
 internal long Suppressed {get;private set;}
 internal void Activity(long now){activityAt=now;barrier=sample;allowed=false;}
 internal void Invalidate(){allowed=false;}
 internal void Observe(Packet p,long now)
 {
  if(session!=p.session){session=p.session;sample=p.inputSample;Activity(now);}
  if(p.inputSample<sample){sample=p.inputSample;Activity(now);}
  sample=p.inputSample;observedAt=now;
  allowed=p.inputGuardVersion==1&&double.IsFinite(sample)&&sample>barrier&&now-activityAt>=SettleMs&&!p.typing&&!p.professionBusy&&p.bindingsReady;
 }
 internal bool Clear(long now)=>allowed&&now-observedAt<=500;
 internal bool OwnStroke(int key,bool up,long now,bool correctWindow)
 {
  // A key-up is passed only for a down we actually allowed; never release user keys.
  if(up)return ownDown.Remove(key);
  if(!correctWindow||!Clear(now)){Suppressed++;return false;}
  ownDown.Add(key);return true;
 }
 internal static bool KeyboardCanFocus(int key)=>key is not (65 or 68 or 69 or 81 or 83 or 87 or 32 or 37 or 38 or 39 or 40);
}

// Dedicated hook thread: it can intercept our queued strokes even while the UI
// thread is taking a screenshot. Physical input always passes through unchanged.
internal sealed class NativeInputGuard:IDisposable
{
 internal static readonly UIntPtr Tag=(UIntPtr)(0x44460000u^(uint)Environment.ProcessId);
 readonly object gate=new();readonly InputGuardState state=new();
 readonly ManualResetEventSlim started=new();readonly Thread thread;
 readonly HookProc keyboard,mouse;IntPtr keyHook,mouseHook,target;uint threadId;volatile bool ready;int error;
 delegate IntPtr HookProc(int code,IntPtr message,IntPtr data);
 [StructLayout(LayoutKind.Sequential)] struct KeyboardData {public uint key,scan,flags,time;public UIntPtr extra;}
 [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SetWindowsHookEx(int id,HookProc proc,IntPtr module,uint tid);
 [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
 [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook,int code,IntPtr message,IntPtr data);
 [DllImport("user32.dll")] static extern bool PostThreadMessage(uint id,uint message,UIntPtr w,IntPtr l);
 [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string? name);
 internal NativeInputGuard()
 {
  keyboard=Keyboard;mouse=Mouse;thread=new Thread(Run){IsBackground=true,Name="DFY input race guard"};thread.SetApartmentState(ApartmentState.STA);thread.Start();
  if(!started.Wait(3000)||!ready)throw new InvalidOperationException("Input guard unavailable; no bridge input allowed. Win32="+error);
 }
 void Run()
 {
  threadId=GetCurrentThreadId();
  try {
   keyHook=SetWindowsHookEx(13,keyboard,GetModuleHandle(null),0);
   mouseHook=SetWindowsHookEx(14,mouse,GetModuleHandle(null),0);
   error=Marshal.GetLastWin32Error();ready=keyHook!=IntPtr.Zero&&mouseHook!=IntPtr.Zero;
   if(ready) {EventHandler announce=(_,_)=>started.Set();Application.Idle+=announce;try{Application.Run();}finally{Application.Idle-=announce;}}
   else started.Set();
  } finally {ready=false;if(keyHook!=IntPtr.Zero)UnhookWindowsHookEx(keyHook);if(mouseHook!=IntPtr.Zero)UnhookWindowsHookEx(mouseHook);started.Set();}
 }
 IntPtr Keyboard(int code,IntPtr message,IntPtr data)
 {
  if(code>=0) {
   var e=Marshal.PtrToStructure<KeyboardData>(data);bool up=(e.flags&128)!=0;
   lock(gate) {
    if(e.extra==Tag&&(e.flags&16)!=0) {
     if(!state.OwnStroke((int)e.key,up,Environment.TickCount64,target!=IntPtr.Zero&&Native.GetForegroundWindow()==target))return (IntPtr)1;
    } else if(InputGuardState.KeyboardCanFocus((int)e.key)||(e.flags&16)!=0)state.Activity(Environment.TickCount64);
   }
  }
  return CallNextHookEx(keyHook,code,message,data);
 }
 IntPtr Mouse(int code,IntPtr message,IntPtr data)
 {
  // Mouse movement/camera rotation alone never blocks an ongoing reply.
  if(code>=0&&message.ToInt64()!=0x200)lock(gate)state.Activity(Environment.TickCount64);
  return CallNextHookEx(mouseHook,code,message,data);
 }
 internal void Observe(Packet p,IntPtr window){lock(gate){target=window;state.Observe(p,Environment.TickCount64);}}
 internal void Invalidate(){lock(gate)state.Invalidate();}
 internal bool Clear {get{lock(gate)return ready&&state.Clear(Environment.TickCount64);}}
 internal long Suppressed {get{lock(gate)return state.Suppressed;}}
 public void Dispose(){lock(gate)state.Invalidate();if(threadId!=0)PostThreadMessage(threadId,0x12,UIntPtr.Zero,IntPtr.Zero);thread.Join(1000);}
}
