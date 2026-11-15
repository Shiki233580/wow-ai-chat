DFY = {channels={}, order={}, sequence=0, status="OFFLINE", detail="等待桌面助手", session=tostring(time())..tostring(math.random(1000,9999)), lastBridge=0}
local A=DFY
A.version="1.18.25"
A.ArrayMeta={}
function A.Array(values) return setmetatable(values or {},A.ArrayMeta) end
local types={SAY="说",YELL="喊叫",PARTY="小队",PARTY_LEADER="小队",RAID="团队",RAID_LEADER="团队",GUILD="公会",OFFICER="官员",WHISPER="悄悄话",BN_WHISPER="战网私聊",CHANNEL="频道",INSTANCE_CHAT="副本队伍",INSTANCE_CHAT_LEADER="副本队伍"}
local function privateType(t) return t=="WHISPER" or t=="BN_WHISPER" end
local function readable(x) return type(issecretvalue)~="function" or not issecretvalue(x) end
local function validBNID(x) return readable(x) and type(x)=="number" and x>0 and x==math.floor(x) end
local function norm(t) return t=="PARTY_LEADER" and "PARTY" or t=="RAID_LEADER" and "RAID" or t=="INSTANCE_CHAT_LEADER" and "INSTANCE_CHAT" or t end
local function clean(s)
 s=tostring(s or ""):gsub("|cn[%w_]+:",""):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("|H.-|h(.-)|h","%1"):gsub("|T.-|t",""):gsub("|A.-|a",""):gsub("|K.-|k",""):gsub("[%z\1-\31]"," ")
 return s:gsub("|","")
end
function A.Cut(s,n)
 local k,p=0,1
 while p<=#s do local b=s:byte(p); local l=b<128 and 1 or b<224 and 2 or b<240 and 3 or 4; k=k+1; if k>n then return s:sub(1,p-1) end; p=p+l end
 return s
end
-- Prefix is a local transport label, not part of the 48-character model body.
function A.ReplyPrefix(c) return c and "【大肥鱼】" or "" end
function A.FormatReply(c,text)
 text=clean(text);local prefix=A.ReplyPrefix(c)
 if prefix~="" then while text:sub(1,#prefix)==prefix do text=text:sub(#prefix+1) end end
 text=A.Cut(text,48)
 if not text:find("%S") then return "" end
 return prefix..text
end
-- Manual, local action: no AI request, no pending-reply mutation, no retry timer.
function A.AskTargetForWater()
 local function feedback(message)
  A.waterDetail=message; A.detail=message
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage("【大肥鱼】"..message) end
  A.Refresh()
 end
 local ok,target=pcall(function()
  local exists=UnitExists("target")
  if not readable(exists) or not exists then return nil end
  local player=UnitIsPlayer("target");local self=UnitIsUnit("target","player");local friend=UnitIsFriend("player","target")
  local _,class=UnitClass("target");local name,realm=UnitFullName("target")
  for _,value in ipairs({player,self,friend,class or false,name or false,realm or false}) do if not readable(value) then return nil end end
  if not player or self or not friend or class~="MAGE" or type(name)~="string" or name=="" then return nil end
  if realm==nil or realm=="" then realm=GetRealmName() end
  if not readable(realm) or type(realm)~="string" or realm=="" then return nil end
  return name.."-"..realm
 end)
 if not ok or not target then feedback("讨水未发送：请先选中一位友方法师玩家（不能是自己）。");return false end
 local message=A.FormatReply({type="WHISPER"},"法师，分我点水呗，鲸鲸都快渴扁了，谢谢啦！")
 local sent,err=pcall(SendChatMessage,message,"WHISPER",nil,target)
 if not sent then feedback("讨水发送失败："..clean(err));return false end
 if A.MasterAutoEnabled() and A.db.waterThanksAuto then A.waterRequests=A.waterRequests or {}; A.waterRequests[target:lower():gsub("%s","")]={target=target} end
 feedback("已向 "..target.." 提交讨水私聊，请以聊天记录为准。")
 return true
end

-- Trade confirmation only: no bag scanning, loot hooks, AI requests or timers.
local function waterNameKey(name) return name:lower():gsub("%s","") end
local waterItemIDs={ [5350]=true,[2288]=true,[2136]=true,[3772]=true,[8077]=true,[8078]=true,[8079]=true,[30703]=true,[22018]=true,[43518]=true,[65499]=true,[58274]=true,[80618]=true,[113509]=true }
local function isWaterLink(link)
 if not readable(link) or type(link)~="string" then return false end
 local id=tonumber(link:match("item:(%d+)"));if not id then return false end
 if waterItemIDs[id] then return true end
 -- Custom/other-client drinks: require actual item data to identify mana restoration.
 if C_TooltipInfo and type(C_TooltipInfo.GetItemByID)=="function" then
  local ok,data=pcall(C_TooltipInfo.GetItemByID,id)
  if ok and type(data)=="table" and type(data.lines)=="table" then
   for _,line in ipairs(data.lines) do
    local t=line.leftText
    if readable(t) and type(t)=="string" then
     t=t:lower()
     if (t:find("法力",1,true) or t:find("mana",1,true)) and (t:find("坐",1,true) or t:find("seated",1,true)) then return true end
    end
   end
  end
 end
 return false
end
function A.WaterTradeEvent(event,...)
 if not A.MasterAutoEnabled() or not A.db.waterThanksAuto then A.waterTrade=nil;A.waterRequests={};return end
 if event=="TRADE_SHOW" then
  A.waterTrade=nil
  local name,realm=UnitFullName("NPC")
  if not readable(name) or not readable(realm) or type(name)~="string" or name=="" then return end
  if not realm or realm=="" then realm=GetRealmName() end
  if not readable(realm) or type(realm)~="string" then return end
  local key=waterNameKey(name.."-"..realm);local request=A.waterRequests and A.waterRequests[key]
  if request then A.waterTrade={key=key,request=request,target=request.target} end
  return
 end
 local trade=A.waterTrade;if not trade then return end
 if event=="TRADE_REQUEST_CANCEL" then A.waterTrade=nil;return end
 if event=="TRADE_TARGET_ITEM_CHANGED" or event=="TRADE_PLAYER_ITEM_CHANGED" then trade.accepted=false;trade.water=false;return end
 if event=="TRADE_ACCEPT_UPDATE" then
  local mine,theirs=...;trade.accepted=false;trade.water=false
  if not readable(mine) or not readable(theirs) then return end
  if (mine~=1 and mine~=true) or (theirs~=1 and theirs~=true) then return end
  for slot=1,6 do if isWaterLink(GetTradeTargetItemLink(slot)) then trade.water=true;break end end
  trade.accepted=true;return
 end
 -- TRADE_CLOSED can precede the completion message; closing is not proof of success.
 if event=="UI_INFO_MESSAGE" then
  local _,message=...
  if not readable(message) or type(message)~="string" or type(ERR_TRADE_COMPLETE)~="string" or message~=ERR_TRADE_COMPLETE then return end
  A.waterTrade=nil
  if not trade.accepted or not trade.water or not A.waterRequests or A.waterRequests[trade.key]~=trade.request then return end
  A.waterRequests[trade.key]=nil -- consume before native send; duplicate events never resend
  local text=A.FormatReply({type="WHISPER"},"水收到啦，谢谢你！哼，鲸鲸记你这个人情。")
  local ok,err=pcall(SendChatMessage,text,"WHISPER",nil,trade.target)
  A.waterDetail=ok and ("已向 "..trade.target.." 提交收水感谢，请以聊天记录为准。") or ("收水感谢发送失败："..clean(err))
  A.detail=A.waterDetail
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage("【大肥鱼】"..A.waterDetail) end
  A.Refresh()
 end
end
local waterEvents=CreateFrame("Frame");A.waterTradeFrame=waterEvents
for _,event in ipairs({"TRADE_SHOW","TRADE_ACCEPT_UPDATE","TRADE_TARGET_ITEM_CHANGED","TRADE_PLAYER_ITEM_CHANGED","TRADE_REQUEST_CANCEL","TRADE_CLOSED","UI_INFO_MESSAGE"}) do pcall(waterEvents.RegisterEvent,waterEvents,event) end
waterEvents:SetScript("OnEvent",function(_,event,...)
 if not A.db then return end
 local ok=pcall(A.WaterTradeEvent,event,...)
 if not ok then A.waterTrade=nil;A.waterDetail="交易信息不可读，未发送自动感谢。" end
end)

function A.FormatPendingReply(p,text)
 if not (p and p.mode=="event" and p.eventFlavor and p.eventReply and p.eventReply~="") then return A.FormatReply(p and p.channel,text) end
 local prefix=A.ReplyPrefix(p.channel);text=clean(text)
 while text:sub(1,#prefix)==prefix do text=text:sub(#prefix+1) end
 local header=p.eventReply
 if text:sub(1,#header)==header then text=text:sub(#header+1):match("^%s*(.-)%s*$") end
 local body=A.Cut(text,24)
 return prefix..header..(body~="" and (" "..body) or "")
end
-- Require the native joined list AND native name lookup to agree before accepting
-- a display alias (e.g. General vs General - zone). Never trust a numeric ID alone.
function A.ChannelMatches(c)
 if type(GetChannelName)~="function" then return false end
 local ok,id,name=pcall(GetChannelName,c.number)
 if not ok or not readable(id) or not readable(name) or id~=c.number or id==0 or type(name)~="string" then return false end
 local expected=clean(c.baseName);name=clean(name)
 if name==expected then return true end
 if type(GetChannelList)~="function" then return false end
 local values={pcall(GetChannelList)};if not values[1] then return false end
 for i=2,#values,3 do
  if readable(values[i]) and readable(values[i+1]) and values[i]==c.number and type(values[i+1])=="string" and clean(values[i+1])==expected then
   local found,n,nativeName=pcall(GetChannelName,expected)
   return found and readable(n) and readable(nativeName) and n==c.number and type(nativeName)=="string" and clean(nativeName)==name
  end
 end
 return false
end
-- Above native/Ellesmere chat (MEDIUM100 tabs), without DIALOG/TOOLTIP promotion.
local function frameValue(frame,method)
 if not frame or type(frame[method])~="function" then return nil end
 local ok,value=pcall(frame[method],frame)
 if not ok or (type(issecretvalue)=="function" and issecretvalue(value)) then return nil end
 return value
end
local function overlaps(a,b)
 local al,ab,ar,at=frameValue(a,"GetLeft"),frameValue(a,"GetBottom"),frameValue(a,"GetRight"),frameValue(a,"GetTop")
 local bl,bb,br,bt=frameValue(b,"GetLeft"),frameValue(b,"GetBottom"),frameValue(b,"GetRight"),frameValue(b,"GetTop")
 for _,n in ipairs({al or false,ab or false,ar or false,at or false,bl or false,bb or false,br or false,bt or false}) do if type(n)~="number" then return false end end
 return al<br and ar>bl and ab<bt and at>bb
end
function A.NormalWindow(frame,level)
 A.uiLayerFrames=A.uiLayerFrames or {};A.uiLayerFrames[#A.uiLayerFrames+1]={frame=frame,offset=(level or 1)*10}
 frame:SetFrameStrata("MEDIUM");frame:SetFrameLevel(120+(level or 1)*10);frame:SetToplevel(false)
end
function A.UpdateWindowLayers()
 if not A.uiLayerFrames then return end
 local base=120
 for _,name in ipairs({"SELECTED_CHAT_FRAME","DEFAULT_CHAT_FRAME","ChatFrame1","RurutiaChatBar"}) do
  local n=frameValue(_G[name],"GetFrameLevel");if type(n)=="number" and n>=0 and n<10000 then base=math.max(base,n+16) end
 end
 local panels,seen={},{}
 local function add(f)
  if f and not seen[f] and frameValue(f,"IsShown")==true and frameValue(f,"IsVisible")~=false then seen[f]=true;panels[#panels+1]=f end
 end
 if type(GetUIPanel)=="function" then for _,slot in ipairs({"left","center","right","doublewide","fullscreen"}) do local ok,f=pcall(GetUIPanel,slot);if ok then add(f) end end end
 for _,name in ipairs({"WorldMapFrame","GameMenuFrame","SettingsPanel","InterfaceOptionsFrame","CharacterFrame","SpellBookFrame","PlayerSpellsFrame","QuestLogFrame","QuestFrame","GossipFrame","MerchantFrame","BankFrame","AuctionHouseFrame","AuctionFrame","TradeFrame","TradeSkillFrame","ProfessionsFrame","ContainerFrameCombinedBags","PVEFrame","FriendsFrame"}) do add(_G[name]) end
 for i=1,13 do add(_G["ContainerFrame"..i]) end
 for _,entry in ipairs(A.uiLayerFrames) do
  local f=entry.frame;local strata,level="MEDIUM",base+entry.offset
  if frameValue(f,"IsShown")==true then
   for _,panel in ipairs(panels) do
    if panel~=f and overlaps(f,panel) then
     local st=frameValue(panel,"GetFrameStrata")
     -- Yield even to low-level ordinary panels instead of competing with their stack.
     if st=="MEDIUM" then strata="LOW";level=entry.offset
     elseif st=="LOW" or st=="BACKGROUND" then strata="BACKGROUND";level=0 end
    end
   end
  end
  if frameValue(f,"GetFrameStrata")~=strata then f:SetFrameStrata(strata) end
  if frameValue(f,"GetFrameLevel")~=level then f:SetFrameLevel(level) end
 end
end
function A.Init()
 DFY_DB=DFY_DB or {}; A.db=DFY_DB
 local d=A.db
 if d.transportVersion~=8 then d.auto=false; d.transportVersion=8 end
 if d.masterAuto==nil then d.masterAuto=d.auto==true end
 if d.waterThanksAuto==nil then d.waterThanksAuto=true end
 if d.uiMode==nil then d.uiMode="chat" end
 if d.selected==nil then d.selected={} end
 -- Each login/reload starts on SAY; later UI refreshes keep the user's choice.
 if not A.channels.SAY then
  A.channels.SAY={key="SAY",type="SAY",name=types.SAY,messages={}}
  A.order[#A.order+1]="SAY"
 end
 d.selected.SAY=true; d.targetKey="SAY"; A.current="SAY"
 if d.cooldownPolicy~=2 then d.cooldown=0; d.cooldownPolicy=2 end
 if d.hourlyPolicy~=1 then d.hourlyLimit=0; d.hourlyPolicy=1 end
 d.cooldown=d.cooldown or 0; d.hourlyLimit=d.hourlyLimit or 0; d.keywords=d.keywords or {"大肥鱼","鲸鱼"}; d.sentTimes=d.sentTimes or {}
 d.width=d.width or 660; d.height=d.height or 540
 A.WhisperInit(); A.boot=GetTime(); if A.ActivityInit then A.ActivityInit() end; A.Refresh()
end
function A.Refresh() if A.Render then A.Render() end; if A.RenderChatDock then A.RenderChatDock() end; if A.Publish then A.Publish() end end
function A.State(s,detail) A.status=s; A.detail=detail or ""; A.Refresh() end
function A.Recent()
 local all={}
 for key,c in pairs(A.channels) do if A.db.selected[key] then for _,m in ipairs(c.messages) do all[#all+1]=m end end end
 table.sort(all,function(x,y) return x.seq<y.seq end)
 local out=A.Array(); for i=math.max(1,#all-7),#all do out[#out+1]=all[i] end
 return out
end
function A.IsSelf(name,guid)
 if readable(guid) and type(guid)=="string" and guid~="" then return guid==UnitGUID("player") end
 local n,r=UnitFullName("player"); n=n or ""; r=((r and r~="") and r or GetRealmName() or ""):gsub("%s","")
 return name==n or name==n.."-"..r or name==n.." "..r
end
function A.AllowAuto()
 if not A.MasterAutoEnabled() then return false,"自动总控已关闭" end
 local now=time(); local times={}
 for _,t in ipairs(A.db.sentTimes) do if now-t<3600 then times[#times+1]=t end end; A.db.sentTimes=times
 if A.db.hourlyLimit>0 and #times>=A.db.hourlyLimit then return false,"每小时上限" end
 if A.db.lastAttempt and now-A.db.lastAttempt<A.db.cooldown then return false,"冷却中",math.ceil(A.db.cooldown-(now-A.db.lastAttempt)) end
 return true
end
function A.Chat(event,text,name,_,_,_,_,_,number,channelName,_,lineID,guid,bnSenderID)
 local typ=norm(event:gsub("CHAT_MSG_","")); if not types[typ] then return end
 if not readable(text) or not readable(name) or not readable(guid) or not readable(lineID) then A.whisperDiagnostic="私聊内容受客户端保护，未读取";A.whisperDirty=true;return end
 if type(name)~="string" or name=="" then return end
 text=clean(text); if text=="" then return end
 if typ~="BN_WHISPER" and A.IsSelf(name,guid) then
  if not privateType(typ) then A.PublicOutgoing(typ,text,name,number,channelName) end
  local p=A.pending
  if p and p.submitted and text==p.reply and typ==p.channel.type and (typ~="CHANNEL" or tonumber(number)==p.channel.number) then
   A.ClearSentPreview(p)
  else
   -- Late public ACKs release only their original destination, never the new job.
   local key=typ=="CHANNEL" and "CHANNEL:"..tostring(number)..":"..clean(channelName) or typ
   local old=A.FindUnconfirmed(A.channels[key],text)
   if old then A.ResolveUnconfirmed(old) end
  end
  return
 end
 local bnChannel
 if typ=="BN_WHISPER" then bnChannel=A.BNWhisperChannel(name,bnSenderID);if not bnChannel then return end end
 local baseName=clean(channelName)
 local key=bnChannel and bnChannel.key or typ=="CHANNEL" and "CHANNEL:"..tostring(number)..":"..baseName or typ=="WHISPER" and "WHISPER:"..name or typ
 local c=A.channels[key]
 if not c then c={key=key,type=typ,name=typ=="CHANNEL" and tostring(number).."."..baseName or typ=="WHISPER" and "悄悄话 · "..name or types[typ],baseName=baseName,number=tonumber(number),target=typ=="WHISPER" and name or nil,messages={}}; A.channels[key]=c; A.order[#A.order+1]=key end
 if type(lineID)=="number" and lineID>0 then if c.lastWhisperLineID==lineID then return end;c.lastWhisperLineID=lineID end
 A.sequence=A.sequence+1
 local m={speaker=clean(name),text=A.Cut(text,240),seq=A.sequence,key=key,label=c.name}
 c.messages[#c.messages+1]=m; if #c.messages>40 then table.remove(c.messages,1) end
 if A.db.selected[key] and (not A.db.targetKey or A.db.targetKey==key) then A.current=key end
 if privateType(typ) then
  A.whisperReceived=A.whisperReceived or {};A.whisperReceived[typ]=(A.whisperReceived[typ] or 0)+1
  A.QueueWhisper(c);A.whisperDirty=true;return
 end
 A.Refresh()
 A.QueuePublic(c)
end
function A.ClearSentPreview(p)
 if not p or p~=A.pending or not p.submitted then return end
 p.confirmed=true; if A.WhisperFinish then A.WhisperFinish(p) end; p.reply=nil; p.recent=nil; p.last=nil; p.previewCleared=true
 if A.dockDraft then A.dockDraft:ClearFocus(); A.dockDraft:SetText("") end
 if A.reply then A.reply:ClearFocus(); A.reply:SetText("") end
 -- Keep a new scene the user is currently typing; never steal its focus on a late ACK.
 if not (A.dockScene and A.dockScene:HasFocus()) then A.db.dockExpanded=false end
 A.State("SENT","已发送，回复预览已清空")
end
-- One persistent gate for every unsolicited send; feature choices remain independent.
function A.MasterAutoEnabled() return A.db and A.db.masterAuto==true end
function A.AutoOptionLabel(name,enabled)
 return name..":"..(enabled and (A.MasterAutoEnabled() and "开" or "停") or "关")
end
function A.SetMasterAuto(value)
 A.db.masterAuto=value==true
 -- Drop stale work on either transition; never replay while resuming.
 A.publicJobs={};A.whisperJobs={};A.queuedSignal=nil;A.waterRequests={};A.waterTrade=nil
 if A.ClearActivityWork then A.ClearActivityWork() end
 local p=A.pending
 if p and p.automatic and not p.submitted then
  A.requestCounter=(A.requestCounter or 0)+1;A.pending=nil;A.prepared=nil
  A.status=A.lastBridge>0 and GetTime()-A.lastBridge<=75 and "IDLE" or "OFFLINE"
 end
 if A.db.masterAuto and A.ActivityScan then A.ActivityScan(true) end
 A.detail=A.db.masterAuto and "自动总控已开：按各项偏好处理新消息，不补发旧任务" or "自动总控已关：所有自动发言停止，手动按钮仍可用"
 if p and p.automatic and p.submitted and not p.confirmed then A.detail=A.detail.."；已经提交的消息无法撤回" end
 A.publicDiagnostic=A.detail;A.whisperDiagnostic=A.detail;A.activityDiagnostic=A.detail
 if A.RenderActivityPanel then A.RenderActivityPanel() end
 A.Refresh()
end

function A.AutoEnabled(p)
 if not A.MasterAutoEnabled() then return false end
 if p and p.mode=="public" and not A.PublicRouteAllowed(p.channel) then return false end
 if p and p.mode=="whisper" then return A.db.whisperAuto==true end
 if p and p.mode=="event" then return A.ActivityEnabled and A.ActivityEnabled(p.eventKind) or false end
 if p and p.mode=="signal" then return A.db.signalAuto==true end
 return A.db.auto==true
end
function A.Cancel()
 if A.pending and A.pending.submitted and not A.pending.confirmed then A.detail="已提交的消息无法撤回；等待发送确认"; A.Refresh(); return false end
 if A.pending and A.pending.mode=="whisper" then A.whisperJobs[A.pending.channel.key]=nil end
 A.queuedSignal=nil; A.requestCounter=(A.requestCounter or 0)+1; A.pending=nil; A.prepared=nil
 A.db.dockExpanded=false
 if A.dockScene then A.dockScene:ClearFocus() end
 if A.dockDraft then A.dockDraft:ClearFocus() end
 A.State(A.lastBridge>0 and GetTime()-A.lastBridge<=75 and "IDLE" or "OFFLINE","已丢弃；旧回复不会再发送")
 return true
end
function A.GenerateScene(prompt)
 prompt=A.Cut(clean(prompt),160)
 if not prompt:find("%S") then A.detail="先写几个场景提示词，例如：打完本感谢队友"; A.Refresh(); return end
 return A.Generate(A.current,false,prompt,"scene")
end
function A.SignalChannel()
 -- Explicit toolbar destination wins, including SAY, whisper and custom channels.
 local key=(A.db.targetKey and A.db.selected[A.db.targetKey] and A.db.targetKey) or (A.current and A.db.selected[A.current] and A.current)
 if key and A.channels[key] then
  local c=A.channels[key]
  if c.type=="PARTY" and (type(IsInGroup)~="function" or not IsInGroup()) then return nil end
  if c.type=="RAID" and (type(IsInRaid)~="function" or not IsInRaid()) then return nil end
  if c.type=="INSTANCE_CHAT" and (not LE_PARTY_CATEGORY_INSTANCE or type(IsInGroup)~="function" or not IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) then return nil end
  if privateType(c.type) and (not c.target or c.target=="") then return nil end
  return key
 end
 if type(IsInGroup)=="function" and IsInGroup() then
  if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  return type(IsInRaid)=="function" and IsInRaid() and "RAID" or "PARTY"
 end
 return "SAY"
end
function A.Signal(prompt,preview)
 if not preview and (not A.MasterAutoEnabled() or not A.db.signalAuto) then return end
 -- Never overwrite a draft, even if it came from a different automation mode.
 if A.pending and (A.status=="GENERATING" or A.status=="READY" or A.pending.submitted and not A.pending.confirmed) then A.detail="保留当前待发内容，本次信号跳过"; A.Refresh(); return end
 local key=A.SignalChannel()
 if not key then A.detail="所选回复频道当前不可用，请选择说或其他可用频道"; A.Refresh(); return end
 if not A.channels[key] then A.channels[key]={key=key,type=key,name=types[key] or key,messages={}}; A.order[#A.order+1]=key end
 if not preview then
  local ok,why,remaining=A.AllowAuto()
  if not ok then
   if remaining then
    A.queuedSignal={prompt=A.Cut(clean(prompt),160),key=key,created=GetTime()}
    A.detail="冷却剩余 "..remaining.." 秒，已保留最新标记"
   else A.queuedSignal=nil; A.detail=why.."，本次信号不排队" end
   A.signalDiagnostic=A.detail; A.Refresh(); return
  end
 end
 A.queuedSignal=nil
 return A.Generate(key,not preview,A.Cut(clean(prompt),160),"signal")
end
function A.PumpSignal()
 local q=A.queuedSignal; if not q then return end
 local p=A.pending
 if not A.MasterAutoEnabled() or not A.db.signalAuto or A.SignalChannel()~=q.key or GetTime()-q.created>20 or (p and (A.status=="GENERATING" or A.status=="READY" or p.submitted and not p.confirmed)) then
  A.queuedSignal=nil; A.signalDiagnostic="排队标记已取消（关闭/目标变化/过期/草稿占用）"; A.Refresh(); return
 end
 local ok,why,remaining=A.AllowAuto()
 if ok then A.queuedSignal=nil; A.Signal(q.prompt,false); if A.status=="GENERATING" and A.pending and A.pending.mode=="signal" then A.pending.signalAt=q.created end; A.signalDiagnostic=A.status=="GENERATING" and "最新标记已触发生成" or A.detail; A.Refresh()
 elseif remaining then
  local detail="冷却剩余 "..remaining.." 秒，已保留最新标记"
  if A.detail~=detail then A.detail=detail; A.signalDiagnostic=detail; A.Refresh() end
 else A.queuedSignal=nil; A.detail=why.."，排队标记已取消"; A.signalDiagnostic=A.detail; A.Refresh() end
end
function A.SignalButton(kind)
 local prompt=kind=="danger" and "危险，提醒队友躲避这里" or "注意，提醒队友留意这里"
 if kind=="target" then
  local name=type(UnitName)=="function" and UnitName("target") or nil
  if type(issecretvalue)=="function" and issecretvalue(name) then name=nil end
  if not name or name=="" then A.detail="请先选中目标"; A.Refresh(); return end
  prompt="提醒队友关注我选中的目标："..clean(name)
 end
 A.Signal(prompt,not (A.MasterAutoEnabled() and A.db.signalAuto))
end
function A.SignalNote(note)
 A.signalDiagnostic=note; A.detail="信号："..note; A.Refresh()
end
local function secret(v) return type(issecretvalue)=="function" and issecretvalue(v) end
function A.IsOwnSignal(name,guid)
 if secret(name) or secret(guid) then return false,"身份受限" end
 local playerGuid=UnitGUID("player")
 if secret(playerGuid) then return false,"身份受限" end
 if type(guid)=="string" and guid~="" then return guid==playerGuid,"GUID" end
 -- CHAT_MSG_PING may omit GUID. Only use exact identity, never message text.
 if type(name)~="string" or name=="" then return false,"缺少发送者" end
 -- Preserve the actual sender payload for diagnosis before normalization.
 local rawName=name
 local linked=name:match("|Hplayer:([^:|]+)")
 if linked then name=linked
 elseif name:find("|H",1,true) then return false,"非玩家链接"
 else name=name:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):match("^%s*(.-)%s*$"); name=name:match("^%[(.*)%]$") or name end
 local n,r=UnitFullName("player"); if secret(n) or secret(r) then return false,"身份受限" end
 r=((r and r~="") and r or GetRealmName() or ""):gsub("%s","")
 if name==n.."-"..r or name==n.." "..r then return true,"完整角色名" end
 if name~=n then return false,"名称不匹配，收到="..A.Cut(rawName:gsub("|","/"),90).."；本机="..n.."-"..r end
 -- Bare names are accepted only when the current group roster is unambiguous.
 if type(GetNumGroupMembers)~="function" then return false,"短名无法核对队伍" end
 local count=GetNumGroupMembers(); if secret(count) then return false,"队伍受限" end
 local raid=type(IsInRaid)=="function" and IsInRaid()
 for i=1,(raid and count or math.max(0,count-1)) do
  local unit=(raid and "raid" or "party")..i; local other=UnitFullName(unit); local otherGuid=UnitGUID(unit)
  if secret(other) or secret(otherGuid) or not other then return false,"队伍身份不可读" end
  if other==n and otherGuid~=playerGuid then return false,"队伍中存在同名角色" end
 end
 return true,"队伍核对短名"
end
-- Only a currently visible, matching world-object tooltip proves tent ownership.
function A.OwnTentSignal(message)
 if not message:find("帐篷",1,true) then return nil end
 local tip=GameTooltip
 if not tip or not tip.IsShown or not tip:IsShown() then return nil end
 local first=GameTooltipTextLeft1
 local title=first and first.GetText and first:GetText()
 if secret(title) or type(title)~="string" then return nil end
 title=clean(title)
 if not title:find("帐篷",1,true) or not message:find(title,1,true) then return nil end
 local lines=tip.NumLines and tip:NumLines() or 20
 if secret(lines) or type(lines)~="number" then return nil end
 for i=2,math.min(lines,20) do
  local line=_G["GameTooltipTextLeft"..i]
  local text=line and line.GetText and line:GetText()
  if not secret(text) and type(text)=="string" then
   local owner=clean(text):match("^%s*由%s*(.-)%s*放置%s*$")
   if owner and A.IsOwnSignal(owner,nil) then
    return "我正在展示自己放置的帐篷："..A.Cut(title,60).."。标记是在炫耀自己的营地，很得意地招呼大家看，不是危险警告；只表达自豪，不编造增益数值。"
   end
  end
 end
 return nil
end
function A.OnPing(text,name,lineID,guid)
 A.signalSeen=(A.signalSeen or 0)+1
 if not A.MasterAutoEnabled() or not A.db.signalAuto then A.SignalNote("已收到，但信号开关关闭"); return end
 if secret(text) or secret(name) or secret(lineID) or secret(guid) then A.SignalNote("客户端限制读取此信号，已跳过"); return end
 local own,method=A.IsOwnSignal(name,guid)
 if not own then A.SignalNote("忽略非本人或不可核对的信号（"..method.."）"); return end
 if type(text)~="string" then A.SignalNote("信号没有可读文本"); return end
 local message=clean(text)
 if not message:find("%S") then A.SignalNote("信号文本为空"); return end
 local numericID=tonumber(lineID)
 local identity=numericID and numericID>0 and tostring(numericID) or message
 if numericID and numericID>0 and A.lastSignalID==identity and GetTime()-(A.lastSignalAt or 0)<60 then A.SignalNote("重复信号已跳过"); return end
 A.lastSignalID=identity; A.lastSignalAt=GetTime()
 A.SignalNote("已识别本人信号（"..method.."）")
 local ok,tent=pcall(A.OwnTentSignal,message)
 A.Signal(ok and tent or ("我刚发出的信号："..message),false)
 -- Surface offline/cooldown/no-group/busy outcomes beside the signal switch as well.
 A.signalDiagnostic=A.status=="GENERATING" and "已触发生成" or A.detail; A.Refresh()
end
-- Snapshot only at generation/delivery boundaries, never on every pixel poll.
function A.ReadWorldState(c)
 local function call(fn,...)
  if type(fn)~="function" then return nil end
  local ok,a,b=pcall(fn,...)
  if not ok or not readable(a) or not readable(b) then return nil end
  return a,b
 end
 local raid=call(IsInRaid);local group=call(IsInGroup)
 if LE_PARTY_CATEGORY_INSTANCE then
  local instanceGroup=call(IsInGroup,LE_PARTY_CATEGORY_INSTANCE)
  if instanceGroup==true then group=true end
 end
 local grouped=raid==true and "raid" or group==true and "party" or group==false and raid==false and "solo" or "unknown"
 local inside,kind=call(IsInInstance);local instance="unknown"
 if inside==false then instance="none"
 elseif inside==true then
  local known={party=true,raid=true,pvp=true,arena=true,scenario=true}
  instance=known[kind or ""] and kind or "inside"
 end
 local zone=call(GetZoneText)
 zone=type(zone)=="string" and A.Cut(clean(zone),32) or ""
 local peerInGroup="unknown"
 if c and c.type=="WHISPER" and type(c.target)=="string" then
  if grouped=="solo" then peerInGroup="no"
  elseif grouped=="party" or grouped=="raid" then
   local target=c.target;local found=0;local complete=true
   for i=1,(grouped=="raid" and 40 or 4) do
    local unit=(grouped=="raid" and "raid" or "party")..i
    local exists=call(UnitExists,unit)
    if exists==nil then complete=false
    elseif exists==true then
     local name,realm=call(UnitFullName,unit)
     if type(name)~="string" or name=="" then complete=false
     else
      if not realm or realm=="" then realm=call(GetRealmName) end
      if type(realm)~="string" then complete=false
      else
       realm=realm:gsub("%s","")
       if target==name.."-"..realm or target==name.." "..realm or target==name then found=found+1 end
      end
     end
    end
   end
   if found==1 and complete then peerInGroup="yes" elseif found==0 and complete then peerInGroup="no" end
  end
 end
 return {group=grouped,instance=instance,zone=zone,peerInGroup=peerInGroup}
end
function A.RefreshStaleWorldState(p)
 if not p or not p.automatic or not p.worldState or (p.mode~="whisper" and p.mode~="public" and p.mode~="reply") then return false end
 local now=A.ReadWorldState(p.channel);local old=p.worldState
 if old.group==now.group and old.instance==now.instance and old.zone==now.zone and old.peerInGroup==now.peerInGroup then return false end
 -- Invalidate the old request ID; a late answer cannot describe the previous location.
 A.requestCounter=(A.requestCounter or p.id)+1;p.id=A.requestCounter;p.worldState=now;p.reply=nil;p.created=GetTime();A.prepared=nil
 local q=p.mode=="whisper" and A.whisperJobs[p.channel.key] or p.mode=="public" and A.publicJobs[p.channel.key]
 if q then q.requestId=p.id end
 A.State("GENERATING","组队或位置已变化，按当前状态重新回答")
 return true
end

function A.Generate(key,automatic,prompt,mode,eventKind)
 if automatic and not A.MasterAutoEnabled() then return end
 if automatic and mode=="public" and not A.PublicRouteAllowed(A.channels[key or A.current]) then return end
 if A.ProfessionBusy and A.ProfessionBusy() then A.detail="专业窗口打开：等待关闭后再聊天";A.Refresh();return end
 if mode~="signal" and mode~="whisper" then A.queuedSignal=nil end
 if automatic and A.pending and A.status=="READY" then A.detail="保留待发草稿，跳过自动触发"; A.Refresh(); return end
 if A.pending and (A.status=="GENERATING" or A.pending.submitted and not A.pending.confirmed) then A.detail=A.status=="GENERATING" and "正在生成，请稍候" or "上一条发送尚未确认，不会重复发送"; A.Refresh(); return end
 key=key or A.current
 local c=key and A.channels[key]
 if not c or (mode~="signal" and mode~="event" and mode~="whisper" and not A.db.selected[key]) or (not prompt and #c.messages==0) then A.State("IDLE","先勾选有消息的频道"); return end
 -- Unconfirmed old requests are evidence, not a permanent destination lock.
 if mode=="whisper" and (not A.db.whisperAuto or not privateType(c.type)) then return end
 if GetTime()-A.lastBridge>75 or A.lastBridge==0 then A.State("OFFLINE","助手未连接或已暂停"); return end
 if automatic then local ok,why=A.AllowAuto(); if not ok then A.detail=why; A.Refresh(); return end; A.db.lastAttempt=time() end
 local recent=A.ContextFor(c); local last=prompt and {speaker="场景提示",text=prompt} or c.messages[#c.messages]
 if mode=="public" then recent=A.PublicContext(c) end
 if mode=="whisper" or mode=="public" then
  -- An outgoing ACK can arrive after the next question. Use the latest incoming turn, not the ACK.
  for i=#c.messages,1,-1 do if not c.messages[i].outgoing and (mode~="public" or not A.IgnorePublicMessage(c,c.messages[i].text)) then last=c.messages[i];break end end
 end
 A.requestCounter=(A.requestCounter or 0)+1
 A.pending={id=A.requestCounter,channel=c,automatic=automatic,mode=mode or "reply",eventKind=eventKind,created=GetTime(),recent=recent,last=last,worldState=A.ReadWorldState(c)}
 A.db.dockExpanded=true; A.State("GENERATING",c.name)
end
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
function A.Unbase64(data)
 if data:find('[^A-Za-z0-9+/=]') then return nil end
 local bits={}
 for i=1,#data do local c=data:sub(i,i); if c~='=' then local n=alphabet:find(c,1,true); if not n then return nil end; n=n-1; for j=5,0,-1 do bits[#bits+1]=math.floor(n/2^j)%2 end end end
 local out={}; for i=1,#bits-7,8 do local n=0; for j=0,7 do n=n*2+bits[i+j] end; out[#out+1]=string.char(n) end; return table.concat(out)
end
function A.Receive(session,id,data)
 local p=A.pending
 if session~=A.session or not p or tonumber(id)~=p.id or A.status~="GENERATING" then return end
 if A.PublicStale(p) then A.PublicRequeue(p);return end
 if A.WhisperStale(p) then A.WhisperRequeue(p);return end
 if p.automatic and not A.AutoEnabled(p) then A.Cancel();return end
 if A.RefreshStaleWorldState(p) then return end
 local raw=A.Unbase64(data or ""); if not raw then if not A.WhisperFail(p,"私聊回包无效") then A.State("OFFLINE","回包无效") end; return end
 if clean(raw):match("^%s*(.-)%s*$")=="…" then A.Cancel(); A.State("IDLE","本次无需发言，已跳过"); return end
 local reply=A.Cut(clean(raw),48):gsub('["`*_#]','')
 if reply=="" or reply:find("作为AI",1,true) or reply:find("人工智能",1,true) then if not A.WhisperFail(p,"私聊回复格式无效") then A.State("OFFLINE","回复被格式检查拒绝") end; return end
 reply=A.FormatPendingReply(p,reply)
 if reply=="" or reply==A.ReplyPrefix(p.channel).."…" then A.Cancel();A.State("IDLE","本次无需发言，已跳过");return end
 if A.FindUnconfirmed(p.channel,reply) then A.Cancel();A.State("IDLE","这句已有未确认记录，不重复发送；新内容可继续");return end
 if A.UnrequestedPublicOffer(p,reply) then A.Cancel();A.State("IDLE","未发送：自动接话不能替你报名、求带或索要物品");return end
 p.reply=reply; A.State("READY",p.channel.name)
end
function A.Send()
 if A.ProfessionBusy and A.ProfessionBusy() then A.detail="专业窗口打开：等待关闭后再聊天";A.Refresh();return end
 local p=A.pending; if A.status~="READY" or not p or not p.reply or p.submitted then A.detail=(p and p.submitted) and "已提交，等待确认；不会重复发送" or "尚无待发送回复，请先生成"; A.Refresh(); return end
 if A.PublicStale(p) then A.PublicRequeue(p);return end
 if A.WhisperStale(p) then A.WhisperRequeue(p);return end
 if not privateType(p.channel.type) then
  local key=A.db.targetKey or A.current
  if not A.RouteAvailable(p.channel) or (key and key~=p.channel.key) then A.Cancel();A.State("IDLE","未发送：选定频道不可用或目标已变化；不会转发到综合");return end
 end
 if A.FindUnconfirmed(p.channel,p.reply) then A.Cancel();A.State("IDLE","这句已有未确认记录，不重复发送；新内容可继续");return end
 if A.UnrequestedPublicOffer(p,p.reply) then A.Cancel();A.State("IDLE","未发送：自动接话不能替你报名、求带或索要物品");return end
 if p.mode=="signal" and GetTime()-(p.signalAt or p.created)>20 then A.Cancel(); A.detail="信号已过期，未发送"; A.Refresh(); return end
 if A.RefreshStaleWorldState(p) then return end
 p.reply=A.FormatPendingReply(p,p.reply); if p.reply=="" then A.detail="回复为空"; A.Refresh(); return end
 if (p.mode=="signal" or p.mode=="event") and A.SignalChannel()~=p.channel.key then A.detail="回复目标已变化，信号发送取消"; A.Refresh(); return end
 if p.mode~="signal" and p.mode~="event" and p.mode~="whisper" and not A.db.selected[p.channel.key] then A.detail="目标频道已取消勾选"; A.Refresh(); return end
 if p.automatic then
  -- Cooldown was reserved at trigger time; enforce the hourly cap again at send time.
  local now=time(); local n=0; for _,t in ipairs(A.db.sentTimes) do if now-t<3600 then n=n+1 end end
  if (A.db.hourlyLimit>0 and n>=A.db.hourlyLimit) or not A.AutoEnabled(p) then A.detail="自动发送已取消或达到上限"; A.Refresh(); return end
 end
 local c=p.channel
 if #p.reply>255 then A.detail="完整发言超过客户端字节上限，请缩短感想";A.Refresh();return end
 if c.type=="CHANNEL" and not A.ChannelMatches(c) then A.detail="频道身份无法核对，请重新选择目标频道"; A.Refresh(); return end
 if c.type=="BN_WHISPER" and (not validBNID(c.bnAccountID) or type(BNSendWhisper)~="function") then
  if not A.WhisperFail(p,"战网私聊接口或账号不可用") then A.State("READY","战网私聊接口或账号不可用") end;return
 end
 p.submitted=true; p.sentAt=GetTime()
 if p.automatic then A.db.sentTimes[#A.db.sentTimes+1]=time(); A.db.lastAttempt=time() end
 local ok,err
 if c.type=="BN_WHISPER" then ok,err=pcall(BNSendWhisper,c.bnAccountID,p.reply)
 else ok,err=pcall(SendChatMessage,p.reply,c.type,nil,c.type=="WHISPER" and c.target or c.type=="CHANNEL" and c.number or nil) end
 if not ok then A.State("READY","发送失败："..clean(err)); return end
 A.detail="已调用发送，等待聊天事件确认"; A.Refresh()
end
function A.Command(input)
 local cmd,arg=input:match("^(%S*)%s*(.-)$")
 if (cmd=="ping" or cmd=="rx" or cmd=="fail" or cmd=="commit" or cmd=="keywords") and not A.bridgeExecuting then A.State("OFFLINE","旧聊天桥接已禁用，请使用新版助手"); return end
 if cmd=="rx" then local s,id,b=arg:match("^(%d+) (%d+) ([A-Za-z0-9+/=]+)$"); if s then A.Receive(s,id,b) end
 elseif cmd=="ping" then
  local s,mode,cool,limit=arg:match("^(%d+) (%w+) (%d+) (%d+)$")
  if s~=A.session then return end
  A.lastBridge=mode=="on" and GetTime() or 0
  if cool then A.db.cooldown=math.max(0,tonumber(cool)); A.db.hourlyLimit=math.max(0,tonumber(limit)) end
  if mode~="on" then A.State("OFFLINE","助手暂停") elseif A.status=="OFFLINE" and not (A.pending and A.pending.submitted and not A.pending.confirmed) then A.State("IDLE","助手已连接") end
 elseif cmd=="keywords" then local s,b=arg:match("^(%d+) ([A-Za-z0-9+/=]+)$"); if s==A.session then local t=A.Unbase64(b); if t then A.db.keywords={}; for w in t:gmatch("[^,]+") do A.db.keywords[#A.db.keywords+1]=w end; A.Refresh() end end
 elseif cmd=="fail" then local s,id=arg:match("^(%d+) (%d+)"); if s==A.session and A.pending and tonumber(id)==A.pending.id then if not A.WhisperFail(A.pending,"私聊生成失败") then A.State("OFFLINE","生成失败，查看助手日志") end end
 elseif cmd=="commit" then local s,id=arg:match("^(%d+) (%d+)$"); if s==A.session and A.pending and tonumber(id)==A.pending.id and A.pending.automatic and A.AutoEnabled(A.pending) then A.Send() end
 elseif cmd=="cancel" then A.Cancel()
 elseif cmd=="scene" then A.GenerateScene(arg)
 elseif cmd=="signal" then A.SignalButton(arg)
 elseif cmd=="generate" then A.Generate()
 elseif cmd=="auto" then A.SetMasterAuto(arg=="on" or (arg~="off" and not A.MasterAutoEnabled()))
 elseif cmd=="whisper" then A.SetWhisperAuto(arg=="on" or (arg~="off" and not A.db.whisperAuto))
 elseif cmd=="events" then if A.ToggleActivityPanel then A.ToggleActivityPanel() end
 elseif cmd=="font" then A.FontDiagnostic()
 elseif cmd=="settings" then A.frame:Show()
 else if A.ToggleChatDock then A.ToggleChatDock() elseif A.frame:IsShown() then A.frame:Hide() else A.frame:Show() end end
end
function A.Start()
 if A.startAttempted then return end
 A.startAttempted=true;A.startupErrors={}
 local function step(name,fn)
  local ok,err=pcall(fn)
  if not ok then
   A.startupErrors[#A.startupErrors+1]=name..": "..tostring(err)
   A.status="OFFLINE";A.detail="启动失败："..A.startupErrors[#A.startupErrors]
   if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage("大肥鱼 "..A.version.." "..A.detail) end
  end
  return ok
 end
 if not step("设置",A.Init) then return end
 step("设置面板",A.MakePanel)
 if not A.bridgeInitError then step("通信接收",A.MakeReceiver) end
 if A.MakeChatDock then step("聊天工具条",A.MakeChatDock) end
 step("界面刷新",A.Refresh)
end
-- Conversation-isolated whisper batches. One in-flight bridge request, fair per-person queue.
function A.WhisperInit()
 if A.db.whisperAuto==nil then A.db.whisperAuto=true end
 A.whisperJobs=A.whisperJobs or {};A.whisperUncertain=A.whisperUncertain or {};A.whisperTicket=A.whisperTicket or 0
end
function A.WhisperCount()
 local n=0;for _ in pairs(A.whisperJobs or {}) do n=n+1 end;return n
end
local function whisperTicket(q)
 if not q.ticket then A.whisperTicket=A.whisperTicket+1;q.ticket=A.whisperTicket end
end
function A.RouteAvailable(c)
 if not c then return false end
 local function yes(fn,...)
  if type(fn)~="function" then return false end
  local ok,value=pcall(fn,...);return ok and readable(value) and value==true
 end
 if c.type=="PARTY" then return yes(IsInGroup) end
 if c.type=="RAID" then return yes(IsInRaid) end
 if c.type=="INSTANCE_CHAT" then return LE_PARTY_CATEGORY_INSTANCE and yes(IsInGroup,LE_PARTY_CATEGORY_INSTANCE) or false end
 return true
end
function A.PublicRouteAllowed(c)
 local key=A.db and (A.db.targetKey or A.current)
 return c and not privateType(c.type) and c.key==key and A.db.selected[c.key]==true and A.RouteAvailable(c) or false
end
function A.IsRecruitment(c,text)
 if not c or c.type~="CHANNEL" then return false end
 local t=clean(text):lower():gsub("%s","")
 for _,word in ipairs({"求组","求带","招募","公会招","公会收人","代练","代打","带刷","来dps","来t","来奶","缺t","缺奶","缺dps","招dps","招坦","来坦","来治疗"}) do
  if t:find(word,1,true) then return true end
 end
 return false
end
function A.UnrequestedPublicOffer(p,text)
 if not p or not p.automatic or p.mode~="public" then return false end
 local t=clean(text):lower():gsub("%s","")
 for _,word in ipairs({"求组","求带","带我","拉我","组我","给我","送我","借我","我加入","我报名","我就来","我就去","管饭","有鱼干吗"}) do
  if t:find(word,1,true) then return true end
 end
 return false
end
function A.ReplyRouteChanged()
 for key in pairs(A.publicJobs or {}) do if not A.PublicRouteAllowed(A.channels[key]) then A.publicJobs[key]=nil end end
 A.queuedSignal=nil
 local p=A.pending;local key=A.db.targetKey or A.current
 if p and not privateType(p.channel.type) and not p.submitted and p.channel.key~=key then
  A.pending=nil;A.prepared=nil;A.requestCounter=(A.requestCounter or 0)+1
  A.status=A.lastBridge>0 and GetTime()-A.lastBridge<=75 and "IDLE" or "OFFLINE"
  A.detail="回复目标已变化：取消旧频道待发内容，不转发到新频道"
 end
end

function A.ContextFor(c)
 local out=A.Array();for i=math.max(1,#c.messages-7),#c.messages do out[#out+1]=c.messages[i] end;return out
end
function A.WhisperStale(p)
 return p and p.mode=="whisper" and (not A.db.whisperAuto or p.whisperRevision~=(p.channel.whisperRevision or 0))
end
function A.WhisperRequeue(p)
 if not p or p.mode~="whisper" or p.submitted then return end
 local q=A.whisperJobs[p.channel.key]
 if q and q.requestId==p.id then
  q.inFlight=false;q.requestId=nil;q.requireQuiet=true;q.first=q.first or GetTime();q.changed=q.changed or GetTime();whisperTicket(q)
 end
 if A.pending==p then A.pending=nil;A.prepared=nil;A.State("IDLE","私聊有新消息，合并后再回复") end
end
function A.QueueWhisper(c)
 if not A.MasterAutoEnabled() then return end
 if not A.db.whisperAuto then return end
 c.whisperRevision=(c.whisperRevision or 0)+1
 local q=A.whisperJobs[c.key]
 if not q then q={key=c.key};A.whisperJobs[c.key]=q end
 q.first=q.first or GetTime();q.changed=GetTime()
 if not q.inFlight then whisperTicket(q) end
 local p=A.pending
 if p and p.mode=="whisper" and p.channel==c and A.status=="READY" and not p.submitted then A.WhisperRequeue(p) end
 A.whisperDiagnostic="合并私聊 · "..A.WhisperCount().." 人"
end
function A.WhisperFinish(p)
 if not p or p.mode~="whisper" then return end
 local q=A.whisperJobs[p.channel.key]
 if not q or q.requestId~=p.id then return end
 q.inFlight=false;q.requestId=nil
 if q.first and A.db.whisperAuto then whisperTicket(q) else A.whisperJobs[p.channel.key]=nil end
 A.whisperDiagnostic="私聊待处理 · "..A.WhisperCount().." 人"
end
function A.WhisperFail(p,reason)
 if p and p.mode=="public" then return A.PublicFail(p,reason) end
 if not p or p.mode~="whisper" then return false end
 A.WhisperFinish(p)
 if A.pending==p then A.pending=nil;A.prepared=nil end
 A.whisperDiagnostic=reason.."；其他会话继续"
 A.State(A.lastBridge>0 and GetTime()-A.lastBridge<=75 and "IDLE" or "OFFLINE",A.whisperDiagnostic)
 return true
end
function A.SetWhisperAuto(value)
 A.db.whisperAuto=value==true
 if not A.db.whisperAuto then
  A.whisperJobs={}
  local p=A.pending;if p and p.mode=="whisper" and not p.submitted then A.Cancel() end
 end
 A.whisperDiagnostic=A.db.whisperAuto and "自动私聊已开启" or "自动私聊已关闭";A.Refresh()
end
function A.BNWhisperChannel(name,id)
 if not validBNID(id) then A.whisperDiagnostic="战网私聊缺少可读账号ID，未猜测目标";A.whisperDirty=true;return nil end
 local key="BN_WHISPER:"..tostring(id);local c=A.channels[key]
 if not c then
  c={key=key,type="BN_WHISPER",target=tostring(id),bnAccountID=id,messages={}}
  A.channels[key]=c;A.order[#A.order+1]=key
 end
 local label=readable(name) and type(name)=="string" and clean(name) or "战网好友"
 c.name="战网私聊 · "..label;c.displayName=label;return c
end
function A.WhisperChannel(name)
 local c=A.channels["WHISPER:"..name];if c then return c end
 -- An unqualified echo may omit realm. Resolve only when unambiguous.
 if name:find("-",1,true) then return nil end
 local found
 for _,ch in pairs(A.channels) do
  if ch.type=="WHISPER" and ch.target:match("^[^-]+") == name then if found then return nil end;found=ch end
 end
 return found
end
function A.WhisperOutgoing(text,name,bnSenderID,isBN)
 if not readable(text) or not readable(name) then return end
 if type(name)~="string" or name=="" then return end
 text=clean(text);if text=="" then return end
 local c=isBN and A.BNWhisperChannel(name,bnSenderID) or nil
 if isBN and not c then return end
 if not isBN then c=A.WhisperChannel(name) end
 if not c then
  -- Do not attribute an ambiguous realm-less echo to any existing conversation.
  if not name:find("-",1,true) then for _,ch in pairs(A.channels) do if ch.type=="WHISPER" and ch.target:match("^[^-]+") == name then return end end end
  local key="WHISPER:"..name;c={key=key,type="WHISPER",name="悄悄话 · "..name,target=name,messages={}};A.channels[key]=c;A.order[#A.order+1]=key
 end
 if c.lastOutgoing==text and GetTime()-(c.lastOutgoingAt or 0)<1 then return end
 c.lastOutgoing=text;c.lastOutgoingAt=GetTime()
 local p=A.pending;local ack=p and p.channel==c and p.submitted and p.reply==text and p or nil
 local uncertain=A.FindUnconfirmed(c,text)
 if not ack and uncertain and uncertain.reply==text then ack=uncertain end
 local n,r=UnitFullName("player");n=n or "我";r=r or GetRealmName() or ""
 A.sequence=A.sequence+1;c.messages[#c.messages+1]={speaker=n..(r~="" and "-"..r or ""),text=A.Cut(text,240),seq=A.sequence,key=c.key,label=c.name,outgoing=true}
 if #c.messages>40 then table.remove(c.messages,1) end
 if ack then
  if ack==A.pending then A.ClearSentPreview(ack)
  else A.ResolveUnconfirmed(ack);A.WhisperFinish(ack) end
 else
  -- A real manual reply takes over this conversation, never any other sender's queue.
  c.whisperRevision=(c.whisperRevision or 0)+1;A.whisperJobs[c.key]=nil
  if p and p.mode=="whisper" and p.channel==c and not p.submitted then A.pending=nil;A.prepared=nil;A.State("IDLE","你已接话，取消这段自动私聊") end
 end
 A.Refresh()
end
-- A missing ACK is per request: retain evidence without blocking new work or replaying old content.
function A.FindUnconfirmed(c,text)
 if not c then return nil end
 for _,old in ipairs(A.unconfirmedHistory or {}) do
  if not old.confirmed and old.channel.key==c.key and old.reply==text then return old end
 end
 local old=A.whisperUncertain and A.whisperUncertain[c.key]
 if old and not old.confirmed and old.reply==text then return old end
end
function A.ResolveUnconfirmed(old)
 if not old then return end
 old.confirmed=true;old.reply=nil
 if A.whisperUncertain and A.whisperUncertain[old.channel.key]==old then A.whisperUncertain[old.channel.key]=nil end
 for i=#(A.unconfirmedHistory or {}),1,-1 do if A.unconfirmedHistory[i]==old then table.remove(A.unconfirmedHistory,i) end end
end
function A.IsAddonNotice(text)
 local t=clean(text):gsub("{[rR][tT]%d+}",""):match("^%s*(.-)%s*$"):lower()
 return t:find("^questie%s*:")~=nil
end
function A.IgnorePublicMessage(c,text) return A.IsAddonNotice(text) or A.IsRecruitment(c,text) end

function A.ParkUnconfirmed()
 local p=A.pending
 if not p or not p.submitted or p.confirmed or GetTime()-(p.sentAt or GetTime())<=5 then return end
 A.whisperUncertain=A.whisperUncertain or {};A.whisperUncertain[p.channel.key]=p
 A.unconfirmedHistory=A.unconfirmedHistory or {};A.unconfirmedHistory[#A.unconfirmedHistory+1]=p
 -- Bound retained diagnostic records, not message frequency. Old requests are never queued again.
 if #A.unconfirmedHistory>128 then local old=table.remove(A.unconfirmedHistory,1);if A.whisperUncertain[old.channel.key]==old then A.whisperUncertain[old.channel.key]=nil end end
 A.WhisperFinish(p)
 p.recent=nil;p.last=nil;A.pending=nil;A.prepared=nil
 A.State(A.lastBridge>0 and GetTime()-A.lastBridge<=75 and "IDLE" or "OFFLINE","上一条结果未知，已保留记录且不重发；新消息和手动生成可继续")
end
function A.UnconfirmedCount()
 local n=0;local seen={};for _,p in ipairs(A.unconfirmedHistory or {}) do if not p.confirmed then n=n+1;seen[p]=true end end;for _,p in pairs(A.whisperUncertain or {}) do if not p.confirmed and not seen[p] then n=n+1 end end;return n
end
local function whisperWait(reason)
 if A.whisperDiagnostic~=reason then A.whisperDiagnostic=reason;A.Refresh() end
end
function A.PumpWhispers()
 if not A.MasterAutoEnabled() then return end
 if not A.db then return end
 A.ParkUnconfirmed()
 if not A.db.whisperAuto then return end
 if A.whisperDirty then A.whisperDirty=false;A.Refresh() end
 if A.WhisperCount()==0 then return end
 if A.ProfessionBusy and A.ProfessionBusy() then whisperWait("私聊等待：专业窗口打开");return end
 local p=A.pending
 if p and (A.status=="GENERATING" or A.status=="READY" or p.submitted and not p.confirmed) then
  whisperWait(p.mode=="whisper" and "私聊处理中，其他会话排队" or "私聊等待：当前生成/待发草稿");return
 end
 if A.lastBridge==0 or GetTime()-A.lastBridge>75 then whisperWait("私聊等待：助手连接恢复");return end
 if type(GetCurrentKeyBoardFocus)=="function" and GetCurrentKeyBoardFocus()~=nil then whisperWait("私聊等待：输入框关闭后继续");return end
 local chosen
 for key,q in pairs(A.whisperJobs) do
  if not q.inFlight and q.ticket and q.changed then
   local quiet=GetTime()-q.changed>=1.2
   local ready=quiet or (not q.requireQuiet and GetTime()-(q.first or q.changed)>=4)
   if ready and (not chosen or q.ticket<chosen.ticket) then chosen=q end
  end
 end
 if not chosen then whisperWait("私聊等待：合并消息或该会话回执");return end
 local c=A.channels[chosen.key];if not c then A.whisperJobs[chosen.key]=nil;return end
 A.Generate(chosen.key,true,nil,"whisper")
 p=A.pending
 if p and p.mode=="whisper" and p.channel==c and A.status=="GENERATING" then
  p.whisperRevision=c.whisperRevision or 0
  chosen.inFlight=true;chosen.requestId=p.id;chosen.ticket=nil;chosen.first=nil;chosen.changed=nil;chosen.requireQuiet=false
  A.whisperDiagnostic="正在回复 · "..(c.displayName or c.target);A.Refresh()
 end
end

-- Contextual public chat: selected destinations only, one batch per channel.
-- Quiet time merges a burst; it is not a post-send cooldown or hourly quota.
A.publicJobs={};A.publicTicket=0;A.publicReceived=0
function A.PublicContext(c)
 local all={};for _,m in ipairs(c.messages) do if not A.IgnorePublicMessage(c,m.text) then all[#all+1]=m end end
 local out=A.Array();for i=math.max(1,#all-7),#all do out[#out+1]=all[i] end;return out
end
function A.PublicCount() local n=0;for _ in pairs(A.publicJobs) do n=n+1 end;return n end
function A.PublicStale(p)
 return p and p.mode=="public" and (not A.db.auto or not A.PublicRouteAllowed(p.channel) or p.publicRevision~=(p.channel.publicRevision or 0))
end
function A.PublicRequeue(p)
 if not p or p.mode~="public" or p.submitted then return end
 if not A.db.auto or not A.PublicRouteAllowed(p.channel) then A.publicJobs[p.channel.key]=nil end
 if A.pending==p then A.pending=nil;A.prepared=nil;A.State("IDLE","频道消息已更新，按最新上下文判断") end
end
function A.PublicFail(p,reason)
 if not p or p.mode~="public" then return false end
 if A.pending==p then A.pending=nil;A.prepared=nil end
 A.publicDiagnostic="频道生成失败；新消息可继续，不重试刷屏";A.State("IDLE",A.publicDiagnostic);return true
end
function A.SetPublicAuto(value)
 A.db.auto=value==true
 if not A.db.auto then
  A.publicJobs={};local p=A.pending
  if p and p.mode=="public" and not p.submitted then A.pending=nil;A.prepared=nil;A.State("IDLE","频道自动回复已关闭") end
 end
 A.publicDiagnostic=A.db.auto and "勾选频道按上下文接话，无需关键词" or "频道自动回复已关闭"
 A.detail=A.publicDiagnostic;A.Refresh()
end
function A.QueuePublic(c)
 if not A.MasterAutoEnabled() then return end
 if not A.db.auto or not A.PublicRouteAllowed(c) then return end
 if A.IgnorePublicMessage(c,c.messages[#c.messages] and c.messages[#c.messages].text or "") then A.publicDiagnostic="插件播报及招募广告不自动接话";return end
 A.publicReceived=A.publicReceived+1;c.publicRevision=(c.publicRevision or 0)+1
 local q=A.publicJobs[c.key]
 if not q then A.publicTicket=A.publicTicket+1;q={key=c.key,ticket=A.publicTicket,first=GetTime()};A.publicJobs[c.key]=q end
 q.changed=GetTime();A.publicDiagnostic="合并频道聊天 · "..A.PublicCount().." 个频道"
 local p=A.pending;if p and p.mode=="public" and p.channel==c and A.status=="READY" and not p.submitted then A.PublicRequeue(p) end
end
function A.PublicOutgoing(typ,text,name,number,baseName)
 local key=typ=="CHANNEL" and "CHANNEL:"..tostring(number)..":"..clean(baseName) or typ
 local c=A.channels[key];if not c then return end
 local p=A.pending;local uncertain=A.FindUnconfirmed(c,text)
 local ack=(p and p.channel==c and p.submitted and p.reply==text) or (uncertain and uncertain.reply==text)
 -- Actual outgoing context only; never trigger generation from ourselves.
 if c.publicOutgoing==text and GetTime()-(c.publicOutgoingAt or 0)<1 then return end
 c.publicOutgoing=text;c.publicOutgoingAt=GetTime();A.sequence=A.sequence+1
 c.messages[#c.messages+1]={speaker=clean(name),text=A.Cut(text,240),seq=A.sequence,key=key,label=c.name,outgoing=true}
 if #c.messages>40 then table.remove(c.messages,1) end
 if not ack then
  c.publicRevision=(c.publicRevision or 0)+1;A.publicJobs[key]=nil
  if p and p.mode=="public" and p.channel==c and not p.submitted then A.pending=nil;A.prepared=nil;A.State("IDLE","你已接话，取消这段频道自动回复") end
 end
end
function A.PumpPublic()
 if not A.MasterAutoEnabled() then return end
 if not A.db then return end
 if not A.db.auto then A.publicJobs={};return end
 local chosen
 for key,q in pairs(A.publicJobs) do
  if not A.PublicRouteAllowed(A.channels[key]) then A.publicJobs[key]=nil
  elseif (GetTime()-q.changed>=1.2 or GetTime()-q.first>=4) and (not chosen or q.ticket<chosen.ticket) then chosen=q end
 end
 if not chosen then return end
 if A.ProfessionBusy and A.ProfessionBusy() then return end
 local p=A.pending;if p and (A.status=="GENERATING" or A.status=="READY" or p.submitted and not p.confirmed) then return end
 if A.lastBridge==0 or GetTime()-A.lastBridge>75 then return end
 if type(GetCurrentKeyBoardFocus)=="function" and GetCurrentKeyBoardFocus()~=nil then return end
 local c=A.channels[chosen.key];if not c then A.publicJobs[chosen.key]=nil;return end
 A.Generate(chosen.key,true,nil,"public");p=A.pending
 if p and p.mode=="public" and p.channel==c and A.status=="GENERATING" then
  p.publicRevision=c.publicRevision or 0;A.publicJobs[chosen.key]=nil
  A.publicDiagnostic="上下文判断 · "..c.name;A.Refresh()
 end
end

local e=CreateFrame("Frame");A.chatEventFrame=e
e:RegisterEvent("ADDON_LOADED")
e:RegisterEvent("PLAYER_ENTERING_WORLD")
for typ in pairs(types) do if typ=="BN_WHISPER" then A.bnWhisperSupported=pcall(e.RegisterEvent,e,"CHAT_MSG_"..typ) else e:RegisterEvent("CHAT_MSG_"..typ) end end
e:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
pcall(e.RegisterEvent,e,"CHAT_MSG_BN_WHISPER_INFORM")
A.signalEventAvailable=pcall(e.RegisterEvent,e,"CHAT_MSG_PING")
e:SetScript("OnEvent",function(_,event,...)
 if event=="ADDON_LOADED" then if (...)=="DaFeiYu" then A.Start() end; return end
 if not A.db then return end
 if event=="PLAYER_ENTERING_WORLD" then
  if not A.fontRecoveryScheduled then
   A.fontRecoveryScheduled=true
   if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(1,function() if A.bridgeInitError then A.RetryPixelBridge() end end) end
  end
  return
 end
 if event=="CHAT_MSG_PING" then local text,name,_,_,_,_,_,_,_,_,lineID,guid=...; local ok=pcall(A.OnPing,text,name,lineID,guid); if not ok then A.SignalNote("客户端信号处理失败，已安全跳过") end; return end
 if event=="CHAT_MSG_BN_WHISPER_INFORM" then local text,name=...;local id=select(13,...);A.WhisperOutgoing(text,name,id,true);return end
 if event=="CHAT_MSG_WHISPER_INFORM" then local text,name=...;A.WhisperOutgoing(text,name);return end
 A.Chat(event,...)
end)
function A.GenerationProgress(p)
 local seconds=math.floor(GetTime()-p.created)
 if A.prepared and A.prepared.kind=="rx" then return "回复已接收，正在确认" end
 if A.receiverActive then return "正在接收 · "..#(A.receiverBuffer or "").." 字节 · 已等 "..seconds.." 秒" end
 if A.bridgeError and A.bridgeError~="" then return "回传待恢复 · 已等 "..seconds.." 秒；无需重连" end
 return "等待生成或回传 · 已等 "..seconds.." 秒；可点丢弃取消"
end
local elapsed=0
e:SetScript("OnUpdate",function(_,dt)
 if not A.db or A.bridgeInitError then return end; elapsed=elapsed+dt; if elapsed<0.25 then return end; elapsed=0
 A.UpdateWindowLayers()
 A.ParkUnconfirmed()
 if A.ProfessionBusy and A.ProfessionBusy() then if A.Publish then A.Publish() end;return end
 A.PumpWhispers(); A.PumpPublic(); if not (A.pending and A.pending.mode=="whisper" and not A.pending.confirmed) then A.PumpSignal(); if A.PumpActivities then A.PumpActivities() end end
 if A.BindingsReady and not A.BindingsReady() and not InCombatLockdown() then A.SetupBindings() end
 local p=A.pending
 if p and A.status=="GENERATING" and GetTime()-p.created>40 then if not A.WhisperFail(p,"私聊生成超时") then A.State("OFFLINE","生成超时") end
 elseif p and p.submitted and not p.confirmed and GetTime()-p.sentAt>5 and A.detail~="发送未确认，请查看聊天；不会自动重发" then A.detail="发送未确认，请查看聊天；不会自动重发"; A.Refresh()
 elseif A.lastBridge>0 and GetTime()-A.lastBridge>75 and A.status~="OFFLINE" then A.State("OFFLINE","暂未收到心跳，回到游戏前台后自动恢复") end
 if p and A.status=="GENERATING" and GetTime()-p.created>3 then
  local detail=A.GenerationProgress(p)
  if A.detail~=detail then A.detail=detail; A.Refresh() end
 end
 if A.Publish then A.Publish() end
end)
SLASH_DAFEIYU1="/dfy"; SlashCmdList.DAFEIYU=function(s) A.Command(s) end
