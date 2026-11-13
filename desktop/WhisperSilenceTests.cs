namespace WhaleChat;

internal static class WhisperSilenceTests
{
    internal static Config FixtureConfig()=>new(){character="测试鲸-测试服",requestTimeoutMs=1000};
    internal static Packet First(string text="11",string channel="BN_WHISPER")=>new(){generationMode="whisper",channel=channel,target="64",text=text,speaker="好友",recent=[new("好友",text)]};
    internal static Task<Reply> FirstResult()=>new ChatApi(FixtureConfig(),(_,_)=>{},null,(_,_)=>Task.FromResult("…")).Generate(First());
    internal static async Task Run(Action<string,bool> check)
    {
        var config=FixtureConfig();
        foreach(string channel in new[]{"BN_WHISPER","WHISPER"}) {
            foreach(string text in new[]{"11","1","?","你好","谢谢"}) {
                int calls=0;bool guarded=false,logged=false;
                var reply=await new ChatApi(config,(kind,_)=>logged|=kind=="whisper_silence_overridden",null,(prompt,_)=>{calls++;guarded=prompt.Contains("本轮必须回应");return Task.FromResult("…");}).Generate(First(text,channel));
                check("first private short turn cannot be silenced "+channel+" "+text,reply.text!="…"&&calls==1&&guarded&&logged&&reply.text.Length<=48);
            }
            var p=First("好",channel);p.recent=[new("好友","在吗"),new(config.character,"在呢，什么事？"),new("好友","好")];
            int count=0;bool closingPrompt=false;
            var ending=await new ChatApi(config,(_,_)=>{},null,(prompt,_)=>{count++;closingPrompt=prompt.Contains("本轮已有本人真实回复");return Task.FromResult("…");}).Generate(p);
            check("real answered simple closure may stay silent "+channel,ending.text=="…"&&count==1&&closingPrompt);
            foreach(string text in new[]{"好，几点走？","11","同一个问题再问一次","谢谢？"}) {
                p=First(text,channel);p.recent=[new(config.character,"先前的回答"),new("好友",text)];
                var reply=await new ChatApi(config,(_,_)=>{},null,(_,_)=>Task.FromResult("…")).Generate(p);
                check("new question or numeric ping after own reply still answered "+channel+" "+text,reply.text!="…");
            }
            p=First("好",channel);p.recent=[new(config.character,"先前答复"),new("好友","几点走？"),new("好友","好")];
            var burst=await new ChatApi(config,(_,_)=>{},null,(_,_)=>Task.FromResult("…")).Generate(p);
            check("closing last word cannot hide unanswered burst question "+channel,burst.text!="…");
            p=First("好",channel);p.recent=[new("另一个人","我回答过了"),new("好友","好")];
            var foreign=await new ChatApi(config,(_,_)=>{},null,(_,_)=>Task.FromResult("…")).Generate(p);
            check("foreign speaker is not proof of own reply "+channel,foreign.text!="…");
            p=First("好",channel);p.recent=[new("好友","好"),new(config.character,"迟到的发送回执")];
            var late=await new ChatApi(config,(_,_)=>{},null,(_,_)=>Task.FromResult("…")).Generate(p);
            check("late own ACK is not proof new incoming was answered "+channel,late.text!="…");
        }
        var ordinary=await new ChatApi(config,(_,_)=>{},null,(_,_)=>Task.FromResult("听着呢，有事说呗。")).Generate(First());
        check("normal model wording unchanged",ordinary.text=="听着呢，有事说呗。");
        var publicEvent=new Packet{generationMode="event",channel="SAY",text="测试"};
        var other=await new ChatApi(config,(_,_)=>{},null,(_,_)=>Task.FromResult("…")).Generate(publicEvent);
        check("private fallback does not alter other generation modes",other.text=="…");
        string memory=Path.Combine(Path.GetTempPath(),"dfy-private-silence-"+Guid.NewGuid()+".json");
        try {
            var p=First("好");new VoiceMemory(memory).Add(ChatApi.MemoryScope(config,p),"历史草稿不是已发送",0);
            var draft=await new ChatApi(config,(_,_)=>{},memory,(_,_)=>Task.FromResult("…")).Generate(p);
            check("draft memory never authorizes silence",draft.text!="…");
        } finally {File.Delete(memory);}
        using var cancelled=new CancellationTokenSource();cancelled.Cancel();bool stopped=false;
        try{await new ChatApi(config,(_,_)=>{},null,(_,ct)=>{ct.ThrowIfCancellationRequested();return Task.FromResult("…");}).Generate(First(),cancelled.Token);}catch(OperationCanceledException){stopped=true;}
        check("explicit cancellation never creates canned reply",stopped);
    }
}
