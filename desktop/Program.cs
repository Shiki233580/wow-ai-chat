using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace WhaleChat;

internal static class Program
{
    internal static string Root = AppContext.BaseDirectory;
    static readonly object LogLock = new();
    internal static void Log(string type, object data)
    {
        lock (LogLock)
        {
            Directory.CreateDirectory(Path.Combine(Root, "logs"));
            File.AppendAllText(Path.Combine(Root, "logs", "app-" + DateTime.Now.ToString("yyyy-MM-dd") + ".log"), JsonSerializer.Serialize(new { time = DateTimeOffset.Now, type, data }) + Environment.NewLine, Encoding.UTF8);
        }
    }
    [STAThread]
    static int Main(string[] args)
    {
#if DFY_PREVIEW
        // Preview builds must never start the live tray, probe the game or inject input.
        if (!args.Contains("--self-test")) {
            Console.Error.WriteLine("Isolated preview: only --self-test is permitted. Online1.18.20 is untouched.");
            return 64;
        }
#endif
        ApplicationConfiguration.Initialize();
        int rootIndex = Array.IndexOf(args, "--root"); if (rootIndex >= 0 && rootIndex + 1 < args.Length) Root = Path.GetFullPath(args[rootIndex + 1]);
#if DFY_PREVIEW
        if (!File.Exists(Path.Combine(Root,"DEVELOPMENT.md"))) {
            Console.Error.WriteLine("Preview tests require their isolated development root; no files written.");
            return 64;
        }
#endif
        try
        {
            var config = Config.Load(Path.Combine(Root, "config.json"));
            if (args.Contains("--self-test")) return Tests.Run(Root, config).GetAwaiter().GetResult();
            int jobIndex=Array.IndexOf(args,"--job-test");
            if(jobIndex>=0) {
                if(jobIndex+1>=args.Length) throw new InvalidDataException("--job-test requires a JSON fixture path");
                var packet=JsonSerializer.Deserialize<Packet>(File.ReadAllText(args[jobIndex+1]))??throw new InvalidDataException("Invalid fixture");
                var reply=new ChatApi(config,Log,Path.Combine(Root,"reply-memory.json")).Generate(packet).GetAwaiter().GetResult();
                Directory.CreateDirectory(Path.Combine(Root,"verification"));File.WriteAllText(Path.Combine(Root,"verification","job-test.json"),JsonSerializer.Serialize(reply));return 0;
            }
            if (args.Contains("--api-test"))
            {
                var p = new Packet { session = "test", requestId = 1, channel = "WHISPER", speaker = "本地验收", text = "鲸鱼，今天一起打本吗？", recent = [new("本地验收", "鲸鱼，今天一起打本吗？")] };
                var result = new ChatApi(config, Log).Generate(p).GetAwaiter().GetResult();
                Directory.CreateDirectory(Path.Combine(Root, "verification")); File.WriteAllText(Path.Combine(Root, "verification", "api-test.json"), JsonSerializer.Serialize(result)); return 0;
            }
            if (args.Contains("--bridge-smoke")) {using var guard=new NativeInputGuard();Native.InputGuard=guard;return BridgeSmoke.Run(config,Root).GetAwaiter().GetResult();}
            if (args.Contains("--probe"))
            {
                Directory.CreateDirectory(Path.Combine(Root, "verification"));
                var p = Native.Read(config, Path.Combine(Root, "verification", "probe-pixels.png"));
                File.WriteAllText(Path.Combine(Root, "verification", "probe.json"), JsonSerializer.Serialize(new { foregroundIsGame = Native.IsGame(Native.GetForegroundWindow(), config), decoded = p != null, diagnostic=Native.LastReadDiagnostic, decodedPlayer=Native.LastDecodedPlayer, packet = p?.packet })); return p == null ? 2 : 0;
            }
            using var mutex = new Mutex(true, "Local\\WhaleChat-DFY-" + Environment.UserName, out bool created);
            if (!created) return 0;
            Application.Run(new TrayContext(config)); return 0;
        }
        catch (Exception ex) { Log("fatal", new { error = ex.GetType().Name, ex.Message }); if (args.Length == 0) MessageBox.Show(ex.Message, "大肥鱼助手启动失败"); return 1; }
    }
}

internal sealed class TrayContext : ApplicationContext
{
    readonly NativeInputGuard inputGuard;
    readonly Config c;
    readonly NotifyIcon tray;
    readonly System.Windows.Forms.Timer timer = new();
    readonly ChatApi api;
    readonly HashSet<string> seen;
    readonly string seenPath;
    readonly ToolStripMenuItem pause;
    bool busy, generateRequested, shutdown, deliveryWaiting;
    string waitReason="", lastReadState="", lastWhisperState="";
    readonly ConnectionGate connection = new();
    readonly BridgeSessionReadiness sessionReady = new();
    string session = "", lastStatus = "", keywordsSession = "";
    DateTime nextPing = DateTime.MinValue;
    Job? job;
    sealed class Job(string key, Reply? reply, DateTime created)
    {
        internal string Key = key;
        internal Reply? Reply = reply;
        internal DateTime Created = created, ReceivedAt; // Created is API completion; pending packet carries game-side request age.
        internal bool Delivered, Committed;
    }
    internal TrayContext(Config config)
    {
        inputGuard=new NativeInputGuard();Native.InputGuard=inputGuard;
        c = config; api = new ChatApi(c, Program.Log, Path.Combine(Program.Root,"reply-memory.json"));
        seenPath = Path.Combine(Program.Root, "seen-requests.json");
        seen = File.Exists(seenPath) ? JsonSerializer.Deserialize<HashSet<string>>(File.ReadAllText(seenPath)) ?? [] : [];
        tray = new NotifyIcon { Icon = SystemIcons.Information, Text = "篝火大肥鱼 · 等待游戏", Visible = true };
        var menu = new ContextMenuStrip();
        pause = new ToolStripMenuItem(c.paused ? "恢复" : "暂停");
        pause.Click += (_, _) => { c.paused = !c.paused; connection.ClearFault(); job=null; generateRequested=false; pause.Text = c.paused ? "恢复" : "暂停"; nextPing = DateTime.MinValue; File.WriteAllText(Path.Combine(Program.Root, "config.json"), JsonSerializer.Serialize(c, new JsonSerializerOptions { WriteIndented = true })); Program.Log("pause", new { c.paused }); };
        menu.Items.Add(pause);
        menu.Items.Add("生成", null, (_, _) => generateRequested = true);
        menu.Items.Add("打开日志", null, (_, _) => Process.Start(new ProcessStartInfo(Path.Combine(Program.Root, "logs")) { UseShellExecute = true }));
        menu.Items.Add("退出", null, (_, _) => { shutdown = true; ExitThread(); });
        tray.ContextMenuStrip = menu;
        // No user-facing/global shortcut; generate via existing buttons only.
        timer.Interval = c.pollMs; timer.Tick += async (_, _) => await Tick(); timer.Start();
        Program.Log("startup", new { c.character, hotkeyRegistered=false, keyboardTransport="unmodified_only", inputGuard=true, c.paused });
    }
    async Task<bool> Command(Packet p, string text, bool matchRequest = false)
    {
        try {
            bool ok = await Native.Command(c, p.session, text, ()=>!c.paused&&!shutdown&&!connection.Faulted, matchRequest ? p.requestId : null);
            if (ok) Program.Log("bridge_acknowledged", new { p.Key, command = text.Split(' ')[0] });
            return ok;
        } catch(BridgeAttemptException ex) {
            Program.Log("bridge_interrupted",new{p.Key,command=ex.Kind,ex.ExecutionStarted,ex.CanRetry,ex.Message,recovery="automatic_when_keys_released"});
            if(!ex.CanRetry) { Program.Log("command_uncertain_no_retry",new{p.Key,command=ex.Kind}); return true; }
            // Preserve the cached API reply and job identity; retry only when the normal safety checks permit it.
            connection.Fail(ex.Message);return false;
        }
    }
    void ObserveWait(Packet? p,string reason)
    {
        if(job==null||job.Reply==null||job.Delivered||(p!=null&&p.Key!=job.Key))return;
        string next=job.Key+":"+reason;
        if(next==waitReason)return;
        waitReason=next;
        Program.Log("delivery_wait",new{Key=job.Key,reason,replyReadyMs=(int)(DateTime.UtcNow-job.Created).TotalMilliseconds});
    }
    async Task Deliver(Packet p)
    {
        if(job==null || job.Key!=p.Key)return;
        if(DeliveryRecovery.ReplyObserved(p,job.Reply)) {job.Delivered=true;job.ReceivedAt=DateTime.UtcNow;}
        if(p.submitted||p.confirmed)job.Committed=true;
        if(DateTime.UtcNow-job.Created>TimeSpan.FromSeconds(40)) {Program.Log("job_expired",new{p.Key});job=null;return;}
        if(p.status=="GENERATING"&&!job.Delivered) {
            if(job.Reply==null){job.Delivered=await Command(p,$"fail {p.session} {p.requestId}",true);return;}
            if(!DeliveryRecovery.FitsReply(p,job.Reply)){ObserveWait(p,"addon_reply_limit_requires_reload");tray.Text="大肥鱼 · 请 /reload 加载48字版本";return;}
            string b64=Convert.ToBase64String(Encoding.UTF8.GetBytes(job.Reply.text));
            if(await Command(p,$"rx {p.session} {p.requestId} {b64}",true)){job.Delivered=true;job.ReceivedAt=DateTime.UtcNow;Program.Log("reply_delivered",new{p.Key,apiMs=job.Reply.elapsedMs,returnWaitMs=(int)(job.ReceivedAt-job.Created).TotalMilliseconds});waitReason="";}
        } else if(p.status=="READY"&&p.automatic&&p.auto&&!p.submitted&&job.Delivered&&!job.Committed&&job.Reply!=null) {
            job.Committed=await Command(p,$"commit {p.session} {p.requestId}",true);
            if(job.Committed)Program.Log("send_requested",new{p.Key,p.channel,p.target,p.channelNumber});
        }
    }
    async Task Tick()
    {
        if (busy || shutdown) return;
        busy = true;
        try
        {
            var read = Native.Read(c);
            string readState=Native.LastReadDiagnostic+":"+(Native.LastDecodedPlayer??"");
            if(readState!=lastReadState){lastReadState=readState;Program.Log("connection_diagnostic",new{reason=Native.LastReadDiagnostic,player=Native.LastDecodedPlayer,paused=c.paused});}
            if (read == null) { ObserveWait(null,Native.LastReadDiagnostic); tray.Text = Native.LastReadDiagnostic=="character_mismatch" ? "大肥鱼 · 角色不匹配" : "大肥鱼 · 等待游戏前台/像素桥"; return; }
            var p = read.Value.packet;
            if(p.professionBusy){deliveryWaiting=false;ObserveWait(p,"profession_window_open");tray.Text="大肥鱼 · 制作期间不生成、不回传";return;}
            deliveryWaiting=p.status=="GENERATING" || (p.status=="READY" && p.automatic && p.auto && !p.submitted);
            // Read-only observation continues while paused; ONLY a new panel click may resume.
            if(!BridgeInputPolicy.Supported(p)){tray.Text=c.paused?"大肥鱼 · 已手动暂停":"大肥鱼 · 请更新插件并 /reload";return;}
            if(!sessionReady.Ready(p.session,Environment.TickCount64)){tray.Text="大肥鱼 · 等待重载后的会话稳定";return;}
            if(connection.ObserveReconnect(p.session,p.reconnectNonce)) {
                bool wasPaused=c.paused;c.paused=false;connection.ClearFault();pause.Text="暂停";
                job=null;generateRequested=false;nextPing=DateTime.MinValue;keywordsSession="";
                if(wasPaused)File.WriteAllText(Path.Combine(Program.Root,"config.json"),JsonSerializer.Serialize(c,new JsonSerializerOptions{WriteIndented=true}));
                Program.Log("panel_reconnect",new{p.session,p.reconnectNonce,wasPaused});
            }
            if(c.paused){tray.Text="大肥鱼 · 已手动暂停；在托盘选择恢复";return;}
            if(connection.RecoverAutomatically(p.bindingsReady,true,Native.CanUseBridge(p),p.typing,c.paused)) Program.Log("bridge_auto_recovered",new{p.Key});
            if (p.session != session) { session = p.session; nextPing = DateTime.MinValue; job = null; }
            if(job!=null && job.Key!=p.Key) { Program.Log("job_obsolete",new{job.Key,current=p.Key});job=null;waitReason=""; }
            string state = p.Key + ":" + p.status + ":" + p.submitted + ":" + p.confirmed + ":" + p.detail;
            if (state != lastStatus) { lastStatus = state; Program.Log("game_state", new { p.Key, p.status, p.submitted, p.confirmed, p.detail, p.channel, p.target, p.channelNumber }); }
            string whisperState=$"{p.session}:{p.whisperAuto}:{p.whisperQueued}:{p.whisperReceivedBN}:{p.sendUnconfirmed}:{p.whisperDiagnostic}";
            if(whisperState!=lastWhisperState){lastWhisperState=whisperState;Program.Log("whisper_state",new{p.whisperAuto,p.whisperQueued,p.whisperReceivedBN,p.sendUnconfirmed,p.whisperDiagnostic});}
            tray.Text = "大肥鱼 · " + (c.paused ? "已暂停" : p.status);
            if (p.status == "GENERATING" && !seen.Contains(p.Key))
            {
                seen.Add(p.Key); if (seen.Count > 1000) { var keep = seen.TakeLast(500).ToArray(); seen.Clear(); seen.UnionWith(keep); }
                File.WriteAllText(seenPath, JsonSerializer.Serialize(seen));
                try { job = new Job(p.Key, await api.Generate(p), DateTime.UtcNow); }
                catch (Exception ex) { Program.Log("generation_failed", new { p.Key, error = ex.GetType().Name, ex.Message }); job = new Job(p.Key, null, DateTime.UtcNow); }
            }
            if(connection.Faulted){ObserveWait(p,p.typing?"input_box_focused":!Native.CanUseBridge(p)?(BridgeInputPolicy.Extended(p)?"bridge_modifier_or_reserved_key_held":"communication_key_or_modifier_held"):"transport_recovery");tray.Text=job?.Reply!=null&&!job.Delivered?"大肥鱼 · 回复已缓存，等待回传恢复":"大肥鱼 · 等待按键松开，自动恢复";return;}
            if(!p.bindingsReady){ObserveWait(p,"bindings_not_ready");tray.Text="大肥鱼 · 专用接收快捷键未就绪";return;}
            if (p.typing) {ObserveWait(p,"input_box_focused");if(job?.Reply!=null&&!job.Delivered&&job.Key==p.Key)tray.Text="大肥鱼 · 回复已缓存，等待输入框关闭";return;}
            if(job!=null&&!job.Delivered)ObserveWait(p,Native.CanUseBridge(p)?"returning_reply":(BridgeInputPolicy.Extended(p)?"bridge_modifier_or_reserved_key_held":"communication_key_or_modifier_held"));
            if(job!=null&&job.Key==p.Key&&(p.status=="GENERATING"||(p.status=="READY"&&p.automatic&&p.auto&&!job.Committed&&!p.submitted))) {await Deliver(p);return;}
            if (DateTime.UtcNow >= nextPing)
            {
                if (await Command(p, $"ping {p.session} on {c.cooldownSeconds} {c.hourlyLimit}")) nextPing = DateTime.UtcNow.AddSeconds(30);
                return;
            }
            if (c.paused) return;
            if (keywordsSession != session)
            {
                string b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(string.Join(',', c.keywords)));
                if (await Command(p, $"keywords {p.session} {b64}")) keywordsSession = session; return;
            }
            if (generateRequested) { if (await Command(p, "generate")) generateRequested = false; return; }

        }
        catch (Exception ex) {
            connection.Fail(ex.Message);
            Program.Log("bridge_fault",new{error=ex.GetType().Name,ex.Message,recovery="automatic_when_keys_released",manualPaused=c.paused});
            tray.Text="大肥鱼 · 等待按键松开，自动恢复";
        }
        finally { timer.Interval=BridgeTiming.PollInterval(c.pollMs,deliveryWaiting); busy = false; }
    }
    protected override void ExitThreadCore() { shutdown = true; timer.Stop(); timer.Dispose();inputGuard.Dispose();Native.InputGuard=null; tray.Visible = false; tray.Dispose(); base.ExitThreadCore(); }
}
