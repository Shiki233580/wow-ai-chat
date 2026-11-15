using System.Text.Json;
namespace WhaleChat;
internal static class ContextIsolationTests
{
 internal static async Task Run(Action<string,bool> check)
 {
  var old=new[]{new ChatLine("本人","集火碎裂的哨兵，别靠太近。"),new ChatLine("队友","奥术之谜有威胁。")};
  foreach(var mode in new[]{"signal","scene","event"}) {
   var p=new Packet{generationMode=mode,text="我刚发出的信号：看这里",channel="PARTY",recent=old};
   using var body=JsonDocument.Parse(ChatApi.UserMessage(p));var doc=body.RootElement;
   check("proactive source isolation "+mode,doc.GetProperty("recent").GetArrayLength()==0 && doc.GetProperty("recentOwnReplies").GetArrayLength()==0);
   check("proactive current text retained "+mode,doc.GetProperty("text").GetString()==p.text);
   check("context filtering never mutates packet or routing "+mode,p.recent.Length==2&&p.channel=="PARTY");
   var sys=ChatApi.BuildPrompt(new Config(),p,["奥术之谜有威胁","碎裂的哨兵别靠近"],0);
   check("raw historical entities excluded from system prompt "+mode,!sys.Contains("奥术之谜")&&!sys.Contains("碎裂的哨兵"));
  }
  foreach(var mode in new[]{"whisper","public","reply"}) {
   var p=new Packet{generationMode=mode,recent=Enumerable.Range(0,12).Select(i=>new ChatLine("peer",i.ToString())).ToArray()};
   using var b=JsonDocument.Parse(ChatApi.UserMessage(p));
   check("real conversation latest eight preserved "+mode,b.RootElement.GetProperty("recent").GetArrayLength()==8&&ChatApi.ContextForModel(p)[0].text=="4");
   check("unconfirmed drafts excluded from conversation "+mode,b.RootElement.GetProperty("recentOwnReplies").GetArrayLength()==0);
  }
  var config=new Config{character="本人"};var signal=new Packet{generationMode="signal",channel="PARTY",text="我刚发出的信号：看这里",recent=old};
  var chat=new Packet{generationMode="public",channel="PARTY"};
  check("draft memory separates signal and conversation",ChatApi.MemoryScope(config,signal)!=ChatApi.MemoryScope(config,chat));
  check("untargeted signal must not infer tactical intent",ChatApi.BuildPrompt(config,signal,[],0).Contains("不补怪名，不改成集火"));
  var attack=new Packet{generationMode="signal",text="我刚发出的信号：攻击：碎裂的哨兵"};
  check("explicit target still preserved",ChatApi.ExactSignalTarget(attack)=="碎裂的哨兵");
  check("tent special intent retained",ChatApi.TaskInstruction(new Packet{generationMode="signal",text="我正在展示自己放置的帐篷：资深冒险者的探险帐篷"}).Contains("欢迎来蹭"));
  object? logged=null;int calls=0;
  await new ChatApi(config,(k,v)=>{if(k=="request")logged=v;},null,(_,_)=>{calls++;return Task.FromResult("看这边，鲸鲸指给你们看。 ");}).Generate(signal);
  using var log=JsonDocument.Parse(JsonSerializer.Serialize(logged));
  check("generation consumes filtered context without extra API call",calls==1&&log.RootElement.GetProperty("recent").GetArrayLength()==0);
 }
}
