namespace WhaleChat;

internal static class BridgeFlow
{
    internal static int MaxChunkChars(int alphabetSize)=>alphabetSize switch {2=>4,4=>8,8=>10,_=>throw new InvalidDataException("Invalid alphabet size")};
    internal static bool StateMatches(Packet? p,Packet source,int nonce)=>p!=null&&p.session==source.session&&p.requestId==source.requestId&&p.bridgeRevision==2&&p.receiverNonce==nonce&&!p.typing&&!p.professionBusy&&p.bindingsReady&&p.bridgeTransport==source.bridgeTransport&&p.bridgeDataKeys.SequenceEqual(source.bridgeDataKeys)&&p.bridgeOpenKey==source.bridgeOpenKey&&p.bridgeExecuteKey==source.bridgeExecuteKey&&p.bridgeOpenMods==source.bridgeOpenMods&&p.bridgeExecuteMods==source.bridgeExecuteMods;
    internal static bool CanWrite(Packet p,int length,int checksum,bool keysClear)=>p.receiverOpen&&p.receiverLength==length&&p.receiverProgressChecksum==checksum&&keysClear;
    internal static (ushort key,bool up)[] Strokes(string chunk,BridgeKey[] slots,bool extended)
    {
        if(chunk.Any(c=>c<32||c>126)|| (!extended||slots.Length is not (2 or 4 or 8)))throw new InvalidDataException("Invalid chunk alphabet");
        if(chunk.Length<1||chunk.Length>MaxChunkChars(slots.Length))throw new InvalidDataException("Chunk exceeds 64 native events");
        return BridgeInputPolicy.Symbols(chunk,extended,slots.Length).SelectMany(i=>Native.ReceiverStrokePlan(slots[i].key,slots[i].mods)).ToArray();
    }
    internal static IEnumerable<string> Chunks(string text,int alphabetSize=2)
    { int size=MaxChunkChars(alphabetSize);for(int i=0;i<text.Length;i+=size)yield return text.Substring(i,Math.Min(size,text.Length-i)); }
    // Keep the verified cursor across brief key holds and torn pixel frames.
    // Waiting is read-only. A changed request/session/map or invalid ACK aborts;
    // the next dispatcher attempt explicitly resets the receiver before retrying.
    internal static async Task Transfer(string text,Packet source,Func<Packet?> read,
        Func<Packet,bool> keysClear,Func<bool> enabled,Action<(ushort key,bool up)[]> write,
        Func<Task> delay,Action<int,int,int,int>? progress=null,Func<bool>? inputInterrupted=null)
    {
        if(!text.StartsWith("DFY4;",StringComparison.Ordinal)||!text.EndsWith('!')||text.Length>480||text.Any(ch=>ch<32||ch>126))
            throw new InvalidDataException("Invalid envelope");
        if(source.bridgeRevision!=2||!BridgeInputPolicy.Extended(source))throw new InvalidDataException("Flow-controlled addon required");
        int nonce=int.Parse(text.Split(';')[2]),length=0,sum=0;
        async Task WaitFor(Func<Packet,bool> predicate,string stage)
        {
            long started=Environment.TickCount64;
            for(int i=0;i<BridgeTiming.AckPollCount;i++) {
                if(!enabled())throw new OperationCanceledException("Bridge paused");
                if(inputInterrupted?.Invoke()==true)throw new InvalidOperationException("Input guard suppressed queued strokes; reset partial stream before retry");
                var p=read();
                if(BridgeTiming.DeadlineExpired(started,Environment.TickCount64))break;
                if(p!=null) {
                    if(!StateMatches(p,source,nonce))throw new InvalidOperationException("Flow-control state changed: "+stage);
                    if(!string.IsNullOrEmpty(p.bridgeError))throw new InvalidOperationException("Receiver rejected: "+p.bridgeError);
                    if(predicate(p))return;
                    if(!p.receiverOpen || p.receiverLength>length || (p.receiverLength==length && p.receiverProgressChecksum!=sum))
                        throw new InvalidOperationException("Flow-control cursor changed: "+stage);
                }
                await delay();
            }
            throw new TimeoutException("No verified flow-control progress: "+stage);
        }
        foreach(string chunk in Chunks(text,source.bridgeDataKeys.Length)) {
            await WaitFor(p=>CanWrite(p,length,sum,keysClear(p)),"before_chunk");
            var strokes=Strokes(chunk,source.bridgeDataKeys,true);
            if(!enabled())throw new OperationCanceledException("Bridge paused");
            write(strokes);
            foreach(char ch in chunk){length++;sum=(sum+ch*length)%65536;}
            progress?.Invoke(nonce,chunk.Length,length,strokes.Length);
            bool final=length==text.Length;
            await WaitFor(p=>Acknowledged(p,nonce,length,sum,final),"chunk_ack");
        }
    }
    internal static bool Acknowledged(Packet p,int nonce,int length,int checksum,bool final)
    {
        if(p.receiverNonce!=nonce||p.receiverProgressChecksum!=checksum||!string.IsNullOrEmpty(p.bridgeError))return false;
        return final ? p.bridgeReadyNonce==nonce : p.receiverOpen&&p.receiverLength==length;
    }
}

internal sealed class BridgeSessionReadiness
{
    string session="";long first;int reads;
    internal bool Ready(string current,long now)
    {
        if(current!=session){session=current;first=now;reads=0;}
        reads++;
        return current.Length>0&&reads>=3&&now-first>=750;
    }
}

internal static class FlowTests
{
    internal static void Run(Action<string,bool> check)
    {
        string wire=BridgeEnvelope.Create("12345",1,"ping 12345 on 0 0").text;
        var chunks=BridgeFlow.Chunks(wire).ToArray();
        check("flow chunks preserve exact envelope",string.Concat(chunks)==wire&&chunks.All(x=>x.Length<=4));
        check("largest binary batch bounded64 events",chunks.All(x=>x.Length*2*8<=64));
        var alphabet=Enumerable.Range(122,2).Select(i=>new BridgeKey(i,0)).ToArray();
        var strokes=BridgeFlow.Strokes("DFY4",alphabet,true);
        check("binary native plan bounded64 and every function key fully released",strokes.Length==64&&strokes.Chunk(2).All(c=>!c[0].up&&c[1].up&&c[0].key==c[1].key));
        bool rejected=false;try{BridgeFlow.Strokes("12345",alphabet,true);}catch(InvalidDataException){rejected=true;}check("oversized input chunk refused before native input",rejected);
        var source=new Packet{session="1",requestId=9,bridgeRevision=2,bindingsReady=true,bridgeTransport="keys1-v1",bridgeDataKeys=alphabet,receiverNonce=7,receiverOpen=true};
        check("matching transfer snapshot accepted",BridgeFlow.StateMatches(source,source,7));
        foreach(string mutation in new[]{"session","request","revision","typing","craft","binding","alphabet","nonce"}){
            var q=System.Text.Json.JsonSerializer.Deserialize<Packet>(System.Text.Json.JsonSerializer.Serialize(source))!;
            switch(mutation){case "session":q.session="2";break;case "request":q.requestId++;break;case "revision":q.bridgeRevision=1;break;case "typing":q.typing=true;break;case "craft":q.professionBusy=true;break;case "binding":q.bindingsReady=false;break;case "alphabet":q.bridgeDataKeys[0]=new BridgeKey(112,0);break;case "nonce":q.receiverNonce++;break;}
            check("native chunk preflight blocks changed "+mutation,!BridgeFlow.StateMatches(q,source,7));
        }
        check("held user input blocks subsequent native chunk",!BridgeFlow.CanWrite(source,0,0,false));
        check("partial bytes cannot be blindly appended",!BridgeFlow.CanWrite(source,4,1,true));
        var p=new Packet{receiverOpen=true,receiverNonce=7,receiverLength=4,receiverProgressChecksum=321};
        check("partial acknowledgement checks nonce length checksum",BridgeFlow.Acknowledged(p,7,4,321,false));
        check("wrong partial checksum cannot authorize next chunk",!BridgeFlow.Acknowledged(p,7,4,322,false));
        check("wrong partial length cannot authorize next chunk",!BridgeFlow.Acknowledged(p,7,5,321,false));
        check("old nonce cannot acknowledge chunk",!BridgeFlow.Acknowledged(p,8,4,321,false));
        p.receiverOpen=false;p.receiverLength=0;p.bridgeReadyNonce=7;
        check("final prepared acknowledgement accepted",BridgeFlow.Acknowledged(p,7,4,321,true));
        p.bridgeError="corrupt";check("receiver error never acknowledged",!BridgeFlow.Acknowledged(p,7,4,321,true));
        var ready=new BridgeSessionReadiness();check("new reload never injects immediately",!ready.Ready("100",1000));
        check("second fresh snapshot still settling",!ready.Ready("100",1500));
        check("stable session becomes eligible automatically",ready.Ready("100",1750));
        check("subsequent messages have no new delay",ready.Ready("100",1751));
        check("new session resets settling barrier",!ready.Ready("101",1800));
        check("old revision requires upgraded addon",!BridgeInputPolicy.Supported(new Packet{protocol=8,craftGuardVersion=1,bridgeTransport="keys1-v1"}));
    }
}
