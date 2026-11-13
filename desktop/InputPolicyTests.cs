using System.Text;
using System.Text.Json;
namespace WhaleChat;
internal static class InputPolicyTests
{
 internal static void Run(Action<string,bool> check,string root)
 {
  var p=new Packet{protocol=8,bridgeTransport="keys3-v1",bridgeOpenKey=124,bridgeExecuteKey=125,bridgeDataKeys=Enumerable.Range(126,8).Select(k=>new BridgeKey(k,0)).ToArray()};
  check("extended alphabet uses ten distinct unmodified keys",BridgeInputPolicy.Extended(p));
  foreach(int key in new[]{1,2,4,32,49,50,65,68,69,81,83,87})
   check("ordinary gameplay key allowed "+key,BridgeInputPolicy.Clear(true,k=>k==key));
  check("legacy reply transfer allows held movement",BridgeInputPolicy.Clear(false,k=>k==87));
  check("legacy reply transfer allows simultaneous movement and mouse",BridgeInputPolicy.Clear(false,k=>new[]{1,2,65,87}.Contains(k)));
  foreach(int key in new[]{1,2,4,32,49,50,65,68,69,81,83,87})
   check("legacy ordinary gameplay key allowed "+key,BridgeInputPolicy.Clear(false,k=>k==key));
  foreach(int key in new[]{16,17,18,91,92,160,161,162,163,164,165,112,123,124,130,135})
   check("legacy communication conflict remains blocked "+key,!BridgeInputPolicy.Clear(false,k=>k==key));
  bool blocked=false;try{Native.ReceiverStrokePlan(119,6);}catch(InvalidDataException){blocked=true;}check("legacy modifier stroke rejected",blocked);
  check("extended allows simultaneous movement and mouse",BridgeInputPolicy.Clear(true,k=>new[]{1,2,65,87}.Contains(k)));
  foreach(int key in new[]{16,17,18,91,92,160,161,162,163,164,165,112,123,124,130,135})
   check("communication conflict remains blocked "+key,!BridgeInputPolicy.Clear(true,k=>k==key));
  check("unmodified stroke never releases user movement",Native.ReceiverStrokePlan(124,0).SequenceEqual(new[]{((ushort)124,false),((ushort)124,true)}));
  p.bridgeDataKeys[0]=new BridgeKey(126,6);check("modified extended key never enables permissive policy",!BridgeInputPolicy.Extended(p));p.bridgeDataKeys[0]=new BridgeKey(124,0);check("overlapping extended key never enables permissive policy",!BridgeInputPolicy.Extended(p));
  var standard=new Packet{protocol=8,bridgeTransport="keys2-v1",bridgeOpenKey=119,bridgeExecuteKey=120,bridgeDataKeys=new[]{121,122,123,117}.Select(k=>new BridgeKey(k,0)).ToArray()};
  check("six standard keys validated without modifiers",BridgeInputPolicy.Extended(standard));
  check("standard stream key events remain ordinary F keys",Native.ReceiverStrokePlan(119,0).SequenceEqual(new[]{((ushort)119,false),((ushort)119,true)}));
  standard.bridgeDataKeys[0]=new BridgeKey(121,6);check("standard modifiers rejected",!BridgeInputPolicy.Extended(standard));
  string wire=BridgeEnvelope.Create("12345",1,"ping 12345 on 0 0").text;
  var q=BridgeInputPolicy.Symbols(wire,true,4).ToArray();
  string qr=new(q.Chunk(4).Select(a=>(char)(a[0]*64+a[1]*16+a[2]*4+a[3])).ToArray());
  check("four-symbol ASCII envelope roundtrip",qr==wire&&q.All(x=>x>=0&&x<4));
  var symbols=BridgeInputPolicy.Symbols(wire,true).ToArray();
  string restored=new(symbols.Chunk(3).Select(a=>(char)(a[0]*64+a[1]*8+a[2])).ToArray());
  check("three-bit ASCII envelope roundtrip",restored==wire&&symbols.All(x=>x is >=0 and <=7));
  File.WriteAllText(Path.Combine(root,"verification","octal-fixture.json"),JsonSerializer.Serialize(new{wire,symbols}));
  check("signal is speaker-initiated not an acknowledgement",ChatApi.TaskInstruction(new Packet{generationMode="signal",text="看这里"}).Contains("主动招呼别人"));
 }
}
