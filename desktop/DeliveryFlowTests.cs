using System.Text.Json;
namespace WhaleChat;

internal static class DeliveryFlowTests
{
    static Packet Source()=>new(){protocol=8,bridgeRevision=2,craftGuardVersion=1,session="12345",requestId=2,bindingsReady=true,bridgeTransport="keys-safe2-v1",bridgeOpenKey=106,bridgeExecuteKey=219,bridgeDataKeys=new[]{221,220,186,222}.Select(k=>new BridgeKey(k,0)).ToArray(),receiverOpen=true,receiverNonce=42};
    sealed class FlowPort
    {
        internal Packet source=Source(),p=Source();
        internal string scenario="",received="";internal int waits,writes,blockedReads,heldTicks;internal bool enabled=true,armed;
        internal Packet? Read()
        {
            if(armed){armed=false;
                if(scenario=="pixels"||scenario=="both")blockedReads=4;
                if(scenario=="held"||scenario=="both")heldTicks=4;
                if(scenario=="permanent_pixels")blockedReads=10000;
                if(scenario=="permanent_held")heldTicks=10000;
                if(scenario=="session")p.session="54321";
                if(scenario=="request")p.requestId++;
                if(scenario=="typing")p.typing=true;
                if(scenario=="profession")p.professionBusy=true;
                if(scenario=="binding")p.bridgeExecuteKey=45;
                if(scenario=="corrupt")p.receiverProgressChecksum++;
                if(scenario=="nonce")p.receiverNonce++;
                if(scenario=="expired"){p.receiverOpen=false;p.bridgeError="键流接收超时";}
                if(scenario=="pause")enabled=false;
            }
            if(blockedReads>0){blockedReads--;return null;}return p;
        }
        internal bool Keys(Packet _)=>heldTicks==0;
        internal Task Delay(){waits++;if(heldTicks>0)heldTicks--;return Task.CompletedTask;}
        internal void Write((ushort key,bool up)[] strokes)
        {
            if(heldTicks>0||blockedReads>0)throw new Exception("Injected during blocked input");
            var symbols=strokes.Chunk(2).Select(pair=>Array.FindIndex(p.bridgeDataKeys,k=>k.key==pair[0].key)).ToArray();
            if(symbols.Any(i=>i<0)||strokes.Any(x=>x.key is 16 or 17 or 18))throw new Exception("Invalid injected key");
            string chunk=new(symbols.Chunk(4).Select(d=>(char)(d[0]*64+d[1]*16+d[2]*4+d[3])).ToArray());
            received+=chunk;writes++;p.receiverLength=received.Length;p.receiverProgressChecksum=BridgeEnvelope.Checksum(received);
            if(writes==2)armed=true;
            if(received.EndsWith('!')){p.receiverOpen=false;p.bridgeReadyNonce=p.receiverNonce;}
        }
        internal Task Run(string text)=>BridgeFlow.Transfer(text,source,Read,Keys,()=>enabled,Write,Delay);
    }
    sealed class OpenPort:IBridgePort
    {
        internal Packet p=Source();internal int opens,executed,typed,waits;internal string scenario="";internal bool pending;
        internal OpenPort(){p.receiverOpen=false;p.receiverNonce=41;p.bridgeError="旧接收超时";}
        public bool Enabled=>true;public bool Idle=>true;public bool KeysUp=>true;
        public Packet? Read()=>scenario=="torn_open"&&pending&&waits<3?null:p;
        public Task OpenReceiver(int k,int m){opens++;pending=true;return Task.CompletedTask;}
        public Task Delay(){waits++;if(pending&&waits>=3){pending=false;p.receiverNonce++;p.receiverOpen=true;p.bridgeError=scenario=="fresh_error"?"本次错误":"";}return Task.CompletedTask;}
        public Task TypeReceiver(string t){typed++;p.receiverOpen=false;p.bridgeReadyNonce=p.receiverNonce;p.bridgeReadyChecksum=int.Parse(t.Split(';')[^1].TrimEnd('!'));return Task.CompletedTask;}
        public Task ExecutePrepared(int k,int m){executed++;p.bridgeAck=p.bridgeReadyNonce;p.bridgeAckChecksum=p.bridgeReadyChecksum;return Task.CompletedTask;}
    }
    internal static async Task Run(Action<string,bool> check)
    {
        string wire=BridgeEnvelope.Create("12345",42,"rx 12345 2 5L2g5aW9").text;
        foreach(string scenario in new[]{"normal","pixels","held","both"}) {
            var port=new FlowPort{scenario=scenario};await port.Run(wire);
            check("delivery resumes exact bytes once after "+scenario,port.received==wire&&port.writes==BridgeFlow.Chunks(wire,4).Count());
            check("delivery injected no bytes during protected wait "+scenario,scenario=="normal"||port.waits>=4);
        }
        foreach(string scenario in new[]{"session","request","typing","profession","binding","corrupt","nonce","expired","pause","permanent_pixels","permanent_held"}) {
            var port=new FlowPort{scenario=scenario};bool rejected=false;
            try{await port.Run(wire);}catch(Exception e) when(e is InvalidOperationException or OperationCanceledException or TimeoutException){rejected=true;}
            check("delivery fails closed before another batch: "+scenario,rejected&&port.writes==2&&port.received==wire[..16]&&port.waits<=BridgeTiming.AckPollCount);
        }
        foreach(string scenario in new[]{"stale_error","torn_open"}) {
            var p=new OpenPort{scenario=scenario};bool ok=await new BridgeDispatcher(p).Send("12345","rx 12345 2 5L2g5aW9",2);
            check("old timeout cannot reject fresh open: "+scenario,ok&&p.opens==1&&p.typed==1&&p.executed==1&&p.waits>=3);
        }
        var bad=new OpenPort{scenario="fresh_error"};bool failed=false;
        try{await new BridgeDispatcher(bad).Send("12345","rx 12345 2 5L2g5aW9",2);}catch(BridgeAttemptException){failed=true;}
        check("new receiver error must not be ignored",failed&&bad.executed==0);
        var source=Source();
        foreach(int k in new[]{112,113,114,119,120,121,122,123,33,34,45,46,187,189,87,2})
            check("unused gameplay key does not block selected transport "+k,BridgeInputPolicy.Clear(source,x=>x==k));
        foreach(int k in new[]{16,17,18,91,92,160,161,162,163,164,165,106,219,221,220,186,222})
            check("modifier or actually reserved key still blocks "+k,!BridgeInputPolicy.Clear(source,x=>x==k));
        check("unknown map never authorizes input",!BridgeInputPolicy.Clear((Packet?)null,_=>false));
    }
}
