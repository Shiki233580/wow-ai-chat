using System.Text;
namespace WhaleChat;
internal static class EventFlavorTests
{
 internal static async Task Run(Action<string,bool> check) {
  Packet P()=>new(){generationMode="event",channel="SAY",eventFlavor=true,eventReply="【拉斯玛尔之怒】已交付，获得【被遗忘者巨斧】！",replyPrefix="【大肥鱼】",text="本人交付任务并领取物品奖励"};
  var p=P();int calls=0;bool promptOk=false;
  var result=await new ChatApi(new Config(),(_,_)=>{},null,(prompt,ct)=>{calls++;promptOk=prompt.Contains("只输出一句")&&prompt.Contains("本地固定添加");return Task.FromResult("哼，这趟没白忙。");}).Generate(p);
  check("event flavor single request with fixed header excluded",calls==1&&promptOk&&result.text=="哼，这趟没白忙。");
  p.status="READY";p.reply=p.replyPrefix+p.eventReply+" "+result.text;
  check("composed preview acknowledged without retransmit",DeliveryRecovery.ReplyObserved(p,result));
  p.reply+="错";check("different preview not falsely acknowledged",!DeliveryRecovery.ReplyObserved(p,result));
  foreach(var raw in new[]{"…",new string('哼',30),"哼，还不错。才没高兴呢。"}) {
   calls=0;var r=await new ChatApi(new Config(),(_,_)=>{},null,(_,_)=>{calls++;return Task.FromResult(raw);}).Generate(P());
   check("one valid flavor no extra request "+raw,calls==1&&r.text!="…"&&r.text.EnumerateRunes().Count()<=24&&!r.text.Contains("才没高兴"));
  }
  foreach(Exception ex in new Exception[]{new HttpRequestException("fixture"),new InvalidDataException("fixture"),new TaskCanceledException("deadline")}) {
   calls=0;bool logged=false;var r=await new ChatApi(new Config(),(k,_)=>logged|=k=="event_flavor_unavailable",null,(_,_)=>{calls++;throw ex;}).Generate(P());
   check("API failure one local flavor "+ex.GetType().Name,calls==1&&logged&&r.text=="哼，这趟没白忙。");
  }
  using var cancel=new CancellationTokenSource();cancel.Cancel();bool stopped=false;
  try{await new ChatApi(new Config(),(_,_)=>{},null,(_,ct)=>{ct.ThrowIfCancellationRequested();return Task.FromResult("…");}).Generate(P(),cancel.Token);}catch(OperationCanceledException){stopped=true;}
  check("explicit cancellation never fallback sends",stopped);
  p=P();p.eventFlavor=false;calls=0;var legacy=await new ChatApi(new Config(),(_,_)=>{},null,(_,_)=>{calls++;throw new Exception("unexpected");}).Generate(p);
  check("old packet still zero API",calls==0&&legacy.text==p.eventReply&&legacy.provider=="local-event-template");
  p=P();p.eventReply="";calls=0;bool natural=false;
  var free=await new ChatApi(new Config(),(_,_)=>{},null,(prompt,_)=>{calls++;natural=prompt.Contains("插件只会添加【大肥鱼】")&&prompt.Contains("不写任务播报");return Task.FromResult("哼，这趟没白忙。");}).Generate(p);
  check("new event natural sentence one request no template",calls==1&&natural&&free.text=="哼，这趟没白忙。");
  p.status="READY";p.reply=p.replyPrefix+free.text;
  check("prefix-only event ACK recognized",DeliveryRecovery.ReplyObserved(p,free));
  p.reply=p.replyPrefix+"【旧任务】已交付！ "+free.text;
  check("old header not mistaken for prefix-only ACK",!DeliveryRecovery.ReplyObserved(p,free));

 }
}
