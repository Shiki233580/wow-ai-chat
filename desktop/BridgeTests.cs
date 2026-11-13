namespace WhaleChat;

internal static class BridgeTests
{
    sealed class Port:IBridgePort
    {
        internal Packet P=new(){protocol=8,session="12345",bindingsReady=true,bridgeOpenKey=119,bridgeExecuteKey=120,bridgeTransport="keys1-v1",bridgeDataKeys=new[]{new BridgeKey(112,0),new BridgeKey(113,0)}};
        internal bool enabled=true,idle=true,keys=true,extended=false;
        internal HashSet<int> held=[];
        internal string scenario="";
        internal int reads,opens,typed,executed;
        internal List<string> Trace=[];
        public bool Enabled=>enabled;
        public bool Idle=>idle;
        public bool KeysUp=>keys&&BridgeInputPolicy.Clear(extended,k=>held.Contains(k));
        public Packet? Read(){if(extended&&reads==0){P.bridgeTransport="keys2-v1";P.bridgeDataKeys=new[]{121,122,123,117}.Select(k=>new BridgeKey(k,0)).ToArray();}reads++;if(scenario=="focus_after_open"&&opens>0)return null;if(scenario=="session_after_open"&&opens>0)P.session="6789";return P;}
        public Task OpenReceiver(int key,int modifiers){opens++;Trace.Add((modifiers==0?"":"M"+modifiers+":")+"F"+(key-111));if(scenario!="no_receiver"){P.receiverOpen=true;P.typing=false;P.receiverNonce++;if(scenario=="profession_after_open")P.professionBusy=true;if(scenario=="held_after_open")keys=false;if(scenario=="pause_after_open")enabled=false;}return Task.CompletedTask;}
        public Task TypeReceiver(string text){typed++;Trace.Add(text);if(scenario=="corrupted_payload"){P.bridgeError="校验失败";return Task.CompletedTask;}var parts=text.TrimEnd('!').Split(';');P.bridgeReadyChecksum=int.Parse(parts[^1]);P.bridgeReadyNonce=P.receiverNonce;P.typing=false;P.receiverOpen=false;if(scenario=="profession_after_type")P.professionBusy=true;if(scenario=="focus_after_type")P.typing=true;if(scenario=="combat_after_type")P.combat=true;if(scenario=="keys_changed")P.bridgeExecuteKey=122;return Task.CompletedTask;}
        public Task ExecutePrepared(int key,int modifiers){if(scenario=="execute_preflight")throw new NativeInputNotStartedException("keys changed before native input");executed++;Trace.Add((modifiers==0?"":"M"+modifiers+":")+"F"+(key-111));if(scenario!="missing_ack"){P.bridgeAck=P.bridgeReadyNonce;P.bridgeAckChecksum=P.bridgeReadyChecksum;P.bridgeReadyNonce=0;if(scenario=="generate_increments_request")P.requestId++;}if(scenario=="keys_after_ack")keys=false;return Task.CompletedTask;}
        public Task Delay()=>Task.CompletedTask;
    }
    internal static async Task Run(Action<string,bool> check)
    {
        var crafting=new Port();crafting.P.professionBusy=true;
        check("profession busy blocks all native transport before open",!await new BridgeDispatcher(crafting).Send("12345","ping 12345 on 0 0")&&crafting.opens==0&&crafting.typed==0&&crafting.executed==0);
        foreach(string step in new[]{"profession_after_open","profession_after_type"}){
            var port=new Port{scenario=step};bool rejected=false;
            try{await new BridgeDispatcher(port).Send("12345","commit 12345 1");}catch(BridgeAttemptException ex){rejected=ex.CanRetry&&!ex.ExecutionStarted;}
            check("profession starts mid-transfer aborts safely "+step,rejected&&port.executed==0&&port.typed==(step=="profession_after_open"?0:1));
        }
        foreach(string transport in new[]{"keys1-v1","keys2-v1","keys3-v1"})check("guarded protocol supported "+transport,BridgeInputPolicy.Supported(new Packet{protocol=8,craftGuardVersion=1,bridgeRevision=2,bridgeTransport=transport}));
        check("old addon without crafting guard requires reload",!BridgeInputPolicy.Supported(new Packet{protocol=8,bridgeTransport="keys-v1"}));
        check("unknown guard version fails closed",!BridgeInputPolicy.Supported(new Packet{protocol=8,craftGuardVersion=2,bridgeTransport="keys-v1"}));
        var moving=new Port{extended=true,held=[87,2]};moving.P.requestId=1;
        check("extended full rx works while W and right mouse held",await new BridgeDispatcher(moving).Send("12345","rx 12345 1 5L2g5aW9",1)&&moving.executed==1);
        check("extended commit works while movement still held",await new BridgeDispatcher(moving).Send("12345","commit 12345 1",1)&&moving.executed==2);
        var ctrl=new Port{extended=true,held=[17]};check("held ctrl still prevents any injected input",!await new BridgeDispatcher(ctrl).Send("12345","generate")&&ctrl.opens==0);
        var focused=new Port{extended=true,held=[87]};focused.P.typing=true;check("focused chat still prevents extended input",!await new BridgeDispatcher(focused).Send("12345","generate")&&focused.opens==0);
        var partial=new Port();partial.P.receiverOpen=true;partial.P.typing=true;partial.P.receiverLength=5;
        check("partial receiver never gets appended/replayed payload",!await new BridgeDispatcher(partial).Send("12345","rx 12345 1 5L2g5aW9",1)&&partial.typed==0&&partial.executed==0);
        foreach(var kind in new[]{"rx","commit"}) {
            var interrupted=new Port{scenario="held_after_open"};interrupted.P.requestId=1;BridgeAttemptException? failure=null;
            try{await new BridgeDispatcher(interrupted).Send("12345",kind+" 12345 1"+(kind=="rx"?" 5L2g5aW9":""),1);}catch(BridgeAttemptException ex){failure=ex;}
            check("pre-execution "+kind+" interruption is safely retryable",failure!=null&&failure.CanRetry&&!failure.ExecutionStarted&&interrupted.executed==0);
            interrupted.keys=true;interrupted.scenario="";interrupted.P.receiverOpen=false;interrupted.P.typing=false;
            check("idle recovery finishes "+kind+" once without reconnect",await new BridgeDispatcher(interrupted).Send("12345",kind+" 12345 1"+(kind=="rx"?" 5L2g5aW9":""),1)&&interrupted.executed==1);
        }
        foreach(var kind in new[]{"rx","commit","generate"}) {
            var lost=new Port{scenario="missing_ack"};BridgeAttemptException? failure=null;
            try{await new BridgeDispatcher(lost).Send("12345",kind+" 12345 1");}catch(BridgeAttemptException ex){failure=ex;}
            check("post-execution lost ACK retry policy "+kind,failure!=null&&failure.ExecutionStarted&&failure.CanRetry==(kind=="rx")&&lost.executed==1);
        }
        var preflight=new Port{scenario="execute_preflight"};BridgeAttemptException? beforeNative=null;
        try{await new BridgeDispatcher(preflight).Send("12345","commit 12345 1");}catch(BridgeAttemptException ex){beforeNative=ex;}
        check("commit preflight rejection before native input is retryable",beforeNative!=null&&beforeNative.CanRetry&&!beforeNative.ExecutionStarted&&preflight.executed==0);
        var acknowledged=new Port{scenario="keys_after_ack"};check("verified ACK succeeds despite subsequent user key",await new BridgeDispatcher(acknowledged).Send("12345","commit 12345 1")&&acknowledged.executed==1);
        check("read-only reply reconciliation recovers lost rx ACK",DeliveryRecovery.ReplyObserved(new Packet{status="READY",reply="你好"},new Reply("你好",0,1,"test")));
        check("different reply cannot authorize auto commit",!DeliveryRecovery.ReplyObserved(new Packet{status="READY",reply="other"},new Reply("你好",0,1,"test")));
        var mouseMoving=new Port{idle=false};check("mouse activity never blocks heartbeat",await new BridgeDispatcher(mouseMoving).Send("12345","ping 12345 on 0 0")&&mouseMoving.executed==1);
        var mouseGenerating=new Port{idle=false};check("mouse activity never blocks generation transport",await new BridgeDispatcher(mouseGenerating).Send("12345","generate")&&mouseGenerating.executed==1);
        var good=new Port();check("dedicated receiver full acknowledged transaction",await new BridgeDispatcher(good).Send("12345","ping 12345 on 12 30"));
        check("transport emits no Enter and no slash-chat command",good.Trace.All(s=>s!="ENTER"&&!s.Contains("/dfy"))&&good.opens==1&&good.typed==1&&good.executed==1);
        var manual=new Port();manual.P.receiverOpen=true;manual.P.typing=false;manual.P.receiverNonce=5;
        check("panel-opened receiver needs no extra open key",await new BridgeDispatcher(manual).Send("12345","ping 12345 on 12 30")&&manual.opens==0&&manual.executed==1);
        foreach(string scenario in new[]{"moving","typing","old_protocol","binding_conflict"}){
            var p=new Port();if(scenario=="moving")p.keys=false;if(scenario=="typing")p.P.typing=true;if(scenario=="combat")p.P.combat=true;if(scenario=="old_protocol")p.P.protocol=2;if(scenario=="binding_conflict")p.P.bindingsReady=false;if(scenario=="idle_too_short")p.idle=false;
            bool ok=await new BridgeDispatcher(p).Send("12345","generate");check("no input when "+scenario,!ok&&p.opens==0&&p.typed==0&&p.executed==0);
        }
        foreach(string scenario in new[]{"no_receiver","focus_after_open","session_after_open","held_after_open","pause_after_open","corrupted_payload","focus_after_type","keys_changed","missing_ack"}){
            var p=new Port{scenario=scenario};bool refused=false;try{await new BridgeDispatcher(p).Send("12345","ping 12345 on 12 30");}catch(Exception ex) when(ex is InvalidOperationException or OperationCanceledException or TimeoutException){refused=true;}
            check("fail closed without retry: "+scenario,refused&&p.opens==1&&p.typed<=1&&p.executed<=(scenario=="missing_ack"?1:0));
        }
        var fighting=new Port();fighting.P.combat=true;
        check("combat alone does not block acknowledged transaction",await new BridgeDispatcher(fighting).Send("12345","ping 12345 on 12 30")&&fighting.executed==1);
        var entering=new Port{scenario="combat_after_type"};
        check("entering combat during transaction does not discard request",await new BridgeDispatcher(entering).Send("12345","ping 12345 on 12 30")&&entering.executed==1);
        var free=new Port();free.P.bridgeOpenKey=121;free.P.bridgeExecuteKey=122;
        check("uses advertised free keys F10/F11",await new BridgeDispatcher(free).Send("12345","ping 12345 on 12 30")&&free.Trace[0]=="F10"&&free.Trace[^1]=="F11");
        foreach(var pair in new[]{(13,120),(119,13),(119,119),(0,0)}) {
            var invalid=new Port();invalid.P.bridgeOpenKey=pair.Item1;invalid.P.bridgeExecuteKey=pair.Item2;
            check("invalid key map rejected "+pair,!await new BridgeDispatcher(invalid).Send("12345","generate")&&invalid.opens==0&&invalid.typed==0);
        }
        var chords=new Port();chords.P.bridgeOpenMods=6;chords.P.bridgeExecuteMods=7;
        check("advertised modifier chords refused with zero input",!await new BridgeDispatcher(chords).Send("12345","ping 12345 on 12 30")&&chords.opens==0&&chords.typed==0&&chords.executed==0);
        foreach(int mod in new[]{1,2,3,4,5,6,7,8,-1}) {
            var invalidMod=new Port();invalidMod.P.bridgeOpenMods=mod;check("reject unsupported modifier "+mod,!await new BridgeDispatcher(invalidMod).Send("12345","generate")&&invalidMod.opens==0);
            bool refused=false;try{Native.ReceiverKeys(119,mod);}catch(InvalidDataException){refused=true;}check("native modifier rejected "+mod,refused);
        }
        var legacy=new Port();legacy.P.bridgeTransport="keys-v1";
        check("old addon cannot cause any native input",!await new BridgeDispatcher(legacy).Send("12345","generate")&&legacy.opens==0&&legacy.typed==0&&legacy.executed==0);
        var changed=new Port{scenario="generate_increments_request"};check("generate ACK survives intentional request increment",await new BridgeDispatcher(changed).Send("12345","generate"));
        bool bad=false;try{BridgeEnvelope.Create("12345",1,"/say leaked");}catch(InvalidDataException){bad=true;}check("arbitrary/slash commands rejected",bad);
        var env=BridgeEnvelope.Create("12345",9,"ping 12345 on 12 30");check("dedicated envelope has no control keys",env.text.StartsWith("DFY4;")&&env.text.EndsWith('!')&&env.text.All(c=>c>=32&&c<=126));
        check("wire contains no WoW pipe markup",!env.text.Contains('|')&&env.text.Count(c=>c==';')==4);
    }
}
