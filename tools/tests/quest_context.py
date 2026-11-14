"""Offline task facts -> actual bridge packet -> reply/ACK regression."""
import argparse, base64, json, sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--deps',type=Path);p.add_argument('--packet',type=Path);args=p.parse_args()
if args.deps: sys.path.insert(0,str(args.deps))
from lupa.lua51 import LuaRuntime
sys.stdout.reconfigure(encoding='utf-8'); checks=[]
def ck(name,ok):
    if not ok: print(json.dumps({'failed':name,'passed':len(checks)},ensure_ascii=False));sys.exit(2)
    checks.append(name)
def fresh():
    l=LuaRuntime(unpack_returned_tuples=True)
    l.execute(Path(__file__).with_name('wow_mock.lua').read_text(encoding='utf-8-sig'))
    l.execute('''
DFY_DB={transportVersion=8,masterAuto=true,auto=true,activityAuto=true}
dialogID=7; completed=false; description="村里的狼太多，请收集狼尾巴。";objective="收集8条狼尾巴";reads=0
C_QuestLog={GetNumQuestLogEntries=function()return 1 end,GetInfo=function()return {title="清理狼群",questID=7,isComplete=completed} end,GetTitleForQuestID=function(id)return "任务"..id end}
function GetQuestID()return dialogID end
function GetTitleText()return "清理狼群" end
function GetQuestText()reads=reads+1;return description end
function GetObjectiveText()return objective end
function GetNumQuestRewards()return 0 end
function GetNumQuestChoices()return 2 end
function GetQuestItemInfo(_,i)return i==1 and "软皮靴" or "布手套",nil,1 end
function GetRewardMoney()return 300 end
''')
    for n in (args.root/'addon/DaFeiYu/DaFeiYu.toc').read_text(encoding='utf-8-sig').splitlines():
        if n.endswith('.lua'):l.execute((args.root/'addon/DaFeiYu'/n).read_text(encoding='utf-8-sig'))
    l.execute('DFY.Start();DFY.lastBridge=clock')
    return l,l.globals().DFY
def pump(l,a):
    l.globals().clock+=2.1;a.PumpActivities()
    if a.pending is None:
        l.globals().clock+=2.1;a.PumpActivities()
    return json.loads(a.Packet())
def clear(a): a.pending=None;a.status='IDLE'

l,a=fresh();a.ActivityEvent('QUEST_DETAIL');a.ActivityEvent('QUEST_ACCEPTED',7)
packet=pump(l,a);print(json.dumps({'scenario':'accept wolves, offered shoes/gloves and 300 copper','text':packet.get('text')},ensure_ascii=False))
ck('task objective transmitted', '收集8条狼尾巴' in packet.get('text',''))
ck('task description transmitted','村里的狼太多' in packet['text'])
ck('offers identified as unreceived choices',all(s in packet['text'] for s in ['展示奖励（非领取凭据）','候选非全得:软皮靴','布手套','300铜']))
ck('only persona prefix/no fixed task notice',packet['eventReply']=='' and packet['eventFlavor'] and packet['replyPrefix']=='【大肥鱼】')
ck('SAY remains default',packet['channel']=='SAY')
clear(a);l.globals().completed=True;a.ActivityEvent('QUEST_LOG_UPDATE');packet=pump(l,a)
ck('complete retains content and not turned in','尚未交付' in packet['text'] and '狼尾巴' in packet['text'])
clear(a);a.ActivityEvent('QUEST_COMPLETE');l.globals().dialogID=99
a.ActivityEvent('QUEST_TURNED_IN',7,1000,300);a.ActivityEvent('QUEST_LOOT_RECEIVED',7,'|Hitem:123|h[软皮靴]|h',1)
packet=pump(l,a)
ck('turn-in and loot one job',a.pending.activityCount==1)
ck('actual rewards and cached content transmitted',all(s in packet['text'] for s in ['实际获得金钱：300铜','任务已领取物品奖励','软皮靴','收集8条狼尾巴']))
ck('turn-in does not read unrelated dialog',l.globals().reads==3)
if args.packet:args.packet.write_text(json.dumps(packet,ensure_ascii=False),encoding='utf-8')
reply='数完狼尾巴就给双鞋，哼，倒也没白跑。'
a.Receive(a.session,str(a.pending.id),base64.b64encode(reply.encode()).decode())
a.bridgeExecuting=True;a.Command('commit '+a.session+' '+str(a.pending.id));a.bridgeExecuting=False
ck('one simulated send with persona prefix',len(l.globals().sent)==1 and l.globals().sent[1].text=='【大肥鱼】'+reply)
a.Chat('CHAT_MSG_SAY','【大肥鱼】'+reply,'圣鲸鲸',None,None,None,None,None,None,None,None,None,'player-guid')
ck('send ACK clears preview',a.pending.confirmed and a.pending.reply is None)
a.ActivityEvent('QUEST_TURNED_IN',7,1000,300);a.ActivityEvent('QUEST_LOOT_RECEIVED',7,'|Hitem:123|h[软皮靴]|h',1);pump(l,a)
ck('duplicate reward events do not regenerate',a.pending.confirmed and len(l.globals().sent)==1)
l,a=fresh();l.execute('GetQuestID=nil;GetQuestText=nil;GetObjectiveText=nil;GetQuestItemInfo=nil')
a.ActivityEvent('QUEST_ACCEPTED',7);packet=pump(l,a)
ck('missing APIs safe known-stage fallback','已接取任务' in packet['text'] and '狼尾巴' not in packet['text'] and '展示奖励' not in packet['text'])
l,a=fresh();a.ActivityEvent('QUEST_DETAIL');l.globals().dialogID=8;a.ActivityEvent('QUEST_ACCEPTED',9);packet=pump(l,a)
ck('wrong dialog never contaminates another task','狼尾巴' not in packet['text'])
l,a=fresh();l.execute('C_QuestLog.GetQuestObjectives=function(id)return {{text="护送村民"}} end;GetQuestID=nil')
a.ActivityEvent('QUEST_ACCEPTED',7);packet=pump(l,a)
ck('modern quest objective fallback','护送村民' in packet['text'])
l,a=fresh();l.execute('description=string.rep("长任务说明",5000);objective=string.rep("长目标",5000)')
a.ActivityEvent('QUEST_DETAIL');a.ActivityEvent('QUEST_ACCEPTED',7);packet=pump(l,a)
ck('bounded payload under pixel capacity',len(a.Packet().encode())<=6136 and len(packet['text'])<=460)
l,a=fresh();a.ActivityEvent('QUEST_DETAIL')
for i in range(1,41):a.ActivityEvent('QUEST_ACCEPTED',i)
packet=pump(l,a);ck('forty tasks produce one batch',a.pending.activityCount==40 and packet['eventKind']=='batch')
ck('batch retains a meaningful task detail','收集8条狼尾巴' in packet['text'])
request=a.pending.id;pump(l,a);ck('no repeated generation while pending',a.pending.id==request)
l,a=fresh();a.db.masterAuto=False;a.ActivityEvent('QUEST_DETAIL');a.ActivityEvent('QUEST_ACCEPTED',7);pump(l,a)
ck('auto off never queues task',a.pending is None)
l,a=fresh();a.ActivityEvent('QUEST_DETAIL');a.ActivityEvent('QUEST_ACCEPTED',7);a.ActivityEvent('TRADE_SKILL_SHOW');pump(l,a)
ck('craft window still blocks generation',a.pending is None)
a.ActivityEvent('TRADE_SKILL_CLOSE');packet=pump(l,a);ck('craft close resumes single batch',packet['eventKind']=='accept')
l,a=fresh()
for i in range(1,131):l.globals().dialogID=i;a.ActivityEvent('QUEST_DETAIL')
l.globals().dialogID=999;a.ActivityEvent('QUEST_ACCEPTED',1);packet=pump(l,a)
ck('old snapshots evicted at cache bound','狼尾巴' not in packet['text'])
print(json.dumps({'passed':len(checks),'checks':checks,'scope':'mock game/API, no real chat'},ensure_ascii=False))
