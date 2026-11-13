-- Local player activity facts only. Event queue is not a message cooldown.
local A=DFY
local labels={accept="接取任务",complete="完成目标",reward="交付/奖励",equipment="Roll / 任务装备"}
local queue,seen,seenOrder,quests,titles,waitingItems={},{},{},{},{},{}
local serial=0
local seenCursor=1
-- Aggregate one burst after it becomes quiet; never a post-send cooldown or quota.
local batchChangedAt=0
local scanDirty=false
local scanDue=0
local batchQuietSeconds=2
local function safe(v) return not (type(issecretvalue)=="function" and issecretvalue(v)) end
local function plain(s) return tostring(s or ""):gsub("|cn[%w_]+:",""):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("|H.-|h(.-)|h","%1"):gsub("[\r\n|]"," ") end
-- Fixed factual notices; names stay intact unless a very long label needs explicit ellipsis.
local function itemName(link)
 return plain(link:match("|Hitem:.-|h%[(.-)%]|h") or link):match("^%s*(.-)%s*$"):gsub("^%[",""):gsub("%]$","")
end
local function label(name,maxBytes)
 local value=itemName(name);local cap=maxBytes or 96
 if #value>cap then
  local n=32;while n>0 and #A.Cut(value,n)>cap-3 do n=n-1 end
  value=A.Cut(value,n).."…"
 end
 return "【"..value.."】"
end
local function addNotice(q,notice,details)
 if details then
  q.rewardTitle=details.rewardTitle or q.rewardTitle;q.rewardTurned=details.rewardTurned or q.rewardTurned
  if details.rewardItem then q.rewardItems=q.rewardItems or {};local found=false;for _,n in ipairs(q.rewardItems) do if n==details.rewardItem then found=true end end;if not found then q.rewardItems[#q.rewardItems+1]=details.rewardItem end end
 end
 if not notice then return end
 q.notices=q.notices or {}
 for _,n in ipairs(q.notices) do if n==notice then return end end
 q.notices[#q.notices+1]=notice
end
local function batchNotice(batch)
 local parts,used={},{}
 local function add(text) if not used[text] then parts[#parts+1]=text;used[text]=true end end
 for _,q in ipairs(batch) do
  if q.rewardTitle then
   if q.rewardItems and #q.rewardItems>0 then
    local last=q.rewardItems[#q.rewardItems]
    local text=label(q.rewardTitle,40)..(q.rewardTurned and "已交付，获得" or "奖励：获得")..label(last,40).."！"
    if #q.rewardItems>1 then text=text.."另"..(#q.rewardItems-1).."件。" end
    add(text)
   else add(label(q.rewardTitle).."已交付！") end
  else for _,n in ipairs(q.notices or {}) do add(n) end end
 end
 local text=table.concat(parts," ")
 if #text<=140 then return text end
 local last=parts[#parts] or "事件已完成！";local suffix="另"..(#parts-1).."项。"
 if #last+ #suffix<=140 then return last..suffix end
 return #last<=140 and last or "本批事件已完成！"
end
local function note(t) A.activityDiagnostic=t; if A.activityStatus then A.activityStatus:SetText(t) end end
local function call(fn,...) if type(fn)~="function" then return nil end; local ok,a,b,c,d,e,f,g,h,i,j,k,l,m=pcall(fn,...); if ok then return a,b,c,d,e,f,g,h,i,j,k,l,m end end
local function title(id,index)
 local n=call(C_QuestLog and C_QuestLog.GetTitleForQuestID,id)
 if not n and index then n=call(GetQuestLogTitle,index) end
 if type(n)=="string" and n~="" then titles[id]=plain(n) end
 return titles[id] or ("任务编号"..tostring(id))
end
function A.ActivityInit()
 local d=A.db; if d.activityAuto==nil then d.activityAuto=false end
 d.activities=d.activities or {}; for k in pairs(labels) do if d.activities[k]==nil then d.activities[k]=true end end
 A.ActivityScan(true)
end
-- A profession session is an input-exclusive operation, not a chat rate limit.
local professionOpen={}
function A.ProfessionBusy()
 if next(professionOpen) then return true end
 for _,name in ipairs({"TradeSkillFrame","CraftFrame","ProfessionsFrame"}) do
  local f=_G[name];if f and type(f.IsShown)=="function" and call(f.IsShown,f) then return true end
 end
 if type(UnitCastingInfo)=="function" then local _,_,_,_,_,craft=call(UnitCastingInfo,"player");if craft==true then return true end end
 return false
end
local function enabled(kind) return A.MasterAutoEnabled() and A.db and A.db.activityAuto and A.db.activities[kind] end
function A.ActivityEnabled(kind)
 if kind~="batch" then return enabled(kind)==true end
 local p=A.pending
 if not A.MasterAutoEnabled() or not A.db.activityAuto or not p or not p.activityKinds then return false end
 for k in pairs(p.activityKinds) do if not enabled(k) then return false end end
 return true
end
local function remember(key)
 if seen[key] then return end
 if #seenOrder<2048 then seenOrder[#seenOrder+1]=key
 else seen[seenOrder[seenCursor]]=nil;seenOrder[seenCursor]=key;seenCursor=seenCursor%2048+1 end
 seen[key]=true
end
local function ensure(key)
 if not A.channels[key] then local names={SAY="说",PARTY="小队",RAID="团队",INSTANCE_CHAT="副本队伍"}; A.channels[key]={key=key,type=key,name=names[key] or key,messages={}}; A.order[#A.order+1]=key end
end
function A.QueueActivity(kind,key,fact,itemID,quantity,notice,details)
 if not enabled(kind) then return end
 for _,q in ipairs(queue) do if q.key==key then if not q.fact:find(fact,1,true) then q.fact=q.fact.."；"..fact;batchChangedAt=GetTime() end;addNotice(q,notice,details); return end end
 if seen[key] then return end
 local route=A.SignalChannel(); if not route then note("事件未排入：所选频道不可用"); return end
 ensure(route); remember(key)
 queue[#queue+1]={kind=kind,key=key,fact=fact,route=route,itemID=itemID,quantity=quantity}
 addNotice(queue[#queue],notice,details)
 batchChangedAt=GetTime();note("合并事件中 · "..#queue.." 项，操作结束后说一句")
end
function A.ClearActivityWork() queue={};waitingItems={};scanDirty=false;A.activityReseed=true end
function A.PumpActivities()
 if not A.MasterAutoEnabled() then A.ClearActivityWork();return end
 if not A.db or A.ProfessionBusy() then return end
 -- QUEST_LOG_UPDATE may fire many times in one frame. Only scan once per update slice.
 if scanDirty and GetTime()>=scanDue then scanDirty=false;A.ActivityScan(false);scanDue=GetTime()+0.25 end
 if #queue==0 or GetTime()-batchChangedAt<batchQuietSeconds then return end
 local p=A.pending
 if p and not p.confirmed then return end
 if A.lastBridge==0 or GetTime()-A.lastBridge>75 then return end
 local route=A.SignalChannel();local batch={};local counts={};local kinds={};local itemIDs={}
 for _,q in ipairs(queue) do
  if enabled(q.kind) and q.route==route then
   if q.itemID then itemIDs[q.itemID]=true end;batch[#batch+1]=q;counts[q.kind]=(counts[q.kind] or 0)+1;kinds[q.kind]=true
  end
 end
 queue={}
 if #batch==0 then note("已取消旧事件：开关或回复目标已变化");return end
 local fact,kind
 if #batch==1 then fact=batch[1].fact;kind=batch[1].kind
 else
  local parts={}
  for _,k in ipairs({"accept","complete","reward","equipment"}) do if counts[k] then parts[#parts+1]=labels[k]..counts[k].."项" end end
  fact="连续操作合并："..table.concat(parts,"、").."。只总结一句心情，不逐项报数、不逐条发言。最后一项事实："..A.Cut(batch[#batch].fact,65)
  kind="batch"
 end
 A.Generate(route,true,A.Cut("已发生的本人游戏事件："..fact,160),"event",kind)
 if A.pending and A.pending.mode=="event" and A.status=="GENERATING" then
  -- Native facts remain in the prompt; spoken output is only the persona sentence.
  A.pending.eventReply="";A.pending.eventFlavor=true;A.pending.activityKinds=kinds;A.pending.activityCount=#batch;A.pending.activityItems=itemIDs
  note("已合并 "..#batch.." 项 → "..A.pending.channel.name);A.Refresh()
 end
end
function A.SetActivityOption(kind,value)
 if kind=="master" then A.db.activityAuto=value else A.db.activities[kind]=value end
 for i=#queue,1,-1 do if not enabled(queue[i].kind) then table.remove(queue,i) end end
 local p=A.pending
 if p and p.mode=="event" and not p.submitted and not A.ActivityEnabled(p.eventKind) then A.Cancel() end
 note(A.db.activityAuto and "事件发言已开启，跟随所选回复频道" or "事件发言已关闭")
 if A.RenderActivityPanel then A.RenderActivityPanel() end; A.Refresh()
end
function A.ActivityScan(seed)
 if not A.MasterAutoEnabled() or A.activityReseed then seed=true end
 if A.ProfessionBusy() then scanDirty=true;return end
 local n=call(C_QuestLog and C_QuestLog.GetNumQuestLogEntries) or call(GetNumQuestLogEntries)
 if type(n)~="number" or not safe(n) then return end
 A.activityReseed=nil
 local present={}
 for i=1,n do
  local info=call(C_QuestLog and C_QuestLog.GetInfo,i)
  local name,_,_,header,_,complete,_,id
  if type(info)=="table" then name=info.title;header=info.isHeader;id=info.questID;complete=info.isComplete
  else name,_,_,header,_,complete,_,id=call(GetQuestLogTitle,i) end
  if safe(id) and type(id)=="number" and id>0 and not header and safe(complete) then
   if safe(name) and type(name)=="string" then titles[id]=plain(name) end
   local actual=call(C_QuestLog and C_QuestLog.IsComplete,id)
   if actual~=nil and safe(actual) then complete=actual end
   complete=complete==true or complete==1;present[id]=true
   local q=quests[id]
   if not q then q={cycle=0,complete=complete,active=true};quests[id]=q
   elseif not seed and not q.complete and complete then
    A.QueueActivity("complete","complete:"..id..":"..q.cycle,"任务目标已完成，尚未交付："..title(id,i),nil,nil,label(title(id,i)).."已完成！")
   end
   q.complete=complete; q.active=true
  end
 end
 for id,q in pairs(quests) do if not present[id] then q.active=false end end
end
-- Only native roll-winner formats authorize equipment speech. Ordinary loot,
-- bag moves, created/pushed items and roll selections are NOT provenance.
local rollFormats={
 {"LOOT_ROLL_YOU_WON",true},{"LOOT_ROLL_YOU_WON_NO_SPAM_NEED",true},
 {"LOOT_ROLL_YOU_WON_NO_SPAM_GREED",true},{"LOOT_ROLL_WON",false},
 {"LOOT_ROLL_WON_NO_SPAM_NEED",false},{"LOOT_ROLL_WON_NO_SPAM_GREED",false}
}
local formatCache={}
local function rollMatch(text)
 if not safe(text) or type(text)~="string" then return nil end
 for _,spec in ipairs(rollFormats) do
  local fmt=_G[spec[1]]
  if type(fmt)=="string" and fmt~="" then
   local cached=formatCache[spec[1]]
   if not cached or cached.format~=fmt then
    local parts,types,pos={},{},1
    local function escape(s) return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1")) end
    while pos<=#fmt do
     local first,last,typ=fmt:find("%%[0-9]*%$?([sd])",pos)
     if not first then parts[#parts+1]=escape(fmt:sub(pos));break end
     parts[#parts+1]=escape(fmt:sub(pos,first-1));parts[#parts+1]=typ=="d" and "(%d+)" or "(.-)"
     types[#types+1]=typ;pos=last+1
    end
    cached={format=fmt,pattern="^"..table.concat(parts).."$",types=types};formatCache[spec[1]]=cached
   end
   local matches={text:match(cached.pattern)}
   if #matches>0 then
    local link,winner
    for i,value in ipairs(matches) do
     if cached.types[i]=="s" then
      local item=value:match("(|Hitem:.-|h.-|h)")
      if item then link=item else winner=plain(value) end
     end
    end
    if link and (spec[2] or (winner and A.IsSelf(winner))) then return link end
   end
  end
 end
end
-- Bounded metadata cache, not a message cooldown. Unknown quality never speaks.
local itemCache,itemCacheOrder={},{}
local function cacheItem(link,fact)
 if itemCache[link]==nil then itemCacheOrder[#itemCacheOrder+1]=link end
 itemCache[link]=fact
 if #itemCacheOrder>256 then itemCache[table.remove(itemCacheOrder,1)]=nil end
 return fact
end
local function itemFacts(link)
 if itemCache[link]~=nil then return itemCache[link] end
 local name,_,quality,level,_,_,_,_,loc,_,_,classID=call(GetItemInfo,link)
 if not safe(quality) or type(quality)~="number" then return nil end
 if quality<3 then return cacheItem(link,false) end
 name=safe(name) and type(name)=="string" and name or link:match("%[(.-)%]")
 if not name then return nil end
 local equip=classID==2 or classID==4 or (type(loc)=="string" and loc~="" and loc~="INVTYPE_NON_EQUIP_IGNORE")
 if not equip or type(loc)~="string" or loc=="" or loc=="INVTYPE_NON_EQUIP_IGNORE" then return cacheItem(link,false) end
 local q=_G["ITEM_QUALITY"..quality.."_DESC"] or ({[3]="稀有",[4]="史诗",[5]="传说",[6]="神器",[7]="传家宝"})[quality] or tostring(quality)
 local fact="我刚获得"..(equip and "装备：" or "稀有物品：")..plain(name).."，品质："..q
 if equip then fact=fact..(type(level)=="number" and ("，物品等级："..level) or "").."。实际提升未评估" end
 return cacheItem(link,fact)
end
local function enqueueItem(entry)
 local facts=itemFacts(entry.link)
 if facts==nil then return false end
 if not facts then return true end
 facts=entry.source.."；"..facts
 local p=A.pending
 -- Additional copies cannot spawn a second job while this item's reply is in flight.
 if p and not p.confirmed and p.mode=="event" and p.activityItems and p.activityItems[entry.id] then return true end
 for _,q in ipairs(queue) do
  if q.kind=="equipment" and q.itemID==entry.id then
   q.quantity=(q.quantity or 1)+entry.quantity
   q.fact=(q.itemFact or facts).."，本批数量："..q.quantity
   batchChangedAt=GetTime();return true
  end
 end
 local groupKey="rare:"..entry.key
 A.QueueActivity("equipment",groupKey,facts.."，本批数量："..entry.quantity,entry.id,entry.quantity,"获得"..label(entry.link).."！")
 for _,q in ipairs(queue) do if q.key==groupKey then q.itemFact=facts;break end end
 return true
end
local function sourceItem(link,key,quantity,source)
 if not enabled("equipment") or seen[key] then return end
 local id=tonumber(link:match("item:(%d+)"));if not id then return end
 local entry={id=id,link=link,key=key,quantity=quantity,source=source}
 local waiting=waitingItems[id]
 if waiting then
  local _,first=next(waiting)
  if first then first.quantity=first.quantity+quantity;remember(key);return end
 end
 if not enqueueItem(entry) then
  waitingItems[id]={[key]=entry};call(C_Item and C_Item.RequestLoadItemDataByID,id);note("等待 Roll / 任务装备品质确认")
 end
 remember(key)
end
function A.ActivityEvent(event,...)
 if not A.db then return end
 if event=="TRADE_SKILL_SHOW" or event=="CRAFT_SHOW" then
  professionOpen[event=="TRADE_SKILL_SHOW" and "trade" or "craft"]=true
  A.queuedSignal=nil
  if A.CloseReceiver then A.CloseReceiver(true) end
  local p=A.pending
  if p and p.automatic and not p.submitted and (p.mode=="event" or p.mode=="signal") then A.Cancel() end
  note("专业窗口打开：不生成、不回传；关闭后合并任务变化")
  A.Refresh();return
 end
 if event=="TRADE_SKILL_CLOSE" or event=="CRAFT_CLOSE" then
  professionOpen[event=="TRADE_SKILL_CLOSE" and "trade" or "craft"]=nil
  scanDirty=true;batchChangedAt=GetTime();A.Refresh();return
 end
 if event=="PLAYER_ENTERING_WORLD" then professionOpen={};A.ActivityScan(true);return end
 if event=="QUEST_LOG_UPDATE" then scanDirty=true;return end
 if event=="QUEST_ACCEPTED" then
  local a,b=...;local id=type(b)=="number" and b or a;if not safe(id) or type(id)~="number" or id<=0 then return end
  local q=quests[id] or {cycle=0}; if q.acceptNotified and q.active and not q.turned then return end
  q.cycle=q.cycle+1;q.active=true;q.turned=false;q.complete=false;q.acceptNotified=true;quests[id]=q
  A.QueueActivity("accept","accept:"..id..":"..q.cycle,"我已接取任务："..title(id,type(b)=="number" and a or nil),nil,nil,"已接取"..label(title(id)).."！");return
 end
 if event=="QUEST_REMOVED" then local id=...;if safe(id) and quests[id] then quests[id].active=false;quests[id].acceptNotified=false end;return end
 if event=="QUEST_TURNED_IN" or event=="QUEST_LOOT_RECEIVED" then
  local id,b,c=...;if not safe(id) or type(id)~="number" then return end
  local q=quests[id] or {cycle=0};quests[id]=q
  local key="reward:"..id..":"..q.cycle
  if event=="QUEST_TURNED_IN" then
   q.turned=true;q.active=false
   local fact="任务已交付："..title(id)
   if safe(b) and type(b)=="number" and b>0 then fact=fact.."，实际获得经验："..b end
   if safe(c) and type(c)=="number" and c>0 then fact=fact.."，实际获得金钱："..c.."铜" end
   A.QueueActivity("reward",key,fact,nil,nil,label(title(id)).."已交付！",{rewardTitle=title(id),rewardTurned=true})
  elseif safe(b) and type(b)=="string" then
   local item=tonumber(b:match("item:(%d+)"));local quantity=safe(c) and tonumber(c) or 1;quantity=quantity or 1
   if enabled("reward") then
    -- One quest reward fact already covers its equipment: never enqueue twice.
    A.QueueActivity("reward",key,"任务已领取物品奖励："..title(id).."，物品："..plain(b).."，数量："..quantity,nil,nil,"获得"..label(b).."！",{rewardTitle=title(id),rewardItem=itemName(b)})
   elseif item then
    sourceItem(b,key..":item:"..item,quantity,"任务奖励获得装备："..title(id))
   end
  end;return
 end
 if event=="CHAT_MSG_LOOT" then
  if not enabled("equipment") then return end
  local text,name,_,_,_,_,_,_,_,_,lineID,guid=...
  if not safe(name) or not safe(guid) then return end
  if type(guid)=="string" and guid~="" and guid~=UnitGUID("player") then return end
  if type(name)=="string" and name~="" and not A.IsSelf(name) then return end
  local link=rollMatch(text);if not link then return end
  serial=serial+1
  local history=text:match("|HlootHistory:(%d+)")
  local key=history and ("roll-history:"..history) or ("roll-line:"..(safe(lineID) and tonumber(lineID) and tonumber(lineID)>0 and tostring(lineID) or ("local:"..serial)))
  sourceItem(link,key,1,"我本人 Roll 获胜获得装备")
  return
 end
 if event=="GET_ITEM_INFO_RECEIVED" or event=="ITEM_DATA_LOAD_RESULT" then
  local id,success=...;if not safe(id) or not waitingItems[id] then return end
  local pending=waitingItems[id];waitingItems[id]=nil
  for _,entry in pairs(pending) do if success~=false then if not enqueueItem(entry) then note("装备资料仍不可用，未猜测品质") end else note("装备资料加载失败") end end
 end
end
local f=CreateFrame("Frame");A.activityFrame=f;A.activitySupport={}
for _,event in ipairs({"TRADE_SKILL_SHOW","TRADE_SKILL_CLOSE","CRAFT_SHOW","CRAFT_CLOSE","PLAYER_ENTERING_WORLD","QUEST_ACCEPTED","QUEST_LOG_UPDATE","QUEST_REMOVED","QUEST_TURNED_IN","QUEST_LOOT_RECEIVED","CHAT_MSG_LOOT","GET_ITEM_INFO_RECEIVED","ITEM_DATA_LOAD_RESULT"}) do local ok,result=pcall(f.RegisterEvent,f,event);A.activitySupport[event]=ok and result~=false end
f:SetScript("OnEvent",function(_,event,...) local ok=pcall(A.ActivityEvent,event,...);if not ok then note("事件数据不可读，已跳过") end end)
function A.ToggleActivityPanel()
 if not A.activityPanel then
  local p=CreateFrame("Frame","DFYActivitySettings",UIParent,"BackdropTemplate");A.activityPanel=p;p:SetSize(330,250);p:SetPoint("CENTER");A.NormalWindow(p,3);p:SetClampedToScreen(true);p:EnableMouse(true)
  p:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1});p:SetBackdropColor(.025,.055,.075,.98)
  local title=p:CreateFontString(nil,"OVERLAY","GameFontNormal");title:SetPoint("TOPLEFT",12,-12);title:SetText("大肥鱼 · 事件自动发言（跟随回复频道）")
  A.activityChecks={}
 local names={{"master","事件开关（受自动总控控制）"},{"accept","接取任务"},{"complete","完成任务目标（尚未交付）"},{"reward","交付任务 / 领取奖励"},{"equipment","Roll / 任务装备（蓝色及以上）"}}
  for i,row in ipairs(names) do
   local key=row[1];local box=CreateFrame("CheckButton",nil,p,"UICheckButtonTemplate");box:SetSize(24,24);box:SetPoint("TOPLEFT",12,-34-(i-1)*28)
   local label=p:CreateFontString(nil,"OVERLAY","GameFontNormal");label:SetPoint("LEFT",box,"RIGHT",4,0);label:SetText(row[2]);A.activityChecks[key]=box
   box:SetScript("OnClick",function(self) A.SetActivityOption(key,self:GetChecked() and true or false) end)
  end
  local status=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");status:SetPoint("TOPLEFT",12,-180);status:SetWidth(306);status:SetHeight(30);A.activityStatus=status
  local close=CreateFrame("Button",nil,p,"UIPanelButtonTemplate");close:SetSize(70,24);close:SetPoint("BOTTOMRIGHT",-10,10);close:SetText("关闭");close:SetScript("OnClick",function() p:Hide() end)
  UISpecialFrames[#UISpecialFrames+1]="DFYActivitySettings";p:Hide()
 end
 if A.activityPanel:IsShown() then A.activityPanel:Hide() else A.RenderActivityPanel();A.activityPanel:Show() end
end
function A.RenderActivityPanel()
 if not A.activityPanel then return end
 for key,box in pairs(A.activityChecks) do box:SetChecked(key=="master" and A.db.activityAuto or key~="master" and A.db.activities[key]) end
 A.activityStatus:SetText(not A.MasterAutoEnabled() and "自动总控已关：仅保存偏好，不自动发言。" or A.activityDiagnostic or "连续事件静默2秒后合为一句；无发送冷却、无小时上限。")
end
