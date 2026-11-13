using System.Text;
using System.Text.Json;
using System.Diagnostics;
namespace WhaleChat;
internal static class BridgeSmoke
{
    internal static async Task<int> Run(Config c,string root)
    {
        var report=new List<object>();using var cancel=new CancellationTokenSource(TimeSpan.FromSeconds(45));
        var readiness=new BridgeSessionReadiness();Packet p;
        while(true){p=Native.Read(c)?.packet??throw new InvalidOperationException("Game must remain foreground");if(!BridgeInputPolicy.Supported(p)||p.requestId!=0||p.submitted||p.professionBusy||p.typing)throw new InvalidOperationException("Smoke requires new idle guarded session without any request");if(readiness.Ready(p.session,Environment.TickCount64))break;await Task.Delay(250,cancel.Token);}
        async Task Send(string command){var sw=Stopwatch.StartNew();bool ok=await Native.Command(c,p.session,command,()=>!cancel.IsCancellationRequested,0);report.Add(new{kind=command.Split(' ')[0],ok,elapsedMs=sw.ElapsedMilliseconds});if(!ok)throw new InvalidOperationException("Unacknowledged smoke command");}
        try{
            await Send($"ping {p.session} off 0 0");
            // No pending request exists. This validated, deliberately nonmatching rx is ignored by Core.Receive.
            // It tests maximum reply-sized transport without generating or sending any chat.
            await Send($"rx {p.session} 2147483647 "+Convert.ToBase64String(Encoding.UTF8.GetBytes(string.Concat(Enumerable.Repeat("🐳",48)))));
            await Send($"ping {p.session} off 0 0");
            var last=Native.Read(c)?.packet??throw new InvalidOperationException("Final state unavailable");
            if(last.requestId!=0||last.submitted||last.confirmed)throw new InvalidOperationException("Unexpected pending work");
            report.Add(new{last.session,last.status,last.receiverNonce,last.bridgeAck,last.requestId,last.submitted,scope="ping off and nonmatching rx only; no chat generated or sent"});return 0;
        }finally{Directory.CreateDirectory(Path.Combine(root,"verification"));File.WriteAllText(Path.Combine(root,"verification","bridge-smoke.json"),JsonSerializer.Serialize(report,new JsonSerializerOptions{WriteIndented=true}));}
    }
}
