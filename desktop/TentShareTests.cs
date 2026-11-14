namespace WhaleChat;
internal static class TentShareTests
{
 internal static async Task Run(Action<string,bool> check)
 {
  foreach(string input in new[]{"大佬早上好，求帐篷蹭一下~","大佬，蹭个帐篷，谢谢","能蹭下你的帐篷吗？","借用一下帐篷，谢谢"})
  foreach(string membership in new[]{"yes","no","unknown"}) {
   var p=new Packet{generationMode="whisper",channel="WHISPER",text=input,worldState=new(){group="party",peerInGroup=membership}};
   int calls=0;var reply=await new ChatApi(new Config(),(_,_)=>{},null,(_,_)=>{calls++;return Task.FromResult("帐篷我没摆。");}).Generate(p);
   check("tent share grounded without model "+input+membership,calls==0&&!reply.text.Contains("没摆")&&!reply.text.Contains("放好了")&&(reply.text.Contains("进队")== (membership=="yes")));
  }
  foreach(string input in new[]{"不用蹭帐篷了，谢谢","昨天蹭了你的帐篷","我不想蹭帐篷","你摆帐篷了吗？","帐篷在哪里？","能帮我摆个帐篷吗","你能卖帐篷给我吗","早上好","帐篷","听别人说你没摆帐篷","蹭帐篷是什么意思"})
   check("tent sharing classifier does not hijack other intent "+input,!WorldStateReplies.TryAnswer(new Packet{generationMode="whisper",text=input},out _));
  check("non-chat event remains untouched",!WorldStateReplies.TryAnswer(new Packet{generationMode="event",text="大佬，蹭个帐篷，谢谢"},out _));
  check("prompt excludes tent inference from group state",WorldStateReplies.Guidance(new Packet()).Contains("快照没有帐篷的摆放或归属数据"));
 }
}
