-- Local-only comparison statistics. No AI, chat sending, target changes or key input.
local A=DFY
local N={cache={},queue={},queued={},members={},epoch=0,nextQuery=0,blockedUntil=0}
A.NeedStats=N
local function readable(v) return type(issecretvalue)~="function" or not issecretvalue(v) end
local function safe(fn,...)
 if type(fn)~="function" then return nil end
 local ok,v,w=pcall(fn,...)
 if not ok or not readable(v) or not readable(w) then return nil end
 return v,w
end
local function guid(unit)
 if safe(UnitIsPlayer,unit)~=true then return nil end
 local g=safe(UnitGUID,unit)
 return type(g)=="string" and g~="" and g or nil
end
local function name(unit)
 local n,r=safe(UnitFullName,unit)
 if type(n)~="string" then return "未知角色" end
 return (n..(type(r)=="string" and r~="" and "-"..r or "")):gsub("|","/")
end
function N.Number(v)
 if not readable(v) then return nil end
 if type(v)=="string" then
  -- A dash/empty/hidden statistic is unknown, never a fabricated zero.
  if not v:match("^%d+$") then
   if not v:match("^%d[%d,]*%d$") or v:find(",,",1,true) then return nil end
   local index=0
   for part in v:gmatch("[^,]+") do index=index+1;if (index==1 and #part>3) or (index>1 and #part~=3) then return nil end end
  end
  v=tonumber((v:gsub(",","")))
 end
 if type(v)~="number" or v~=v or v<0 or v==math.huge or v~=math.floor(v) then return nil end
 return v
end
function N.Calculate(a,b,c)
 a,b,c=N.Number(a),N.Number(b),N.Number(c)
 if not a or not b or not c then return nil end
 return {runs=a,need=b,greed=c,rate=b+c>0 and b/(b+c)*100 or nil,average=a>0 and b/a or nil,
  warn=a>0 and b+c>0 and b/(b+c)>0.5 and b/a>3}
end
local function available()
 return type(SetAchievementComparisonUnit)=="function" and type(GetComparisonStatistic)=="function"
  and C_Timer and type(C_Timer.After)=="function"
end
local function tipGUID(tip)
 if not tip or not tip.GetUnit then return nil end
 local _,unit=safe(tip.GetUnit,tip)
 return type(unit)=="string" and guid(unit) or nil
end
local function lines(entry)
 local s=entry and entry.stats
 if not s then return "大肥鱼："..(entry and entry.reason or "需求统计查询中…"),"统计项 932 / 1044 / 1043；缺失数据不判定" end
 return string.format("大肥鱼：需求率 %s · 场均需求 %s",s.rate and string.format("%.2f%%",s.rate) or "未知",s.average and string.format("%.2f",s.average) or "未知"),
  string.format("副本：%d · 需求：%d · 贪婪：%d",s.runs,s.need,s.greed)
end
function N.Render(g)
 local tip=GameTooltip
 if not tip or tipGUID(tip)~=g or (tip.IsShown and not tip:IsShown()) then return end
 local first,second=lines(N.cache[g])
 if tip.dfyNeedGUID~=g then
  tip.dfyNeedGUID=g
  tip:AddLine(first,1,0.82,0,true);local index=tip:NumLines()
  tip:AddLine(second,0.75,0.75,0.75,true)
  tip.dfyNeedLine=index
 else
  local prefix=tip:GetName();local index=tip.dfyNeedLine
  local left=prefix and index and _G[prefix.."TextLeft"..index]
  local lower=prefix and index and _G[prefix.."TextLeft"..(index+1)]
  if left and lower then left:SetText(first);lower:SetText(second) end
 end
 tip:Show()
end
local function warn(g,entry,epoch)
 local member=N.members[g];local s=entry and entry.stats
 if not member or member.epoch~=epoch or member.warned or not s or not s.warn then return end
 if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
  member.warned=true
  DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9933【大肥鱼·本地提醒】%s：需求率 %.2f%%，场均需求 %.2f 次（副本 %d / 需求 %d / 贪婪 %d）。两项均超过阈值；历史累计统计仅供参考，不代表本场行为。|r",member.name,s.rate,s.average,s.runs,s.need,s.greed))
 end
end
local function put(g,entry)
 entry.time=GetTime();N.cache[g]=entry
 local count,oldest,when=0,nil,math.huge
 for k,v in pairs(N.cache) do count=count+1;if v.time<when then oldest,when=k,v.time end end
 if count>128 and oldest then N.cache[oldest]=nil end
end
local function cached(g)
 local e=N.cache[g]
 return e and GetTime()-e.time<(e.stats and 300 or 20) and e or nil
end
local function wake(delay)
 if N.scheduled or not available() then return end
 N.scheduled=true
 C_Timer.After(delay or 0,function() N.scheduled=false;N.Pump() end)
end
function N.Enqueue(unit,epoch)
 local g=guid(unit)
 if not g or g==guid("player") then return end
 local entry=cached(g)
 if entry then warn(g,entry,epoch);return end
 if N.pending and N.pending.guid==g then
  if epoch then N.pending.epoch=epoch end
  return
 end
 if N.queued[g] then if epoch then N.queued[g].epoch=epoch end;return end
 if #N.queue>=64 then return end
 local q={unit=unit,guid=g,epoch=epoch};N.queued[g]=q;N.queue[#N.queue+1]=q;wake(0)
end
local function unitFor(q)
 if guid(q.unit)==q.guid then return q.unit end
 local m=N.members[q.guid]
 if m and guid(m.unit)==q.guid then return m.unit end
 if guid("mouseover")==q.guid then return "mouseover" end
end
function N.Pump()
 if N.pending or #N.queue==0 or not available() then return end
 if AchievementFrame and AchievementFrame.IsShown and AchievementFrame:IsShown() then wake(1);return end
 local delay=math.max(N.nextQuery,N.blockedUntil)-GetTime()
 if delay>0 then wake(delay);return end
 local q=table.remove(N.queue,1);N.queued[q.guid]=nil
 local unit=unitFor(q)
 if not unit then wake(0);return end
 N.pending=q;N.nextQuery=GetTime()+1;N.ownRequest=true
 local ok,result=pcall(SetAchievementComparisonUnit,unit)
 N.ownRequest=false
 if not ok or (readable(result) and result==false) then
  N.pending=nil;put(q.guid,{reason="统计不可用"});N.Render(q.guid);wake(1);return
 end
 C_Timer.After(5,function()
  if N.pending==q then N.pending=nil;put(q.guid,{reason="查询超时，暂无法判断"});N.Render(q.guid);wake(0) end
 end)
end
function N.Ready(g)
 if not readable(g) then return end
 local q=N.pending
 if not q or type(g)~="string" or g~=q.guid then return end
 if not unitFor(q) then N.pending=nil;wake(0);return end
 local a=safe(GetComparisonStatistic,932);local b=safe(GetComparisonStatistic,1044);local c=safe(GetComparisonStatistic,1043)
 local stats=N.Calculate(a,b,c)
 N.pending=nil;put(g,{stats=stats,reason="统计未公开或不可用"});N.Render(g);warn(g,N.cache[g],q.epoch);wake(0)
end
function N.Roster()
 local list={};local raid=safe(IsInRaid)==true
 local count=safe(GetNumGroupMembers) or 0
 if type(count)~="number" then return end
 for i=1,math.min(raid and count or math.max(0,count-1),raid and 40 or 4) do
  local unit=(raid and "raid" or "party")..i;local g=guid(unit)
  if g and g~=guid("player") then
   local m=N.members[g]
   if not m then N.epoch=N.epoch+1;m={epoch=N.epoch,name=name(unit)} end
   m.unit=unit;list[g]=m
  end
 end
 N.members=list
 for _,m in pairs(list) do N.Enqueue(m.unit,m.epoch) end
end
function N.Tooltip(tip)
 local g=tipGUID(tip)
 if not g then return end
 if g==guid("player") then
  put(g,{stats=N.Calculate(safe(GetStatistic,932),safe(GetStatistic,1044),safe(GetStatistic,1043)),reason="自身统计不可用"});N.Render(g);return
 end
 if N.cache[g] and not cached(g) then N.cache[g]=nil end
 if not available() then put(g,{reason="客户端不支持统计查询"}) end
 local _,unit=safe(tip.GetUnit,tip)
 N.Render(g)
 if available() then N.Enqueue(unit) end
end
local frame=CreateFrame("Frame");N.frame=frame
for _,event in ipairs({"PLAYER_ENTERING_WORLD","GROUP_ROSTER_UPDATE","INSPECT_ACHIEVEMENT_READY"}) do pcall(frame.RegisterEvent,frame,event) end
frame:SetScript("OnEvent",function(_,event,g)
 if event=="INSPECT_ACHIEVEMENT_READY" then N.Ready(g) else N.Roster() end
end)
if type(hooksecurefunc)=="function" and type(SetAchievementComparisonUnit)=="function" then
 hooksecurefunc("SetAchievementComparisonUnit",function()
  if N.ownRequest then return end
  -- Other addons/the achievement UI own this shared API now; never consume their response.
  local q=N.pending;N.pending=nil;N.blockedUntil=GetTime()+5
  if q then
   put(q.guid,{reason="其他比较查询正在使用，稍后再查看"});N.Render(q.guid)
   if not N.queued[q.guid] then N.queued[q.guid]=q;table.insert(N.queue,1,q) end
  end
  if #N.queue>0 then wake(5) end
 end)
end
if GameTooltip and GameTooltip.HookScript then
 GameTooltip:HookScript("OnTooltipCleared",function(t) t.dfyNeedGUID=nil;t.dfyNeedLine=nil end)
 local ok=pcall(GameTooltip.HookScript,GameTooltip,"OnTooltipSetUnit",N.Tooltip)
 if not ok and TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit,N.Tooltip)
 end
end
