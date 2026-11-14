"""Offline Lua 5.1 startup/route regression; requires lupa (no game or API)."""
from pathlib import Path
import argparse
import json
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, required=True)
parser.add_argument('--core', type=Path)
parser.add_argument('--deps', type=Path)
args = parser.parse_args()
if args.deps:
    sys.path.insert(0, str(args.deps))
from lupa.lua51 import LuaRuntime
sys.stdout.reconfigure(encoding='utf-8')
checks = []

def fresh(saved='PARTY', enabled=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(Path(__file__).with_name('wow_mock.lua').read_text(encoding='utf-8-sig'))
    lua.globals().saved = saved
    lua.globals().enabled = enabled
    lua.execute('DFY_DB={transportVersion=8,masterAuto=enabled,auto=enabled,whisperAuto=true,selected={PARTY=true,GUILD=false},targetKey=saved};function IsInGroup() return true end')
    addon = args.root / 'addon/DaFeiYu'
    for name in (addon / 'DaFeiYu.toc').read_text(encoding='utf-8-sig').splitlines():
        if name.endswith('.lua'):
            path = args.core if name == 'Core.lua' and args.core else addon / name
            lua.execute(path.read_text(encoding='utf-8-sig'))
    lua.execute('DFY.Start()')
    return lua, lua.globals().DFY

def check(name, condition):
    if not condition:
        print(json.dumps({'failed': name, 'passed': len(checks)}, ensure_ascii=False))
        sys.exit(2)
    checks.append(name)

lua, a = fresh()
print(json.dumps({'savedTarget': 'PARTY', 'target': a.db.targetKey, 'current': a.current,
                  'saySelected': a.db.selected.SAY, 'sent': len(lua.globals().sent)}, ensure_ascii=False))
check('startup resets saved PARTY to SAY', a.db.targetKey == 'SAY' and a.current == 'SAY' and a.db.selected.SAY)
for saved in ('CHANNEL:1:综合', 'WHISPER:好友', 'BN_WHISPER:123', None):
    lua, a = fresh(saved)
    check('startup resets ' + str(saved), a.db.targetKey == 'SAY' and a.current == 'SAY' and a.channels.SAY.type == 'SAY')
    check('startup succeeds without chat ' + str(saved), len(a.startupErrors) == 0 and len(lua.globals().sent) == 0)
    check('preserves monitoring/auto ' + str(saved), a.db.selected.PARTY and a.db.selected.GUILD == False and a.db.auto == False and a.db.masterAuto == False and a.db.whisperAuto)
    a.SeedDockChannels()
    a.DockSelectChannel('PARTY', False)
    a.Refresh(); a.SeedDockChannels(); a.Start()
    check('manual PARTY survives refresh ' + str(saved), a.current == 'PARTY' and a.db.targetKey == 'PARTY' and a.SignalChannel() == 'PARTY')
    a.Init()
    check('new initialization resets SAY ' + str(saved), a.current == 'SAY' and a.db.targetKey == 'SAY' and a.SignalChannel() == 'SAY')
lua, a = fresh(enabled=True)
check('enabled automation preserved', a.db.auto and a.db.masterAuto)
a.SeedDockChannels()
check('public destination SAY only', a.PublicRouteAllowed(a.channels.SAY) and not a.PublicRouteAllowed(a.channels.PARTY))
lua.execute("chat('PARTY','你好','队友'); chat('WHISPER','你好','好友')")
check('incoming messages do not hijack SAY', a.current == 'SAY' and a.db.targetKey == 'SAY')
for typ, target in [('WHISPER', '好友'), ('BN_WHISPER', 123)]:
    lua.globals().kind = typ; lua.globals().recipient = target
    lua.execute('local key=kind..":"..tostring(recipient);DFY.channels[key]={key=key,type=kind,name="好友",target=recipient,messages={{speaker="好友",text="你好"}}};DFY.pending=nil;DFY.lastBridge=GetTime();DFY.status="IDLE";DFY.Generate(key,true,nil,"whisper")')
    check(typ + ' generation retains private recipient', a.pending and a.pending.channel.type == typ and a.pending.channel.target == target)
    check(typ + ' does not change public default', a.current == 'SAY' and a.db.targetKey == 'SAY')
check('no chat sent by test', len(lua.globals().sent) == 0)
print(json.dumps({'passed': len(checks), 'checks': checks, 'scope': 'offline Lua mock'}, ensure_ascii=False))
