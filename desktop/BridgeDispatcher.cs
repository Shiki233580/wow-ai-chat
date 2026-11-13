using System.Text;

namespace WhaleChat;

internal interface IBridgePort
{
    Packet? Read();
    bool Enabled { get; }
    bool Idle { get; }
    bool KeysUp { get; }
    Task OpenReceiver(int key,int modifiers);
    Task TypeReceiver(string text);
    Task ExecutePrepared(int key,int modifiers);
    Task Delay();
}

internal static class BridgeEnvelope
{
    internal static int Checksum(string text) => text.Select((ch, index) => (int)ch * (index + 1)).Sum() & 65535;
    internal static (string text,int checksum) Create(string session,int nonce,string command)
    {
        if (session.Length==0 || session.Any(c=>c<'0'||c>'9') || nonce<1 || command.Length>320 || command.Any(c=>c<32||c>126)) throw new InvalidDataException("Invalid dedicated-receiver command");
        string kind=command.Split(' ')[0]; if(kind is not ("ping" or "keywords" or "generate" or "rx" or "fail" or "commit")) throw new InvalidDataException("Unsupported internal command");
        string prefix=$"DFY4;{session};{nonce};{Convert.ToBase64String(Encoding.ASCII.GetBytes(command))}";
        if(prefix.Length+8>480)throw new InvalidDataException("Receiver envelope exceeds480 bytes");
        int checksum=Checksum(prefix);return ($"{prefix};{checksum}!",checksum);
    }
}

// A failed transport attempt is not a permanent disconnect.
internal sealed class NativeInputNotStartedException(string message) : InvalidOperationException(message);
internal sealed class BridgeAttemptException(string kind,bool executionStarted,Exception inner)
    : InvalidOperationException(inner.Message,inner)
{
    internal string Kind=>kind;
    internal bool ExecutionStarted=>executionStarted;
    internal bool CanRetry=>!executionStarted || kind is not ("commit" or "generate");
}
internal static class DeliveryRecovery
{
    internal static bool FitsReply(Packet p,Reply reply)=>reply.text.EnumerateRunes().Count()<=Math.Clamp(p.replyMaxChars,0,48);
    internal static bool ReplyObserved(Packet p,Reply? reply)
    {
        if(reply==null || !(p.status=="READY" || p.submitted || p.confirmed))return false;
        string expected=reply.text;
        if(p.replyPrefix=="【大肥鱼】") {
            while(expected.StartsWith(p.replyPrefix,StringComparison.Ordinal))expected=expected[p.replyPrefix.Length..];
            if(p.eventFlavor && p.generationMode=="event" && p.eventReply.Length>0) {
                if(expected.StartsWith(p.eventReply,StringComparison.Ordinal))expected=expected[p.eventReply.Length..].Trim();
                expected=p.eventReply+(expected.Length>0?" "+expected:"");
            }
            expected=p.replyPrefix+expected;
        }
        return p.reply==expected;
    }
}

// Two-phase key stream: bound symbols -> pixel-verified prepared packet -> execute key -> pixel ACK.
// There is deliberately no Enter key and no interaction with any ChatFrame edit box.
internal sealed class BridgeDispatcher(IBridgePort port)
{
    int openKey,executeKey,openMods,executeMods; string alphabet="";
    static string Alphabet(Packet p)=>p.bridgeTransport+":"+string.Join(";",p.bridgeDataKeys.Select(k=>k.key+":"+k.mods));
    static bool ValidAlphabet(Packet p)=>BridgeInputPolicy.Extended(p);
    static bool ValidKeys(Packet p)=>BridgeInputPolicy.Extended(p);
    bool Same(Packet p,string session,int? request) => p.protocol==8 && ValidAlphabet(p) && Alphabet(p)==alphabet && p.session==session && p.bindingsReady && ValidKeys(p) && p.bridgeOpenKey==openKey && p.bridgeExecuteKey==executeKey && p.bridgeOpenMods==openMods && p.bridgeExecuteMods==executeMods && (request==null||p.requestId==request);
    void Enabled() { if(!port.Enabled) throw new OperationCanceledException("Bridge paused or closing"); }
    async Task<Packet> Wait(string session,int? request,Func<Packet,bool> predicate,string label,int? openingAfter=null)
    {
        for(int i=0;i<BridgeTiming.AckPollCount;i++) {
            Enabled(); var p=port.Read();
            if(p==null) { await port.Delay(); continue; } // Torn/occluded frame: read-only retry, never inject blindly.
            if(!Same(p,session,request)) throw new InvalidOperationException("Bridge state lost: "+label);
            if(!string.IsNullOrEmpty(p.bridgeError) && !(openingAfter.HasValue && p.receiverNonce<=openingAfter.Value))
                throw new InvalidOperationException("Addon receiver rejected at "+label+": "+p.bridgeError+" ["+p.bridgeRxDiagnostic+"]");
            if(predicate(p)) return p; // Read-only ACK may complete even if input resumes.
            if(p.professionBusy) throw new InvalidOperationException("Profession opened during bridge: "+label);
            if(!port.KeysUp) throw new InvalidOperationException("Communication modifier/function key interrupted: "+label);
            if(p.typing) throw new InvalidOperationException("Unrelated input focus: "+label);
            await port.Delay();
        }
        throw new TimeoutException("No verified addon acknowledgement: "+label);
    }
    internal async Task<bool> Send(string session,string command,int? request=null)
    {
        bool executionStarted=false;
        try {
        Enabled();var initial=port.Read();alphabet=initial==null?"":Alphabet(initial);
        openKey=initial?.bridgeOpenKey??0;executeKey=initial?.bridgeExecuteKey??0;openMods=initial?.bridgeOpenMods??0;executeMods=initial?.bridgeExecuteMods??0;
        if(initial==null||!Same(initial,session,request)||initial.professionBusy||initial.typing||!port.KeysUp) return false;
        // A previous attempt owns no live cursor here. Reset its partial stream explicitly; never append blindly.
        int initialNonce=initial.receiverNonce;
        bool alreadyOpen=initial.receiverOpen && initial.receiverLength==0 && string.IsNullOrEmpty(initial.bridgeError);
        if(!alreadyOpen) await port.OpenReceiver(openKey,openMods);
        var ready=await Wait(session,request,p=>p.receiverOpen&&(alreadyOpen?p.receiverNonce==initialNonce:p.receiverNonce>initialNonce),"open_receiver",alreadyOpen?null:initialNonce);
        int nonce=ready.receiverNonce;
        var envelope=BridgeEnvelope.Create(session,nonce,command);
        Enabled();var check=port.Read();
        if(check==null||check.professionBusy||check.typing||!Same(check,session,request)||!check.receiverOpen||check.receiverNonce!=nonce||!port.KeysUp) throw new InvalidOperationException("Key-stream state or input changed before data");
        await port.TypeReceiver(envelope.text);
        await Wait(session,request,p=>!p.typing&&p.bridgeReadyNonce==nonce&&p.bridgeReadyChecksum==envelope.checksum,"prepare_payload");
        Enabled();check=port.Read();
        if(check==null||check.professionBusy||!Same(check,session,request)||check.typing||check.bridgeReadyNonce!=nonce||check.bridgeReadyChecksum!=envelope.checksum||!port.KeysUp) throw new InvalidOperationException("Prepared payload changed; execute refused");
        executionStarted=true; // Conservative: a native call can partially succeed.
        await port.ExecutePrepared(executeKey,executeMods);
        // 'generate' may intentionally increment requestId, so only session/nonce remain fixed for its ACK.
        await Wait(session,null,p=>p.bridgeAck==nonce&&p.bridgeAckChecksum==envelope.checksum&&string.IsNullOrEmpty(p.bridgeError),"execute_ack");
        return true;
        } catch(Exception ex) when(ex is not BridgeAttemptException) { throw new BridgeAttemptException(command.Split(' ')[0],executionStarted && ex is not NativeInputNotStartedException,ex); }
    }
}

internal static class BridgeTiming
{
    internal const int AckPollMs=20, AckPollCount=160;
    internal static int PollInterval(int configured,bool delivering)=>delivering?Math.Min(configured,50):configured;
}

// Validated unmodified transport: six standard F keys, or legacy ten extended F keys.
internal static class BridgeInputPolicy
{
 internal static readonly int[] AuxiliaryKeys={45,46,36,35,33,34,106,107,109,111,219,221,220,186,222,188,190,192,189,187};
 internal static bool AllowedKey(int key)=>key is >=112 and <=135 || AuxiliaryKeys.Contains(key);
 internal static bool Supported(Packet p)=>p.protocol==8&&p.craftGuardVersion==1&&p.bridgeRevision==2&&p.bridgeTransport is ("keys1-v1" or "keys2-v1" or "keys3-v1" or "keys-safe1-v1" or "keys-safe2-v1");
 internal static bool Extended(Packet? p)
 {
  if(p==null||p.protocol!=8)return false;
  bool safe=p.bridgeTransport is "keys-safe1-v1" or "keys-safe2-v1";
  bool binary=p.bridgeTransport is "keys1-v1" or "keys-safe1-v1",standard=safe||binary||p.bridgeTransport=="keys2-v1";
  int count=binary?2:standard?4:8,min=standard?112:124,max=standard?123:135;
  if((!standard&&p.bridgeTransport!="keys3-v1")||p.bridgeDataKeys.Length!=count)return false;
  var keys=p.bridgeDataKeys.Concat(new[]{new BridgeKey(p.bridgeOpenKey,p.bridgeOpenMods),new BridgeKey(p.bridgeExecuteKey,p.bridgeExecuteMods)}).ToArray();
  return keys.All(k=>(safe?AllowedKey(k.key)&&!(k.key>=124&&k.key<=135):k.key>=min&&k.key<=max)&&k.mods==0)&&keys.Distinct().Count()==count+2;
 }
 internal static bool Clear(Packet? p,Func<int,bool> held)
 {
  if(!Extended(p))return false;
  foreach(int k in new[]{16,17,18,91,92,160,161,162,163,164,165})if(held(k))return false;
  return !p!.bridgeDataKeys.Select(k=>k.key).Append(p.bridgeOpenKey).Append(p.bridgeExecuteKey).Any(held);
 }
 internal static bool Clear(bool extended,Func<int,bool> held)
 {
  // Both validated transports use reserved function keys. Ordinary movement/mouse
  // state is not a conflicting chord and must not reset a reply transfer.
  // Never synthesize releases of user movement or mouse buttons; modifiers and
  // reserved function keys remain blockers for both modified/unmodified streams.
  foreach(int k in new[]{16,17,18,91,92,160,161,162,163,164,165})if(held(k))return false;
  for(int k=112;k<=135;k++)if(held(k))return false;
  foreach(int k in AuxiliaryKeys)if(held(k))return false;
  return true;
 }
 internal static IEnumerable<int> Symbols(string text,bool extended,int alphabetSize=8)
 {
  if(!extended || alphabetSize is not (2 or 4 or 8))throw new InvalidDataException("Unmodified alphabet required");
  foreach(char c in text){if(alphabetSize==2){for(int bit=7;bit>=0;bit--)yield return (c>>bit)&1;}else if(extended&&alphabetSize==4){yield return c>>6;yield return(c>>4)&3;yield return(c>>2)&3;yield return c&3;}else if(extended){yield return c>>6;yield return(c>>3)&7;yield return c&7;}else{yield return c>>4;yield return c&15;}}
 }
}
