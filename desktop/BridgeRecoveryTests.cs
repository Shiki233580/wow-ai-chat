namespace WhaleChat;
internal static class BridgeRecoveryTests
{
 sealed class Port(string scenario):IBridgePort {
  internal Packet p=new(){protocol=8,bridgeRevision=2,craftGuardVersion=1,session="12345",requestId=2,bindingsReady=true,bridgeTransport="keys2-v1",bridgeOpenKey=118,bridgeExecuteKey=119,bridgeDataKeys=new[]{120,121,122,123}.Select(k=>new BridgeKey(k,0)).ToArray()};
  internal int opens,typed,executed,reads,readyReads,waits;int held;bool armed=true;
  public bool Enabled=>true;public bool Idle=>true;public bool KeysUp=>held==0;
  public Packet? Read(){reads++;if(typed>0)readyReads++;
   bool beforeData=opens>0&&typed==0&&reads==3,beforeExecute=typed>0&&readyReads==2;
   if(armed&&((scenario.EndsWith("data")&&beforeData)||(!scenario.EndsWith("data")&&beforeExecute))){armed=false;
    if(scenario.StartsWith("torn"))return null;
    if(scenario.StartsWith("held"))held=3;
    if(scenario=="typing")p.typing=true;
    if(scenario=="profession")p.professionBusy=true;
    if(scenario=="request")p.requestId++;
    if(scenario=="checksum")p.bridgeReadyChecksum++;
   }
   return p;
  }
  public Task OpenReceiver(int k,int m){opens++;p.receiverOpen=true;p.receiverNonce++;return Task.CompletedTask;}
  public Task TypeReceiver(string s){typed++;p.receiverOpen=false;p.bridgeReadyNonce=p.receiverNonce;p.bridgeReadyChecksum=int.Parse(s.Split(';')[^1].TrimEnd('!'));return Task.CompletedTask;}
  public Task ExecutePrepared(int k,int m){executed++;p.bridgeAck=p.receiverNonce;p.bridgeAckChecksum=p.bridgeReadyChecksum;return Task.CompletedTask;}
  public Task Delay(){waits++;if(held>0)held--;return Task.CompletedTask;}
 }
 internal static async Task Run(Action<string,bool> check) {
  foreach(string scenario in new[]{"torn_data","torn_execute","held_data","held_execute"}){
   var p=new Port(scenario);bool ok=await new BridgeDispatcher(p).Send("12345","rx 12345 2 5L2g5aW9",2);
   check("brief transport interruption preserves one payload "+scenario,ok&&p.opens==1&&p.typed==1&&p.executed==1&&p.waits>0);
  }
  foreach(string scenario in new[]{"typing","profession","request","checksum"}){
   var p=new Port(scenario);bool stopped=false;try{await new BridgeDispatcher(p).Send("12345","commit 12345 2",2);}catch(BridgeAttemptException ex){stopped=ex.CanRetry&&!ex.ExecutionStarted;}
   check("prepared packet still rejected on actual state change "+scenario,stopped&&p.executed==0&&p.waits<=BridgeTiming.AckPollCount);
  }
  string wire=BridgeEnvelope.Create("12345",42,"rx 12345 2 "+new string('A',180)).text;
  foreach(int size in new[]{2,4,8}){
   var slots=Enumerable.Range(112,size).Select(x=>new BridgeKey(x,0)).ToArray();var chunks=BridgeFlow.Chunks(wire,size).ToArray();
   check("adaptive chunks preserve envelope "+size,string.Concat(chunks)==wire);
   check("adaptive chunks retain 64-event upper bound "+size,chunks.All(c=>BridgeFlow.Strokes(c,slots,true).Length<=64));
  }
  check("four-key alphabet halves ACK batches",BridgeFlow.Chunks(wire,4).Count()==(BridgeFlow.Chunks(wire,2).Count()+1)/2);
  check("binary transport keeps four-byte bound",BridgeFlow.MaxChunkChars(2)==4);
  check("ACK budget counts capture time not only sleeps",BridgeTiming.DeadlineExpired(1000,4200));
  check("ACK budget does not expire early",!BridgeTiming.DeadlineExpired(1000,4199));
  check("slow capture cannot multiply nominal wait budget",BridgeTiming.DeadlineExpired(1000,9000));
  var source=new Port("").p;source.receiverNonce=42;source.receiverOpen=true;
  bool blocked=false;int polls=0,writes=0;bool ended=false;
  try {await BridgeFlow.Transfer(wire,source,()=>source,_=>true,()=>true,_=>{writes++;blocked=true;},()=>{polls++;return Task.CompletedTask;},inputInterrupted:()=>blocked);}
  catch(InvalidOperationException ex){ended=ex.Message.Contains("suppressed");}
  check("suppressed native input aborts without ACK timeout",ended&&writes==1&&polls==0);
  var guard=new InputGuardState();long before=guard.Suppressed;guard.OwnStroke(188,false,0,true);guard.OwnStroke(188,true,0,true);
  check("guard reports blocked downs without fake key releases",guard.Suppressed==before+1);
 }
}
