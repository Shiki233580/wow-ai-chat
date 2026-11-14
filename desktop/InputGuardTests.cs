namespace WhaleChat;
internal static class InputGuardTests
{
 internal static void Run(Action<string,bool> check)
 {
  Packet P()=>new(){session="one",inputGuardVersion=1,inputSample=100,bindingsReady=true};
  var p=P();var s=new InputGuardState();s.Observe(p,0);p.inputSample=102;s.Observe(p,500);
  check("input fence admits fresh unfocused packet",s.Clear(500));
  // User opens a text field after the snapshot but before queued SendInput symbols.
  s.Activity(501);int leaked=0;
  foreach(int key in new[]{188,190,111,219,221,186,222}) {
   if(s.OwnStroke(key,false,502,true))leaked++;
   check("blocked down has no stray keyup "+key,!s.OwnStroke(key,true,502,true));
  }
  check("focus race blocks every queued printable symbol",leaked==0);
  s.Observe(p,900);check("old pixel frame cannot rearm fence",!s.Clear(900));
  p.inputSample=103;p.typing=true;s.Observe(p,950);check("active input keeps fence closed",!s.Clear(950));
  p.typing=false;p.inputSample=104;s.Observe(p,1000);check("input close resumes without manual reconnect",s.Clear(1000));
  check("wrong foreground suppresses own keydown",!s.OwnStroke(188,false,1001,false));
  check("approved own keydown passes",s.OwnStroke(188,false,1002,true));
  s.Activity(1003);check("already sent own down always receives paired up",s.OwnStroke(188,true,1004,false));
  check("never releases a user modifier",!s.OwnStroke(17,true,1005,true)&&!s.OwnStroke(16,true,1005,true));
  p.inputSample=110;s.Observe(p,1100);check("fresh frame inside input transition stays blocked",!s.Clear(1100));
  s.Observe(p,1400);check("transition safety window is not a chat cooldown",s.Clear(1400));
  check("stale screenshot permission expires",!s.Clear(1901));
  s.Observe(p,1950);s.Invalidate();check("failed read immediately closes permission",!s.Clear(1950));
  p.inputGuardVersion=0;s.Observe(p,2000);check("old addon cannot authorize risky injection",!s.Clear(2000));
  p.inputGuardVersion=1;p.professionBusy=true;s.Observe(p,2000);check("profession guard retained",!s.Clear(2000));
  p.professionBusy=false;p.session="two";s.Observe(p,2100);check("new game session needs fresh observation",!s.Clear(2100));
  foreach(int key in new[]{13,191,9,27,70,188,190})check("input-opening physical key fences "+key,InputGuardState.KeyboardCanFocus(key));
  foreach(int key in new[]{87,65,83,68,81,69,32,37,38,39,40})check("ordinary movement does not fence "+key,!InputGuardState.KeyboardCanFocus(key));
  using(var guard=new NativeInputGuard())check("native guard hooks register without injecting input",!guard.Clear);
 }
}
