namespace WhaleChat;

// Testable SendInput boundary. No blanket key-up on pause, focus loss or exit.
internal static class BridgeStrokeWriter
{
 internal static void Write((ushort key,bool up)[] plan,Func<(ushort key,bool up)[],(int count,int error)> send)
 {
  if(plan.Length==0||plan.Length>64||plan.Length%2!=0)throw new InvalidDataException("Invalid stroke batch");
  for(int i=0;i<plan.Length;i+=2)
   if(!BridgeInputPolicy.AllowedKey(plan[i].key)||plan[i].up||!plan[i+1].up||plan[i].key!=plan[i+1].key)
    throw new InvalidDataException("Only paired unmodified approved keys allowed");
  var result=send(plan);
  if(result.count==plan.Length)return;
  string cleanup="none";
  // SendInput inserts an ordered prefix. Only an odd prefix leaves our last key down.
  // No other key, modifier, mouse button or movement key is ever released here.
  if(result.count>0&&result.count<plan.Length&&result.count%2==1) {
   var released=send(new[]{(plan[result.count-1].key,true)});
   cleanup=$"key={plan[result.count-1].key} count={released.count} error={released.error}";
  }
  throw new InvalidOperationException($"SendInput partial: {result.count}/{plan.Length}; error={result.error}; release={cleanup}");
 }
}
