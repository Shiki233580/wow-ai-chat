DFY={}; now=0; timers={}; requests={}; messages={}; transmitted=0; groupCount=0; raid=false
units={player={guid='self',name='本人'},mouseover={guid='A',name='甲'},party1={guid='A',name='甲'},party2={guid='B',name='乙'}}
stats={[932]='10',[1044]='40',[1043]='10'}; reads=0
function GetTime() return now end
function UnitIsPlayer(u) return units[u]~=nil end
function UnitGUID(u) return units[u] and units[u].guid end
function UnitFullName(u) return units[u] and units[u].name,'测试服' end
function GetNumGroupMembers() return groupCount end
function IsInRaid() return raid end
function SendChatMessage() transmitted=transmitted+1 end
function SetAchievementComparisonUnit(u) requests[#requests+1]=u;return true end
function GetComparisonStatistic(id) reads=reads+1;return stats[id] end
function GetStatistic(id) return stats[id] end
function hooksecurefunc(n,fn) local old=_G[n];_G[n]=function(...) local r=old(...);fn(...);return r end end
C_Timer={After=function(s,f) timers[#timers+1]={at=now+s,fn=f} end}
function advance(s)
 local finish=now+s;local loops=0
 while true do
  local at,index=math.huge,nil
  for i,t in ipairs(timers) do if t.at<=finish and t.at<at then at,index=t.at,i end end
  if not index then break end
  now=at;local t=table.remove(timers,index);t.fn();loops=loops+1;assert(loops<500,'timer storm')
 end
 now=finish
end
function CreateFrame()
 return {RegisterEvent=function() end,SetScript=function(self,k,f) self[k]=f end}
end
DEFAULT_CHAT_FRAME={AddMessage=function(_,m) messages[#messages+1]=m end}
GameTooltip={unit='mouseover',lines={},shown=true,hooks={}}
function GameTooltip:GetUnit() return '角色',self.unit end
function GameTooltip:IsShown() return self.shown end
function GameTooltip:GetName() return 'GameTooltip' end
function GameTooltip:NumLines() return #self.lines end
function GameTooltip:AddLine(t)
 self.lines[#self.lines+1]=t;local i=#self.lines
 _G['GameTooltipTextLeft'..i]={SetText=function(_,text) self.lines[i]=text end}
end
function GameTooltip:Show() self.shown=true end
function GameTooltip:HookScript(k,f) self.hooks[k]=f end
function hover(u)
 GameTooltip.unit=u;GameTooltip.lines={};GameTooltip.shown=true
 if GameTooltip.hooks.OnTooltipCleared then GameTooltip.hooks.OnTooltipCleared(GameTooltip) end
 if GameTooltip.hooks.OnTooltipSetUnit then GameTooltip.hooks.OnTooltipSetUnit(GameTooltip) end
end
function ready(g) if DFY.NeedStats then DFY.NeedStats.Ready(g) end end
function roster() if DFY.NeedStats then DFY.NeedStats.Roster() end end
