using System.Net;
using System.Text;
using System.Text.Json;

namespace WhaleChat;

internal static class Tests
{
    internal static async Task<int> Run(string root, Config config)
    {
        var checks = new List<object>();
        Directory.CreateDirectory(Path.Combine(root, "verification"));
        void Check(string name, bool pass) { checks.Add(new { name, pass }); File.WriteAllText(Path.Combine(root,"verification","transport-progress.json"),JsonSerializer.Serialize(checks)); if (!pass) throw new Exception("FAIL: " + name); }
        Check("scene instruction is proactive", ChatApi.TaskInstruction(new Packet {generationMode="scene"}).Contains("主动"));
        Check("signal instruction preserves intent", ChatApi.TaskInstruction(new Packet {generationMode="signal"}).Contains("意图不能丢失"));
        Check("legacy task remains reply", ChatApi.TaskInstruction(new Packet()).Contains("回复最后一句"));
        Check("mode survives packet JSON", JsonSerializer.Deserialize<Packet>(JsonSerializer.Serialize(new Packet {generationMode="signal"}))!.generationMode=="signal");
        foreach(var mode in new[]{"reply","scene","signal"}) {
            var p=new Packet {generationMode=mode};var configured=new Config {personaFile="persona.txt",persona="当前角色的队友人设"};
            Check("persona file routes "+mode+" through official API",ChatApi.UsesOfficialPersona(configured,p));
            Check("exact persona included in "+mode+" system prompt",ChatApi.SystemPrompt(configured,p).StartsWith(configured.persona+"\n"));
        }
        Check("legacy local route available without persona file",!ChatApi.UsesOfficialPersona(new Config(),new Packet()));
        Check("ellipsis survives normalization for addon skip",ChatApi.Normalize("…")=="…");
        if(!string.IsNullOrEmpty(config.personaFile)) Check("actual persona file loaded",config.persona.Contains("没有主人与宠物关系"));
        Check("share build uses configured identity",ChatApi.SystemPrompt(new Config{character="测试角色-测试服务器",persona="测试人设"},new Packet{generationMode="scene"}).Contains("测试角色-测试服务器"));
        Check("share task has no fixed player identity",ChatApi.TaskInstruction(new Packet{generationMode="scene"}).Contains("当前角色"));
        Check("own tent cue selects proud showcase instruction",ChatApi.TaskInstruction(new Packet{generationMode="signal",text="我正在展示自己放置的帐篷：测试帐篷"}).Contains("很得意"));
        Check("ordinary tent mention never asserts ownership",!ChatApi.TaskInstruction(new Packet{generationMode="signal",text="注意：测试帐篷"}).Contains("归属已"));
        await WhisperSilenceTests.Run(Check);
        await EventFlavorTests.Run(Check);
        foreach(var channel in new[]{"PARTY","RAID","INSTANCE_CHAT","GUILD","SAY","CHANNEL"}) {
            int calls=0;bool contextual=false;
            var packet=new Packet{channel=channel,generationMode="public",text="大家准备好了吗？",recent=[new("队友","大家准备好了吗？")]};
            Check("public route official persona "+channel,ChatApi.UsesOfficialPersona(new Config(),packet));
            var r=await new ChatApi(new Config(),(_,_)=>{},null,(prompt,_)=>{calls++;contextual=prompt.Contains("无需出现")&&prompt.Contains("仅包含当前频道")&&prompt.Contains("也包括你");return Task.FromResult("哼，等你半天了。");}).Generate(packet);
            Check("public contextual single completion "+channel,calls==1&&contextual&&r.text=="哼，等你半天了。");
            var skip=await new ChatApi(new Config(),(_,_)=>{},null,(_,_)=>Task.FromResult("…")).Generate(packet);
            Check("public unrelated closure allowed silence "+channel,skip.text=="…");
        }

        foreach(string notice in new[]{"【寻找：营地】已完成！","获得【精良护腕】！","【测试任务】已交付！获得【奖励】！"}) {
            int requests=0;
            var fixedReply=await new ChatApi(new Config(),(_,_)=>{},null,(_,_)=>{requests++;throw new Exception("Event template must not call AI");}).Generate(new Packet{generationMode="event",channel="SAY",eventReply=notice});
            Check("fixed native event uses zero AI calls "+notice,requests==0&&fixedReply.text==notice&&fixedReply.provider=="local-event-template");
        }
        Check("automatic whisper uses contextual official persona route",ChatApi.UsesOfficialPersona(new Config(),new Packet{generationMode="whisper"}));
        Check("whisper instruction permits natural closure silence",ChatApi.TaskInstruction(new Packet{generationMode="whisper"}).Contains("没有新问题"));
        Check("whisper instruction distinguishes drafts from actual replies",ChatApi.TaskInstruction(new Packet{generationMode="whisper"}).Contains("自己的历史草稿不等于已发送"));
        Check("whisper instruction scopes context to one recipient",ChatApi.TaskInstruction(new Packet{generationMode="whisper"}).Contains("这一个人"));
        Check("event guard detects exact repeats",EventVariation.NeedsRewrite("接了，这活儿不省心。",["接了，这活儿不省心。"]));
        Check("event guard detects observed task title substitution",EventVariation.NeedsRewrite("野猪人的内战？接了，听着就不是省心的活。",["遗忘之池？接了，听听就不像轻松的活。"]));
        Check("event guard detects punctuation-only changes",EventVariation.NeedsRewrite("可算忙完这阵了！",["可算忙完这阵了。"]));
        Check("event guard accepts natural novel response",!EventVariation.NeedsRewrite("行吧，谁让我闲不住呢。",["遗忘之池？接了，听听就不像轻松的活。"]));
        Check("event rewrite selects less repetitive complete reply",EventVariation.Choose("接了，这活儿不省心。","行吧，谁让我闲不住呢。",["接了，这活儿不省心。"])=="行吧，谁让我闲不住呢。");
        Check("event rewrite never silences an event to evade repetition",EventVariation.Choose("接了，这活儿不省心。","…",["接了，这活儿不省心。"])=="接了，这活儿不省心。");
        Check("event intent comes from explicit field",EventVariation.Kind(new Packet{eventKind="accept",text="任意标题"})=="accept");
        Check("event instruction treats drafts as anti-repeat data",ChatApi.BuildPrompt(new Config(),new Packet{generationMode="event",eventKind="accept"},[],0).Contains("避重参考，不是模仿样本"));
        Check("private prompt is not given event rewrite instruction",!ChatApi.BuildPrompt(new Config(),new Packet{generationMode="whisper"},[],0).Contains("避重参考，不是模仿样本"));
        string repeatFile=Path.Combine(Path.GetTempPath(),"dfy-event-repeat-"+Guid.NewGuid()+".json");
        try {
            var ec=new Config{character="离线测试",requestTimeoutMs=1200};var ep=new Packet{generationMode="event",eventKind="accept",channel="SAY",text="我已接取任务：测试任务"};
            string repeat="测试任务？接了，这活儿不省心。",novel="行吧，谁让我闲不住呢。";
            void Seed(){File.Delete(repeatFile);new VoiceMemory(repeatFile).Add("离线测试\nSAY\n0\n",repeat,0);}
            Seed();int calls=0;bool deadlineSeen=false;
            var er=await new ChatApi(ec,(_,_)=>{},repeatFile,(prompt,ct)=>{deadlineSeen=ct.CanBeCanceled;return Task.FromResult(++calls==1?repeat:novel);}).Generate(ep);
            Check("event repeated API draft rewritten exactly once",calls==2&&er.text==novel&&deadlineSeen);
            Seed();calls=0;er=await new ChatApi(ec,(_,_)=>{},repeatFile,(_,_)=>{calls++;return Task.FromResult(repeat);}).Generate(ep);
            Check("event repeated second draft never triggers third call or silence",calls==2&&er.text==repeat);
            Seed();calls=0;er=await new ChatApi(ec,(_,_)=>{},repeatFile,(_,_)=>{calls++;return Task.FromResult(novel);}).Generate(ep);
            Check("novel event needs only one API call",calls==1&&er.text==novel);
            Seed();calls=0;er=await new ChatApi(ec,(_,_)=>{},repeatFile,(_,_)=>{if(++calls==2)throw new HttpRequestException("offline retry fixture");return Task.FromResult(repeat);}).Generate(ep);
            Check("event rewrite failure preserves complete first response",calls==2&&er.text==repeat);
            Seed();calls=0;using var cancel=new CancellationTokenSource();bool cancelled=false;
            try {await new ChatApi(ec,(_,_)=>{},repeatFile,(_,ct)=>{if(++calls==2){cancel.Cancel();ct.ThrowIfCancellationRequested();}return Task.FromResult(repeat);}).Generate(ep,cancel.Token);}catch(OperationCanceledException){cancelled=true;}
            Check("explicit cancellation cannot return and send old event draft",cancelled&&calls==2);
        } finally {File.Delete(repeatFile);}
        Check("BN draft memory isolates reconnect sessions with potentially reused account IDs",ChatApi.MemoryScope(new Config(),new Packet{channel="BN_WHISPER",target="401",session="one"})!=ChatApi.MemoryScope(new Config(),new Packet{channel="BN_WHISPER",target="401",session="two"}));
        Check("BN draft memory isolates account IDs in same session",ChatApi.MemoryScope(new Config(),new Packet{channel="BN_WHISPER",target="401",session="one"})!=ChatApi.MemoryScope(new Config(),new Packet{channel="BN_WHISPER",target="402",session="one"}));
        var structuralHistory=new[]{"行吧，今天总算让我赶上热闹。"};
        string structuralFirst="行吧，背包快被杂物挤爆了。",structuralSecond="哼，这热闹正合我意。";
        Check("structural rule detects repeated opening despite low character score",EventVariation.NeedsRewrite(structuralFirst,structuralHistory)&&EventVariation.Score(structuralFirst,structuralHistory)<.68);
        Check("rewrite selection honors structural rule not only character similarity",EventVariation.Choose(structuralFirst,structuralSecond,structuralHistory)==structuralSecond);
        Check("event instructions forbid inventing reward comparison and unseen journey",ChatApi.TaskInstruction(new Packet{generationMode="event"}).Contains("只知道接取就不编造跑腿过程")&&ChatApi.TaskInstruction(new Packet{generationMode="event"}).Contains("未提供时不判断"));
        var visiblePacket=PixelCodec.Encode("{\"session\":\"occlusion-test\"}");
        using(var surface=PixelCodec.Render(visiblePacket)) {
            Check("bridge image decodes before cover",PixelCodec.Decode(surface)!=null);
            using(var graphics=System.Drawing.Graphics.FromImage(surface))graphics.FillRectangle(System.Drawing.Brushes.Black,0,0,64,64);
            Check("window-covered bridge cannot decode or become an input command",PixelCodec.Decode(surface)==null);
        }
        using(var visibleAgain=PixelCodec.Render(visiblePacket))Check("bridge decodes again after cover removed without reconnect",PixelCodec.Decode(visibleAgain)!=null);
        VoiceMemoryTests.Run(Check);
        Check("event uses proactive fact-grounded instruction",ChatApi.TaskInstruction(new Packet{generationMode="event"}).Contains("已发生的游戏事件"));
        Check("event always uses official persona route",ChatApi.UsesOfficialPersona(new Config(),new Packet{generationMode="event"}));
        Check("active delivery polls at 50ms without idle gate",BridgeTiming.PollInterval(150,true)==50);
        Check("idle polling remains configured",BridgeTiming.PollInterval(150,false)==150);
        Check("ACK timeout budget preserved",BridgeTiming.AckPollMs*BridgeTiming.AckPollCount==3200);
        Check("one unmodified native stroke has no held tail",Native.ReceiverStrokePlan(119,0).SequenceEqual(new[]{((ushort)119,false),((ushort)119,true)}));
        Check("signal target typo repaired without new request",ChatApi.NormalizeReply(new Packet{generationMode="signal",text="我刚发出的信号：攻击：邪鳍攻击者"},"邪鳄攻击者，先打这家伙")=="邪鳍攻击者，先打这家伙");
        Check("ordinary reply never gets signal target repair",ChatApi.NormalizeReply(new Packet{generationMode="reply",text="攻击：邪鳍攻击者"},"邪鳄攻击者，先打这家伙")=="邪鳄攻击者，先打这家伙");
        FlowTests.Run(Check);
        FontAssetTests.Run(Check,root);
        NativeGlyphTests.Run(Check);
        InputPolicyTests.Run(Check,root);
        await BridgeTests.Run(Check);
        ConnectionGateTests.Run(Check);
        var wire=BridgeEnvelope.Create("12345",1,"ping 12345 on 12 30");
        File.WriteAllText(Path.Combine(root,"verification","bridge-envelope.json"),JsonSerializer.Serialize(new{wire.text,wire.checksum}));
        string json = JsonSerializer.Serialize(new Packet { session = "12345", player = config.character, status = "GENERATING", text = "大肥鱼，今天打本吗？", recent = [new("甲", "你好"), new("乙", "鲸鱼")], requestId = 1 });
        var bytes = PixelCodec.Encode(json); using var bitmap = PixelCodec.Render(bytes);
        Check("pixel UTF-8 round trip", PixelCodec.Decode(bitmap) == json);
        using (var bright = new Bitmap(bitmap)) {
            for(int y=0;y<bright.Height;y++) for(int x=0;x<bright.Width;x++) { var color=bright.GetPixel(x,y); bright.SetPixel(x,y,Color.FromArgb(Math.Min(255,(int)Math.Round(color.R*1.66)),Math.Min(255,(int)Math.Round(color.G*1.66)),Math.Min(255,(int)Math.Round(color.B*1.66)))); }
            Check("observed 1.66x UI brightness is calibrated",PixelCodec.Decode(bright)==json);
            bright.Save(Path.Combine(root,"verification","brightness-fixture.png"));
        }
        using (var nonlinear = new Bitmap(bitmap)) {
            int Curve(int v,double gain) => (int)Math.Min(255,Math.Round(255*Math.Pow(v/255.0,.85)*gain));
            for(int y=0;y<nonlinear.Height;y++) for(int x=0;x<nonlinear.Width;x++) { var color=nonlinear.GetPixel(x,y); nonlinear.SetPixel(x,y,Color.FromArgb(Curve(color.R,1.3),Curve(color.G,1.2),Curve(color.B,1.1))); }
            Check("per-channel nonlinear color curves calibrated",PixelCodec.Decode(nonlinear)==json);
        }
        bitmap.SetPixel(11, 1, Color.HotPink); Check("corruption rejected", PixelCodec.Decode(bitmap) == null);
        string luaFixture = Path.Combine(root, "verification", "lua-packet.bin");
        if (File.Exists(luaFixture)) { using var luaBitmap = PixelCodec.Render(File.ReadAllBytes(luaFixture)); var luaJson = PixelCodec.Decode(luaBitmap); Check("actual Lua packet decodes in desktop", luaJson != null && JsonSerializer.Deserialize<Packet>(luaJson)!.recent.Length == 8); }
        Check("48 Unicode codepoints preserved",ChatApi.Normalize(new string('鲸',48))==new string('鲸',48));
        Check("complete first sentence wins over cut second",ChatApi.Normalize("这句话完整。"+new string('鲸',50))=="这句话完整。");
        Check("long clause ends at safe punctuation",ChatApi.Normalize(new string('鲸',35)+"，"+new string('鲸',20))==new string('鲸',35)+"。");
        bool overlong=false;try{ChatApi.Normalize(new string('鲸',60));}catch(InvalidDataException){overlong=true;}Check("no silent midword truncation for unbroken overflow",overlong);
        Check("at most two sentences",ChatApi.Normalize("来了。知道啦。走吧。")=="来了。知道啦。");
        Check("recent fish imagery changes guidance",VoiceMemory.FishHint(new[]{"鱼干算你的","来啦"}).Contains("这句用普通口语"));
        Check("old fish imagery falls outside three drafts",!VoiceMemory.FishHint(new[]{"鱼干","甲","乙","丙"}).Contains("这句用普通口语"));
        Check("soft seed and no forced rewrite",ChatApi.BuildPrompt(config,new Packet(),[],0).Contains("不必为每句换句式"));
        Check("old addon cannot silently truncate new long reply",!DeliveryRecovery.FitsReply(new Packet(),new Reply(new string('鲸',39),0,0,"test")));
        foreach(var channel in new[]{"WHISPER","BN_WHISPER","SAY","YELL","PARTY","RAID","GUILD","OFFICER","INSTANCE_CHAT","CHANNEL"}) {
            var prefixed=new Packet{status="READY",channel=channel,replyPrefix="【大肥鱼】",reply="【大肥鱼】在呢。"};
            Check("prefixed READY is observed "+channel,DeliveryRecovery.ReplyObserved(prefixed,new Reply("在呢。",0,0,"test")));
            Check("prefix already in model body remains idempotent "+channel,DeliveryRecovery.ReplyObserved(prefixed,new Reply("【大肥鱼】在呢。",0,0,"test")));
            prefixed.reply="【大肥鱼】错误内容";Check("prefix cannot mask mismatched content "+channel,!DeliveryRecovery.ReplyObserved(prefixed,new Reply("在呢。",0,0,"test")));
        }
        Check("public prefix is observed without retransmission",DeliveryRecovery.ReplyObserved(new Packet{status="READY",channel="SAY",replyPrefix="【大肥鱼】",reply="【大肥鱼】在呢。"},new Reply("在呢。",0,0,"test")));
        Check("older unprefixed addon remains compatible",DeliveryRecovery.ReplyObserved(new Packet{status="READY",channel="WHISPER",reply="在呢。"},new Reply("在呢。",0,0,"test")));
        Check("updated addon accepts full48",DeliveryRecovery.FitsReply(new Packet{replyMaxChars=48},new Reply(new string('鲸',48),0,0,"test")));
        string emoji48=string.Concat(Enumerable.Repeat("🐳",48));Check("astral runes intact",ChatApi.Normalize(emoji48)==emoji48);
        var largeWire=BridgeEnvelope.Create("17944500381789",2147483647,"rx 17944500381789 2147483647 "+Convert.ToBase64String(Encoding.UTF8.GetBytes(emoji48)));Check("48 astral reply fits existing addon envelope",largeWire.text.Length<=480);
        File.WriteAllText(Path.Combine(root,"verification","long-reply-envelope.json"),JsonSerializer.Serialize(new{text=largeWire.text,reply=emoji48}));
        Check("prefix markdown quotes removed", ChatApi.Normalize("大肥鱼：\"**哼，等我一下。**\"") == "哼，等我一下。");
        Check("max two sentences", ChatApi.Normalize("一。二。三。") == "一。二。");
        bool reject = false; try { ChatApi.Normalize("我是AI助手"); } catch (InvalidDataException) { reject = true; } Check("AI self-identification rejected", reject);
        using (var image = PixelCodec.Render(PixelCodec.Encode(json))) { Directory.CreateDirectory(Path.Combine(root, "verification")); image.Save(Path.Combine(root, "verification", "protocol-fixture.png")); }
        // An actual HTTP exchange with a local deterministic endpoint, not a generated fake API result.
        var tcp = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0); tcp.Start(); int port = ((IPEndPoint)tcp.LocalEndpoint).Port; tcp.Stop();
        using var listener = new HttpListener(); listener.Prefixes.Add($"http://127.0.0.1:{port}/"); listener.Start();
        var server = Task.Run(async () => {
            var ctx = await listener.GetContextAsync(); using var sr = new StreamReader(ctx.Request.InputStream); string body = await sr.ReadToEndAsync();
            using var doc = JsonDocument.Parse(body); Check("HTTP recent 8 preserved", doc.RootElement.GetProperty("recent").GetArrayLength() == 8);
            Check("HTTP whisper mapping", doc.RootElement.GetProperty("channel").GetString() == "whisper");
            var data = Encoding.UTF8.GetBytes("{\"ok\":true,\"reply\":\"大肥鱼：哼，才不是特意等你的。\",\"delayMs\":1200}"); ctx.Response.ContentType = "application/json"; ctx.Response.ContentLength64 = data.Length; await ctx.Response.OutputStream.WriteAsync(data); ctx.Response.Close();
        });
        var mock = new Config { apiUrl = $"http://127.0.0.1:{port}/api/game/chat", allowFallback = false };
        var reply = await new ChatApi(mock, (_, _) => { }).Generate(new Packet { channel = "WHISPER", recent = Enumerable.Range(0, 10).Select(i => new ChatLine("测试", "消息" + i)).ToArray() }); await server;
        Check("HTTP reply normalized", reply.text == "哼，才不是特意等你的。");
        Check("HTTP delay retained", reply.delayMs == 1200);
        File.WriteAllText(Path.Combine(root, "verification", "desktop-test.json"), JsonSerializer.Serialize(new { passed = checks.Count, checks }, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }
}
