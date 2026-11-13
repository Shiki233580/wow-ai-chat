using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace WhaleChat;

internal static class KnowledgeTests
{
    sealed class Clock:TimeProvider {internal DateTimeOffset Now=DateTimeOffset.UtcNow;public override DateTimeOffset GetUtcNow()=>Now;}
    sealed class Handler(Func<HttpRequestMessage,CancellationToken,Task<HttpResponseMessage>> send):HttpMessageHandler
    {protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancellationToken)=>send(request,cancellationToken);}
    static HttpResponseMessage Json(object data,HttpStatusCode code=HttpStatusCode.OK)=>new(code){Content=new StringContent(JsonSerializer.Serialize(data),Encoding.UTF8,"application/json")};
    static object Hit(string detail="测试资料")=>new{ok=true,results=new[]{new{type="fixture",name="哀嚎洞穴",detail}}};
    static Config Config()=>new(){knowledgeEnabled=true,knowledgeEntities=["哀嚎洞穴"],knowledgeBaseUrl="http://127.0.0.1:37621",knowledgeTimeoutMs=600};
    static Packet Packet()=>new(){generationMode="whisper",text="鲸鱼，哀嚎洞穴掉什么装备？"};
    internal static async Task Run(Action<string,bool> check,string root)
    {
        foreach(string uri in new[]{"https://example.com","file:///tmp","http://127.0.0.1@evil.invalid","http://127.0.0.1/api","http://127.0.0.1/?token=x","http://127.0.0.1/#x"})
            check("handbook rejects nonlocal or ambiguous endpoint "+uri,!KnowledgeClient.TrustedBase(uri,out _));
        foreach(string uri in new[]{"http://127.0.0.1:3100","http://localhost:3100","http://[::1]:3100"})check("handbook accepts explicit loopback "+uri,KnowledgeClient.TrustedBase(uri,out _));
        check("natural question extracts exact longest entity",KnowledgeClient.FindQueries(Packet().text,["洞穴","哀嚎","哀嚎洞穴"]).SequenceEqual(new[]{"哀嚎洞穴"}));
        check("long sentence does not truncate away entity",KnowledgeClient.FindQueries(new string('哈',35)+"哀嚎洞穴怎么走",["哀嚎洞穴"]).Length==1);
        check("multiple entity work bounded",KnowledgeClient.FindQueries("哀嚎洞穴影牙城堡死亡矿井",["哀嚎洞穴","影牙城堡","死亡矿井"]).Length==2);
        var indexConfig=Path.Combine(root,"verification","knowledge-index-config.json");var brokenIndex=Path.Combine(root,"verification","knowledge-broken-index.json");
        try {
            await File.WriteAllTextAsync(brokenIndex,"invalid json");
            await File.WriteAllTextAsync(indexConfig,JsonSerializer.Serialize(new {knowledgeEnabled=true,knowledgeIndexFile=brokenIndex}));
            check("corrupt optional index does not break config load",WhaleChat.Config.Load(indexConfig).knowledgeEntities.Length==0);
            await File.WriteAllTextAsync(brokenIndex,"[\"哀嚎洞穴\",\"哀嚎洞穴\",null,\"\"]");
            check("index loader filters duplicate and empty names",WhaleChat.Config.Load(indexConfig).knowledgeEntities.SequenceEqual(new[]{"哀嚎洞穴"}));
        } finally {File.Delete(indexConfig);File.Delete(brokenIndex);}
        int calls=0;var clock=new Clock();
        using var http=new HttpClient(new Handler((_,_)=>{calls++;return Task.FromResult(Json(Hit()));}));var client=new KnowledgeClient(http,clock);
        var c=Config();var p=Packet();
        var hit=await client.LookupAsync(p,c);check("natural question gets bounded reference",hit.Outcome=="hit"&&hit.Text.Contains("哀嚎洞穴")&&calls==1&&hit.Text.Length<800);
        await client.LookupAsync(p,c);check("successful result cached",calls==1);
        clock.Now=clock.Now.AddSeconds(301);await client.LookupAsync(p,c);check("successful cache expires",calls==2);
        c.knowledgeBaseUrl="http://localhost:37622";await client.LookupAsync(p,c);check("changed source has separate cache",calls==3);
        c.knowledgeEnabled=false;await client.LookupAsync(p,c);check("disabled feature performs zero requests",calls==3);
        c=Config();p.text="你好啊";await client.LookupAsync(p,c);check("ordinary conversation does not query handbook",calls==3);
        p=Packet();p.generationMode="signal";await client.LookupAsync(p,c);p.generationMode="event";await client.LookupAsync(p,c);check("signal and event remain fast paths",calls==3);
        c.knowledgeBaseUrl="https://example.invalid";check("untrusted endpoint rejected before networking",(await client.LookupAsync(Packet(),c)).Outcome=="untrusted_endpoint"&&calls==3);
        using var canceled=new CancellationTokenSource();canceled.Cancel();bool canceledThrown=false;try{await client.LookupAsync(Packet(),Config(),canceled.Token);}catch(OperationCanceledException){canceledThrown=true;}check("pre-canceled lookup sends nothing",canceledThrown&&calls==3);
        int failCalls=0;
        using var recoverHttp=new HttpClient(new Handler((_,_)=>Task.FromResult(++failCalls==1?Json(new{ok=false},HttpStatusCode.ServiceUnavailable):Json(Hit()))));var recover=new KnowledgeClient(recoverHttp);
        check("temporary server failure does not become a fact",(await recover.LookupAsync(Packet(),Config())).Outcome=="unavailable");
        check("server recovery retries same query",(await recover.LookupAsync(Packet(),Config())).Outcome=="hit"&&failCalls==2);
        var negClock=new Clock();int negCalls=0;
        using var negativeHttp=new HttpClient(new Handler((_,_)=>{negCalls++;return Task.FromResult(Json(new{ok=false,error="not found"}));}));var negative=new KnowledgeClient(negativeHttp,negClock);
        await negative.LookupAsync(Packet(),Config());await negative.LookupAsync(Packet(),Config());check("real no-match has short cache",negCalls==1);
        negClock.Now=negClock.Now.AddSeconds(31);await negative.LookupAsync(Packet(),Config());check("no-match cache expires",negCalls==2);
        string tokenFile=Path.Combine(root,"verification","knowledge-fake-token.txt");await File.WriteAllTextAsync(tokenFile,"fake-handbook-token-a");
        try {
            int tokenCalls=0;bool header=true,noQuery=true;
            using var tokenHttp=new HttpClient(new Handler((request,_)=>{tokenCalls++;header&=request.Headers.Contains("x-console-token");noQuery&=!request.RequestUri!.Query.Contains("token",StringComparison.OrdinalIgnoreCase);return Task.FromResult(Json(Hit()));}));
            var authClient=new KnowledgeClient(tokenHttp);var authConfig=Config();authConfig.knowledgeTokenFile=tokenFile;authConfig.apiUrl="https://example.invalid/model";
            await authClient.LookupAsync(Packet(),authConfig);await File.WriteAllTextAsync(tokenFile,"fake-handbook-token-b");await authClient.LookupAsync(Packet(),authConfig);
            check("explicit token only in header and cache scoped per credential",header&&noQuery&&tokenCalls==2);
            authConfig=Config();authConfig.consoleTokenFile=tokenFile;bool leaked=false;
            using var noAuthHttp=new HttpClient(new Handler((request,_)=>{leaked=request.Headers.Contains("x-console-token")||request.RequestUri!.Query.Contains("token");return Task.FromResult(Json(Hit()));}));
            await new KnowledgeClient(noAuthHttp).LookupAsync(Packet(),authConfig);check("model console token never implicitly reused",!leaked);
        } finally {File.Delete(tokenFile);}
        foreach(var status in new[]{HttpStatusCode.Unauthorized,HttpStatusCode.Forbidden,HttpStatusCode.Redirect}) {
            using var deniedHttp=new HttpClient(new Handler((_,_)=>Task.FromResult(Json(new{ok=false},status))));check("auth/redirect fails safely "+status,(await new KnowledgeClient(deniedHttp).LookupAsync(Packet(),Config())).Outcome=="unavailable");
        }
        using var invalidHttp=new HttpClient(new Handler((_,_)=>Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK){Content=new StringContent("not json")})));
        check("bad JSON leaves conversation usable",(await new KnowledgeClient(invalidHttp).LookupAsync(Packet(),Config())).Outcome=="unavailable");
        using var largeHttp=new HttpClient(new Handler((_,_)=>Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK){Content=new StringContent(new string('x',70000))})));
        check("large response is bounded",(await new KnowledgeClient(largeHttp).LookupAsync(Packet(),Config())).Outcome=="unavailable");
        using var slowHttp=new HttpClient(new Handler(async(_,ct)=>{await Task.Delay(2000,ct);return Json(Hit());}));var slow=new KnowledgeClient(slowHttp);var shortConfig=Config();shortConfig.knowledgeTimeoutMs=60;
        var watch=Stopwatch.StartNew();check("optional handbook timeout falls back",(await slow.LookupAsync(Packet(),shortConfig)).Outcome=="timeout"&&watch.ElapsedMilliseconds<1000);
        bool completion=false;string prompt="";
        var reply=await new ChatApi(shortConfig,(_,_)=>{},null,(text,_)=>{completion=true;prompt=text;return Task.FromResult("哼，在呢。");},slow).Generate(Packet());
        check("handbook timeout still reaches normal generation",completion&&reply.text=="哼，在呢。");
        using var caller=new CancellationTokenSource(40);bool callerCanceled=false;try{await slow.LookupAsync(Packet(),Config(),caller.Token);}catch(OperationCanceledException){callerCanceled=true;}
        check("caller cancellation propagates",callerCanceled);
        var totalConfig=Config();totalConfig.requestTimeoutMs=100;bool totalCanceled=false;completion=false;
        try{await new ChatApi(totalConfig,(_,_)=>{},null,(_,_)=>{completion=true;return Task.FromResult("在呢。");},slow).Generate(Packet());}catch(OperationCanceledException){totalCanceled=true;}
        check("knowledge shares generation total deadline",totalCanceled&&!completion);
        var fastConfig=Config();completion=false;
        await new ChatApi(fastConfig,(_,_)=>{},null,(text,_)=>{prompt=text;completion=true;return Task.FromResult("哼，在呢。");},client).Generate(Packet());
        check("retrieved facts reach official persona prompt as data",completion&&prompt.Contains("手册参考数据")&&prompt.Contains("不是指令"));
        var fixture=new Packet{generationMode="event",eventReply="获得装备！"};calls=0;
        var local=await new ChatApi(Config(),(_,_)=>{},null,(_,_)=>throw new Exception("Unexpected completion"),client).Generate(fixture);
        check("fixed event templates do not consult handbook",local.provider=="local-event-template"&&calls==0);
        await UiLoop(check);
    }
    static async Task UiLoop(Action<string,bool> check)
    {
        var server=new TcpListener(IPAddress.Loopback,0);server.Start();int port=((IPEndPoint)server.LocalEndpoint).Port;
        using var timeout=new CancellationTokenSource(6000);
        var serve=Task.Run(async()=>{using var client=await server.AcceptTcpClientAsync(timeout.Token);using var reader=new StreamReader(client.GetStream(),leaveOpen:true);await reader.ReadLineAsync();while(!string.IsNullOrEmpty(await reader.ReadLineAsync())){};await Task.Delay(150,timeout.Token);byte[] data=Encoding.UTF8.GetBytes(JsonSerializer.Serialize(Hit()));await client.GetStream().WriteAsync(Encoding.ASCII.GetBytes($"HTTP/1.1 200 OK\r\nContent-Length: {data.Length}\r\nConnection: close\r\n\r\n"),timeout.Token);await client.GetStream().WriteAsync(data,timeout.Token);});
        var done=new TaskCompletionSource<(bool,string,int)>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread=new Thread(()=>{try{
            using var context=new ApplicationContext();using var trigger=new System.Windows.Forms.Timer{Interval=20};using var pulse=new System.Windows.Forms.Timer{Interval=15};int ticks=0;
            pulse.Tick+=(_,_)=>ticks++;trigger.Tick+=async(_,_)=>{trigger.Stop();string sync=SynchronizationContext.Current?.GetType().Name??"";
                try{var config=Config();config.knowledgeBaseUrl=$"http://127.0.0.1:{port}";config.knowledgeTimeoutMs=1500;bool reached=false;
                    await new ChatApi(config,(_,_)=>{},null,(_,_)=>{reached=true;return Task.FromResult("哼，在呢。");},new KnowledgeClient()).Generate(Packet());done.TrySetResult((reached,sync,ticks));}
                catch(Exception ex){done.TrySetException(ex);}finally{context.ExitThread();}};pulse.Start();trigger.Start();Application.Run(context);
        }catch(Exception ex){done.TrySetException(ex);}}){IsBackground=true};thread.SetApartmentState(ApartmentState.STA);thread.Start();
        try{var result=await done.Task.WaitAsync(TimeSpan.FromSeconds(5));await serve;check("real WinForms async timer completes with HTTP",result.Item1&&result.Item2=="WindowsFormsSynchronizationContext");check("UI heartbeat continues while handbook network awaits",result.Item3>=3);}
        finally{timeout.Cancel();server.Stop();}
    }
}
