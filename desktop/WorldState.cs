using System.Text.Json;
using System.Text.RegularExpressions;
namespace WhaleChat;

public sealed class WorldState
{
    public string group { get; set; } = "unknown";
    public string instance { get; set; } = "unknown";
    public string peerInGroup { get; set; } = "unknown";
    public string zone { get; set; } = "";
}
public static class WorldStateReplies
{
    public static string Guidance(Packet p) => "\n当前客户端实测状态（不是聊天消息）："+JsonSerializer.Serialize(p.worldState??new WorldState())+
        "。group=party表示已在小队、raid表示团队、solo表示未组队；instance=party/raid/scenario表示已进入相应副本，none表示不在副本，pvp/arena表示战场/竞技场，inside表示已在实例内但类型未知，unknown表示读不到。组队不等于进本；zone仅是实际区域名。当前状态优先于旧对话和历史草稿；未知不能说成没有。peerInGroup=yes只表示经客户端核实这位私聊者已在同一队，no表示不在，unknown表示未确认；不能只因自己组队就推定对方在队。蹭不是蹲；游戏中“蹭下”通常是请求共享帐篷效果、位面或组队便利，具体目的未说明时问清；已入队则顺势友好接纳，不重复质问对方或装作拒绝。对陌生人礼貌克制，嘴硬是轻松语气，不索要鱼干、报酬或感谢作为条件。人设里的馋只可轻轻自嘲，不凌驾实际对话意图。不承诺入队、退队、带本、交易或行动，未提供的装备、任务和战况不要编造。";

    // Only direct present-state questions, never invitations, history or other people's status.
    public static bool TryAnswer(Packet p, out string reply)
    {
        reply="";
        if(p.generationMode is not ("whisper" or "public" or "reply"))return false;
        string t=Regex.Replace(p.text??"",@"\s+","").Trim('？','?','。','！','!','，',',');
        if(p.generationMode=="whisper" && Regex.IsMatch(t,@"^(?:(?:哥|老哥|大佬|老板|兄弟)[，,]*)?蹭(?:下|一下)(?:呗|哈|嘛|可以吗|行吗|谢谢)?$")) {
            reply=p.worldState?.peerInGroup=="yes" ? "进队啦，别跟本鲸客气。" : "你是想蹭帐篷还是换个位面呀？";
            return true;
        }
        bool dungeon=Regex.IsMatch(t,@"^(?:你|你们)?(?:已经|现在)?(?:进本|进副本|进地下城|进去了|进本了|进副本了|进地下城了|在本里|在副本里|到本里)(?:了)?(?:吗|么|没|没啊|没有|了吗|了么|了没|了没有)$");
        bool party=Regex.IsMatch(t,@"^(?:你|你们)?(?:现在)?(?:有队|有队伍|组队|进队|在队里|在队伍里)(?:了)?(?:吗|么|没|没有|了吗|了么|了没|了没有)$");
        if(!dungeon&&!party)return false;
        var s=p.worldState??new WorldState();
        bool grouped=s.group is "party" or "raid";
        if(party) {
            reply=s.group switch {"party"=>"我已经在小队里啦，鲸鲸可没掉队。","raid"=>"我已经在团队里啦，鲸鲸可没掉队。","solo"=>"我现在还没组队呢，你找鲸鲸啥事？",_=>"你是问我现在有没有队吗？我先确认下。"};
        } else {
            reply=s.instance switch {
                "party" or "raid" or "scenario"=>"已经在本里啦，鲸鲸可没掉队。",
                "inside"=>"我已经进实例区域啦，你问的是哪个本呀？",
                "none"=>grouped?"我在队里呢，还没进副本。":"我现在还没进副本呢，你问哪个本呀？",
                "pvp"=>"我这会儿在战场里，你问的是哪个本呀？",
                "arena"=>"我这会儿在竞技场里，你问的是哪个本呀？",
                _=>grouped?"我在队里呢，你问我进哪个本呀？":"你问的是哪个本呀？我先确认下。"};
        }
        return true;
    }
}
