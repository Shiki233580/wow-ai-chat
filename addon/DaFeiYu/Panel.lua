local A=DFY
local function json(v)
 if type(v)=="string" then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')..'"' end
 if type(v)=="number" then return tostring(v) end
 if type(v)=="boolean" then return v and 'true' or 'false' end
 if type(v)=="table" then
  local a={}; if v[1]~=nil or getmetatable(v)==A.ArrayMeta then for _,x in ipairs(v) do a[#a+1]=json(x) end; return '['..table.concat(a,',')..']' end
  for k,x in pairs(v) do a[#a+1]=json(k)..':'..json(x) end; table.sort(a); return '{'..table.concat(a,',')..'}'
 end
 return 'null'
end
local function label(parent,text,x,y,font)
 local f=parent:CreateFontString(nil,"OVERLAY",font or "GameFontNormal"); f:SetPoint("TOPLEFT",x,y); f:SetText(text); return f
end
local function button(parent,text,x,y,w,click)
 local b=CreateFrame("Button",nil,parent,"BackdropTemplate"); b:SetSize(w or 90,28); b:SetPoint("BOTTOMLEFT",x,y)
 b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1}); b:SetBackdropColor(.08,.18,.22,.95); b:SetBackdropBorderColor(.2,.65,.65,1)
 local t=b:CreateFontString(nil,"OVERLAY","GameFontNormal"); t:SetPoint("CENTER"); t:SetText(text); b.label=t
 b:EnableMouse(true); b:RegisterForClicks("LeftButtonUp")
 b:SetScript("OnEnter",function(self) self:SetBackdropColor(.13,.30,.34,1) end)
 b:SetScript("OnLeave",function(self) self:SetBackdropColor(.08,.18,.22,.95) end)
 b:SetScript("OnClick",function()
  A.uiClickCount=(A.uiClickCount or 0)+1
  local ok,err=pcall(click)
  A.uiFeedback=text.." #"..A.uiClickCount.."："..(ok and (A.detail or "已执行") or ("按钮出错："..tostring(err)))
  A.Refresh()
 end); return b
end
function A.MakePanel()
 local d=A.db
 local f=CreateFrame("Frame","DFYPanel",UIParent,"BackdropTemplate"); A.frame=f
 f:SetSize(d.width,d.height); f:SetPoint("TOPLEFT",UIParent,"TOPLEFT",d.x or 260,d.y or -180)
 A.NormalWindow(f,2); f:SetMovable(true); f:SetResizable(true); f:SetClampedToScreen(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
 f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1}); f:SetBackdropColor(.025,.055,.075,.96); f:SetBackdropBorderColor(.15,.6,.65,1)
 local function save() d.width=f:GetWidth(); d.height=f:GetHeight(); d.x=f:GetLeft(); d.y=f:GetTop()-UIParent:GetHeight() end
 f:SetScript("OnDragStart",function() f:StartMoving() end); f:SetScript("OnDragStop",function() f:StopMovingOrSizing(); save() end)
 if f.SetResizeBounds then f:SetResizeBounds(540,460,1100,900) end
 f:SetScript("OnSizeChanged",function() if A.context then A.context:SetWidth(f:GetWidth()-60); A.reply:SetWidth(f:GetWidth()-38); if A.statusLabel then A.statusLabel:SetWidth(f:GetWidth()-40) end end end)
 label(f,"篝火大肥鱼 · AI 聊天",16,-14,"GameFontNormalLarge")
 local close=button(f,"×",0,0,28,function() f:Hide() end); close:ClearAllPoints(); close:SetPoint("TOPRIGHT",-8,-8)
 label(f,"出现过的频道（勾选后采集上下文；点击名称锁定唯一公开发言频道）",16,-46)
 local sc=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate"); sc:SetPoint("TOPLEFT",16,-70); sc:SetPoint("TOPRIGHT",-30,-70); sc:SetHeight(108)
 local content=CreateFrame("Frame",nil,sc); content:SetSize(480,110); sc:SetScrollChild(content); A.channelContent=content; A.checks={}
 label(f,"最近 8 条 · 仅所选频道",16,-208)
 local cs=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate"); cs:SetPoint("TOPLEFT",16,-230); cs:SetPoint("BOTTOMRIGHT",-30,162)
 local ct=CreateFrame("EditBox",nil,cs); ct:SetMultiLine(true); ct:SetAutoFocus(false); ct:SetFontObject(GameFontHighlight); ct:SetTextColor(1,1,1,1); ct:SetJustifyH("LEFT"); ct:SetJustifyV("TOP"); ct:SetWidth(f:GetWidth()-60); ct:SetHeight(160); ct:SetScript("OnEscapePressed",function(self) self:ClearFocus() end); cs:SetScrollChild(ct); A.context=ct
 A.targetLabel=label(f,"",16,-184)
 local reply=CreateFrame("EditBox",nil,f,"BackdropTemplate"); reply:SetPoint("BOTTOMLEFT",16,76); reply:SetSize(f:GetWidth()-38,60); reply:SetMultiLine(true); reply:SetAutoFocus(false); reply:SetFontObject(ChatFontNormal); reply:SetTextInsets(8,8,5,5); reply:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); reply:SetBackdropColor(.08,.12,.16,1); reply:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
 reply:SetScript("OnTextChanged",function(self,user) if user and A.pending and A.status=="READY" and not A.pending.submitted then A.pending.reply=A.FormatPendingReply(A.pending,self:GetText():gsub('[\r\n|]',' ')) end end); A.reply=reply
 local caption=label(f,"待发送回复",16,0); caption:ClearAllPoints(); caption:SetPoint("BOTTOMLEFT",16,141)
 button(f,"生成",16,38,88,function() A.Generate() end)
 button(f,"发送",112,38,88,function() A.reply:ClearFocus(); A.Send() end)
 A.autoButton=button(f,"自动：关",208,38,112,function() A.SetMasterAuto(not A.MasterAutoEnabled()) end)
 A.connectButton=button(f,"自动连接",328,38,112,function() end); A.connectButton:Disable()
 A.waterButton=button(f,"讨水",448,38,72,function() A.AskTargetForWater() end)
 A.statusLabel=label(f,"",16,0); A.statusLabel:ClearAllPoints(); A.statusLabel:SetPoint("BOTTOMLEFT",16,3); A.statusLabel:SetWidth(600); A.statusLabel:SetHeight(32); A.statusLabel:SetJustifyH("LEFT")
 local grip=button(f,"◢",0,0,24,function() end); grip:ClearAllPoints(); grip:SetPoint("BOTTOMRIGHT",-2,2); grip:SetScript("OnMouseDown",function() f:StartSizing("BOTTOMRIGHT") end); grip:SetScript("OnMouseUp",function() f:StopMovingOrSizing(); save() end)
 UISpecialFrames[#UISpecialFrames+1]="DFYPanel"
 local ok,err=pcall(A.MakePixelBridge)
 if not ok then A.DisablePixelBridge(err) end
 A.Refresh(); if d.uiMode=="chat" then f:Hide() else f:Show() end
end
-- A renderer failure must not prevent the settings panel/chat dock from loading.
function A.DisablePixelBridge(err)
 if A.bridgeInitError then return end
 A.bridgeInitError="通信渲染失败："..tostring(err)
 A.status="OFFLINE";A.detail=A.bridgeInitError;A.lastBridge=0
 if A.bridge then A.bridge:Hide() end
 A.pixels=nil;A.pixelValues=nil;A.bridgePayload=nil;A.lastPacket=nil;A.bridgeDirtyRows={}
 if A.CloseReceiver then pcall(A.CloseReceiver,true) end
 if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff9966大肥鱼 1.18.11："..A.bridgeInitError.."；界面仍可使用。|r")
 end
end
local pixelFontPath="Interface\\AddOns\\DaFeiYu\\BridgePixelV2.ttf"
local function loadPixelFont(font)
 -- Never substitute a normal font: its glyphs would silently corrupt the wire image.
 local notes={}
 for _,flags in ipairs({"MONOCHROME",""}) do
  local called,result=pcall(font.SetFont,font,pixelFontPath,2,flags)
  local valid=called and result~=false
  -- Native GetFont verifies the actual loaded resource, not merely the return value.
  if valid and type(font.GetFont)=="function" then
   local read,path,size=pcall(font.GetFont,font)
   valid=read and type(path)=="string" and path:lower():gsub("/","\\")==pixelFontPath:lower() and type(size)=="number" and math.abs(size-2)<.01
  end
  notes[#notes+1]=(flags~="" and flags or "plain")..":"..(valid and "ok" or (called and tostring(result) or "error"))
  if valid then A.bridgeFontDiagnostic=table.concat(notes,",");return true end
 end
 A.bridgeFontDiagnostic=table.concat(notes,",");return false
end
local function rowFontValid(f)
 if not f or type(f.GetFont)~="function" then return false end
 local ok,path,size=pcall(f.GetFont,f)
 return ok and type(path)=="string" and path:lower():gsub("/","\\")==pixelFontPath:lower() and type(size)=="number" and math.abs(size-2)<.01
end
function A.VerifyBridgeFonts(force)
 if not force and A.fontCheckAt and GetTime()-A.fontCheckAt<1 then return end
 A.fontCheckAt=GetTime();A.rowFontRepairs=A.rowFontRepairs or {}
 for i,f in ipairs(A.bridgeRows or {}) do
  if not rowFontValid(f) then
   -- Repair only our own rows once. Never hook/disable another addon's font methods.
   if A.rowFontRepairs[i] or not loadPixelFont(f) or not rowFontValid(f) then
    local _,path=pcall(f.GetFont,f)
    error("通信行"..i.."字体未生效："..tostring(path).."；输入 /dfy font 查看诊断")
   end
   A.rowFontRepairs[i]=true
  end
 end
end
function A.RetryPixelBridge()
 if not A.bridgeInitError then return true end
 A.bridgeInitError=nil;A.lastBridge=0;A.rowFontRepairs={};A.fontCheckAt=nil
 local ok,err=pcall(A.MakePixelBridge)
 if not ok then A.DisablePixelBridge(err);A.Refresh();return false end
 local ready,why=pcall(A.MakeReceiver)
 if not ready then A.DisablePixelBridge(why);A.Refresh();return false end
 A.State("OFFLINE","通信字体已恢复，等待助手真实心跳")
 return not A.bridgeInitError
end
function A.FontDiagnostic()
 if not A.bridgeInitError then local ok,err=pcall(A.VerifyBridgeFonts,true);if not ok then A.DisablePixelBridge(err) end end
 if A.bridgeInitError then A.RetryPixelBridge() end
 local row=A.bridgeRows and A.bridgeRows[1];local path,size
 if row and type(row.GetFont)=="function" then local ok,p,h=pcall(row.GetFont,row);if ok then path,size=p,h end end
 local message="大肥鱼字体："..(A.bridgeFontDiagnostic or "未尝试").."；实际行="..tostring(path).."/"..tostring(size).."；"..(A.bridgeInitError or "等待助手真实心跳")
 if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage(message) end
 A.detail=message;A.Refresh()
end
function A.MakePixelBridge()
 -- Physical-pixel transport is noninteractive and behind normal windows.
 -- Occlusion invalidates the checksum/read; desktop waits and resumes when visible again.
 local b=A.bridge or CreateFrame("Frame",nil,UIParent); A.bridge=b; b:SetFrameStrata("BACKGROUND"); b:SetFrameLevel(0); b:SetToplevel(false)
 local _,physicalHeight=GetPhysicalScreenSize()
 b:SetScale(768/physicalHeight/UIParent:GetEffectiveScale()); b:SetSize(384,130); b:SetPoint("TOPLEFT",UIParent,"TOPLEFT",8,-8); b:EnableMouse(false)
 A.pixels={};A.pixelValues={};A.bridgePayload=nil;A.lastPacket=nil
 -- Native WoW font rendering advances 3px for each 2px glyph (observed 1px gap).
 -- Reserve all 128 glyph advances; 256px clips the packet and cannot be decoded.
 -- Keep 65 cached text rows instead of 8196 Texture regions.
 A.bridgeRows=A.bridgeRows or {};A.bridgeDirtyRows={};A.bridgeCells={}
 local shared
 if type(CreateFont)=="function" then
  A.pixelFont=A.pixelFont or CreateFont("DFYBridgePixelFont")
  if not loadPixelFont(A.pixelFont) then error("通信字体被客户端拒绝（"..A.bridgeFontDiagnostic.."）；输入 /dfy font 查看诊断") end
  shared=A.pixelFont
 end
 for row=0,64 do
  local f=A.bridgeRows[row+1] or b:CreateFontString(nil,"OVERLAY");A.bridgeRows[row+1]=f;f:SetPoint("TOPLEFT",row*0,-row*2);f:SetSize(384,2)
  if shared then f:SetFontObject(shared)
  elseif not loadPixelFont(f) then error("通信字体被客户端拒绝（"..A.bridgeFontDiagnostic.."）；输入 /dfy font 查看诊断") end
  if not rowFontValid(f) and (not loadPixelFont(f) or not rowFontValid(f)) then error("通信行字体载入失败；输入 /dfy font 查看诊断") end
  f:SetTextColor(1,1,1,1);f:SetJustifyH("LEFT");f:SetJustifyV("TOP");f:SetSpacing(0);f:SetShadowOffset(0,0);f:SetShadowColor(0,0,0,0)
  if f.SetWordWrap then f:SetWordWrap(false) end
  if f.SetNonSpaceWrap then f:SetNonSpaceWrap(false) end
  A.bridgeRows[row+1]=f;A.bridgeCells[row+1]={}
 end
 for i=0,8195 do
  local row=math.floor(i/128)+1;local column=i%128+1
  local t={};function t:SetColorTexture(r,g,blue,alpha)
   self.rgb={r,g,blue}
   local code=string.format("|cff%02x%02x%02xM|r",math.floor(r*255+.5),math.floor(g*255+.5),math.floor(blue*255+.5))
   if A.bridgeCells[row][column]~=code then A.bridgeCells[row][column]=code;A.bridgeDirtyRows[row]=true end
  end
  t:SetColorTexture(0,0,0,1);A.pixels[i+1]=t;A.pixelValues[i+1]=0
 end
 function A.FlushBridgeRows()
  A.VerifyBridgeFonts()
  for row in pairs(A.bridgeDirtyRows) do A.bridgeRows[row]:SetText(table.concat(A.bridgeCells[row]));A.bridgeDirtyRows[row]=nil end
 end
 for i=0,3 do A.pixels[i+1]:SetColorTexture(i*32/255,i*32/255,i*32/255,1) end
 b:Show()
end
function A.Render()
 if not A.frame then return end
 for i,key in ipairs(A.order) do
  local c=A.channels[key]; local row=A.checks[i]
  if not row then
   row=CreateFrame("CheckButton",nil,A.channelContent,"UICheckButtonTemplate"); row:SetSize(24,24); row:SetPoint("TOPLEFT",0,-(i-1)*26)
   local t=CreateFrame("Button",nil,A.channelContent); t:SetSize(420,24); t:SetPoint("LEFT",row,"RIGHT",4,0); t.text=t:CreateFontString(nil,"OVERLAY","GameFontHighlight"); t.text:SetPoint("LEFT"); t:SetScript("OnClick",function() A.DockSelectChannel(key,false) end); row.title=t
   row:SetScript("OnClick",function(self) A.db.selected[key]=self:GetChecked() and true or false; if A.db.selected[key] and not A.db.targetKey and not A.current then A.current=key;A.db.targetKey=key elseif not A.db.selected[key] and (A.db.targetKey==key or A.current==key) then A.db.targetKey=nil; A.current=nil end; A.ReplyRouteChanged();A.Refresh() end); A.checks[i]=row
  end
  row:SetChecked(A.db.selected[key]); row.title.text:SetText((A.current==key and "→ " or "")..c.name.." ("..#c.messages..")")
 end
 A.channelContent:SetHeight(math.max(110,#A.order*26))
 local lines={}; for _,m in ipairs(A.Recent()) do lines[#lines+1]="<"..m.label..">||"..m.speaker..": "..m.text end
 local txt=table.concat(lines,"\n"); if A.context:GetText()~=txt then A.context:SetText(txt); A.context:SetHeight(math.max(160,math.ceil(#txt/math.max(20,(A.frame:GetWidth()-60)/9))*18+#lines*18)); A.context:SetCursorPosition(0) end
 local p=A.pending; local r=p and p.reply or ""; if A.reply:GetText()~=r and not A.reply:HasFocus() then A.reply:SetText(r) end
 A.autoButton.label:SetText(A.MasterAutoEnabled() and "自动总控：开" or "自动总控：关")
 A.statusLabel:SetText(A.status.." · "..(A.bridgeInitError or (A.status=="OFFLINE" and A.bridgeError and A.bridgeError~="") and A.bridgeError or A.detail)..(A.uiFeedback and ("\n"..A.uiFeedback) or ""))
 A.targetLabel:SetText("目标："..(p and p.channel.name or A.current and A.channels[A.current].name or "未选择"))
end
function A.Packet()
 local p=A.pending; local n,r=UnitFullName("player"); n=n or ""; r=(r and r~="") and r or GetRealmName() or ""
 local v={session=A.session,player=n.."-"..r:gsub("%s",""),status=A.status,detail=A.detail,typing=GetCurrentKeyBoardFocus()~=nil,auto=A.AutoEnabled(p) or false,requestId=p and p.id or 0,submitted=p and p.submitted or false,confirmed=p and p.confirmed or false}
 v.addonVersion=A.version;v.bridgeFontDiagnostic=A.bridgeFontDiagnostic or "";v.publicDiagnostic=A.publicDiagnostic or "";v.publicQueued=A.PublicCount();v.publicReceived=A.publicReceived;v.whisperAuto=A.MasterAutoEnabled() and A.db.whisperAuto==true;v.sendUnconfirmed=A.UnconfirmedCount();v.whisperDiagnostic=A.whisperDiagnostic or "";v.whisperQueued=A.WhisperCount();v.whisperReceivedBN=A.whisperReceived and A.whisperReceived.BN_WHISPER or 0
 v.bridgeRevision=2; v.receiverProgressChecksum=A.receiverProgressChecksum or 0; v.craftGuardVersion=1; v.professionBusy=A.ProfessionBusy and A.ProfessionBusy() or false; v.protocol=8; v.replyMaxChars=48; v.bridgeTransport=A.bridgeTransport or "keys-v1"; v.bridgeDataKeys=A.bridgeDataKeys or A.Array(); v.bridgeRxDiagnostic=A.bridgeRxDiagnostic or ""; v.receiverLength=A.receiverActive and #(A.receiverBuffer or "") or 0; v.bridgeOpenMods=A.bridgeOpenMods or 0; v.bridgeExecuteMods=A.bridgeExecuteMods or 0; v.reconnectNonce=A.reconnectNonce or 0; v.bridgeOpenKey=A.bridgeOpenKey or 0; v.bridgeExecuteKey=A.bridgeExecuteKey or 0; v.combat=InCombatLockdown() and true or false; v.bindingsReady=A.BindingsReady and A.BindingsReady() or false
 v.receiverOpen=A.receiverActive or false
 v.receiverNonce=A.bridgeNonce or 0; v.bridgeAck=A.bridgeAck or 0; v.bridgeAckChecksum=A.bridgeAckChecksum or 0; v.bridgeError=A.bridgeError or ""
 v.bridgeReadyNonce=A.prepared and A.prepared.nonce or 0; v.bridgeReadyChecksum=A.prepared and A.prepared.checksum or 0
 if p then v.worldState=p.worldState;v.eventReply=p.eventReply or "";v.eventFlavor=p.eventFlavor or false;v.replyPrefix=A.ReplyPrefix(p.channel);v.eventKind=p.eventKind or "";v.generationMode=p.mode or "reply"; v.reply=p.reply or ""; v.automatic=p.automatic or false; v.channel=p.channel.type; v.target=p.channel.target or ""; v.channelNumber=p.channel.number or 0 end
 if p and A.status=="GENERATING" then
  v.speaker=p.last.speaker; v.text=p.last.text; v.recent=A.Array()
  for _,m in ipairs(p.recent) do v.recent[#v.recent+1]={speaker=A.Cut(m.speaker,40),text=A.Cut(m.text,120)} end
 end
 local encoded=json(v)
 -- Preserve eight conversation turns, shortening only oversized text fields.
 if #encoded>6136 and v.recent then
  for _,limit in ipairs({90,60,30}) do
   for _,m in ipairs(v.recent) do m.text=A.Cut(m.text,limit) end
   v.contextClipped=true;encoded=json(v);if #encoded<=6136 then break end
  end
 end
 return encoded
end
local function publishPixels()
 if not A.pixels then return end
 local _,height=GetPhysicalScreenSize(); local scale=768/math.max(1,height)/UIParent:GetEffectiveScale()
 if A.bridgeScale~=scale then A.bridgeScale=scale; A.bridge:SetScale(scale) end
 A.VerifyBridgeFonts()
 local s=A.Packet(); if s==A.lastPacket then return end
 if #s>6136 then error("通信数据超过容量，已停止绘制而不递归刷新") end
 A.lastPacket=s
 local sum=0; for i=1,#s do sum=(sum+s:byte(i)*i)%65536 end
 local data="DFY1"..string.char(math.floor(#s/256),#s%256,math.floor(sum/256),sum%256)..s
 -- Six payload bits per RGB cell; low levels avoid client brightness clipping.
 -- Four calibration cells let the desktop recover the actual displayed levels.
 local function cell(index,v)
  if A.pixelValues[index]==v then return end
  A.pixelValues[index]=v
  A.pixels[index]:SetColorTexture(math.floor(v/16)*32/255,math.floor(v/4)%4*32/255,v%4*32/255,1)
 end
 -- Clear a shorter packet tail, but never repaint unchanged or unused cells.
 local groups=math.ceil(math.max(#data,#(A.bridgePayload or ""))/3)
 A.bridgePayload=data
 for i=0,groups-1 do
  local a,b,c=data:byte(i*3+1,i*3+3); a=a or 0; b=b or 0; c=c or 0
  cell(i*4+5,math.floor(a/4)); cell(i*4+6,a%4*16+math.floor(b/16)); cell(i*4+7,b%16*4+math.floor(c/64)); cell(i*4+8,c%64)
 end
 if A.FlushBridgeRows then A.FlushBridgeRows() end
end

function A.Publish()
 if A.bridgeInitError then return end
 local ok,err=pcall(publishPixels)
 if not ok then A.DisablePixelBridge(err) end
end

-- Embedded ChatDock source: ChatDock.lua (reload-safe entry)
-- Chat-adjacent UI only. Never inserts into the game's ordinary chat input.
local A=DFY
local function tip(frame,title,body)
 if not GameTooltip then return end
 GameTooltip:SetOwner(frame,"ANCHOR_TOP"); GameTooltip:SetText(title)
 if body then GameTooltip:AddLine(body,1,1,1,true) end
 GameTooltip:Show()
end
local function skin(f)
 f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
 f:SetBackdropColor(.025,.055,.07,.94); f:SetBackdropBorderColor(.12,.48,.52,.9)
end
local function text(parent,value)
 local t=parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); t:SetText(value or ""); t:SetJustifyH("LEFT"); return t
end
local function button(parent,label,width,action,help)
 local b=CreateFrame("Button",nil,parent,"BackdropTemplate"); b:SetSize(width,24); skin(b); b:EnableMouse(true); b:RegisterForClicks("LeftButtonUp")
 b.label=text(b,label); b.label:SetPoint("CENTER")
 b:SetScript("OnClick",function()
  local ok,err=pcall(action)
  if not ok then A.detail="操作失败："..tostring(err) end
  A.Refresh()
 end)
 b:SetScript("OnEnter",function(self) self:SetBackdropColor(.09,.22,.25,1); tip(self,label,type(help)=="function" and help() or help) end)
 b:SetScript("OnLeave",function(self) self:SetBackdropColor(.025,.055,.07,.94); if GameTooltip then GameTooltip:Hide() end end)
 return b
end
local function clearDraft()
 if A.dockScene then A.dockScene:ClearFocus() end
 if A.dockDraft then A.dockDraft:ClearFocus() end
 if A.reply then A.reply:ClearFocus() end
 if A.context then A.context:ClearFocus() end
end
function A.ToggleChatDock()
 if not A.dock then return end
 A.db.dockVisible=not A.dock:IsShown()
 if A.db.dockVisible then A.dock:Show() else clearDraft(); A.dock:Hide(); if A.dockChannels then A.dockChannels:Hide() end end
end
function A.AttachChatDock()
 if not A.dock then return end
 A.db.dockDetached=false; A.dockAnchor=nil; A.LayoutChatDock()
end
function A.LayoutChatDock()
 A.UpdateWindowLayers()
 local f=A.dock; if not f then return end
 local chat=SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME or ChatFrame1
 local nativeBar=RurutiaChatBar and RurutiaChatBar:IsShown() and RurutiaChatBar or nil
 local anchor=nativeBar or chat
 local w=math.max(420,math.min(620,chat and chat:GetWidth() or 460))
 if A.db.dockDetached then
  w=A.db.dockWidth or 460
  if A.dockAnchor~="detached" then f:ClearAllPoints(); f:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",A.db.dockX or 30,A.db.dockY or 180); A.dockAnchor="detached" end
 elseif anchor then
  if A.dockAnchor~=anchor then f:ClearAllPoints(); f:SetPoint("BOTTOMLEFT",anchor,"TOPLEFT",0,nativeBar and 6 or 54); A.dockAnchor=anchor end
 elseif not A.dockAnchor then f:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",30,180); A.dockAnchor="fallback" end
 f:SetSize(w,A.db.dockExpanded and 232 or 44)
 local x=4
 for _,entry in ipairs({{A.dockToggle,32},{A.dockTarget,w-338},{A.dockGenerate,48},{A.dockSend,44},{A.dockAuto,60},{A.dockWater,44},{A.dockConnect,44},{A.dockSettings,30}}) do
  local b,width=entry[1],entry[2]; b:ClearAllPoints(); b:SetPoint("TOPLEFT",f,"TOPLEFT",x,-4); b:SetWidth(width); x=x+width+4
 end
 A.dockStatus:SetWidth(w-12); A.dockDraft:SetWidth(w-16); A.dockScene:SetWidth(w-96)
 if A.db.dockExpanded then A.dockPreview:Show() else A.dockScene:ClearFocus(); A.dockDraft:ClearFocus(); A.dockPreview:Hide() end
end
function A.SeedDockChannels()
 local function add(key,typ,name,number,base)
  if not A.channels[key] then A.channels[key]={key=key,type=typ,name=name,number=number,baseName=base or name,messages={}}; A.order[#A.order+1]=key end
 end
 for _,c in ipairs({{"SAY","说"},{"YELL","喊叫"},{"PARTY","小队"},{"RAID","团队"},{"GUILD","公会"},{"OFFICER","官员"}}) do add(c[1],c[1],c[2]) end
 if type(GetChannelList)=="function" then
  local list={GetChannelList()}
  for n=1,#list,3 do local id,name=list[n],list[n+1]
   if type(id)=="number" and id>0 and type(name)=="string" then add("CHANNEL:"..id..":"..name,"CHANNEL",id.."."..name,id,name) end
  end
 end
end
function A.DockChannelKeys()
 local keys={}; local filter=(A.dockFilter or ""):lower()
 for _,key in ipairs(A.order) do local c=A.channels[key]; if filter=="" or c.name:lower():find(filter,1,true) then keys[#keys+1]=key end end
 return keys
end
function A.DockSelectChannel(key,only)
 if not A.channels[key] then return end
 if only then for k in pairs(A.db.selected) do A.db.selected[k]=false end end
 A.db.selected[key]=true; A.current=key; A.db.targetKey=key;A.ReplyRouteChanged()
 A.detail=(only and "仅监听并回复：" or "回复目标：")..A.channels[key].name; A.Refresh()
end
function A.DockCycleChannel(delta)
 A.SeedDockChannels(); local keys=A.DockChannelKeys(); if #keys==0 then return end
 local index=0; for n,key in ipairs(keys) do if key==A.current then index=n; break end end
 A.DockSelectChannel(keys[((index-1+(delta>0 and -1 or 1))%#keys)+1],false)
end
function A.RenderDockChannels()
 local f=A.dockChannels; if not f or not f:IsShown() then return end
 local keys=A.DockChannelKeys()
 for index,key in ipairs(keys) do
  local row=A.dockRows[index]
  if not row then
   row=CreateFrame("CheckButton",nil,A.dockChannelContent,"UICheckButtonTemplate"); row:SetSize(24,24); row:SetPoint("TOPLEFT",0,-(index-1)*26)
   row.choose=button(A.dockChannelContent,"",280,function() end,"左键：锁定唯一公开发言频道，保留其他监听勾选。右键：只监听并回复此频道。菜单保持打开，可连续多选。")
   row.choose:RegisterForClicks("LeftButtonUp","RightButtonUp")
   row.choose:SetScript("OnClick",function(_,which) A.DockSelectChannel(row.channelKey,which=="RightButton") end)
   row.choose:SetPoint("LEFT",row,"RIGHT",2,0)
   row:SetScript("OnClick",function(self)
    local k=self.channelKey; A.db.selected[k]=self:GetChecked() and true or false
    if not A.db.selected[k] and A.db.targetKey==k then A.db.targetKey=nil end
    if not A.db.selected[k] and A.current==k then A.current=nil end
    if A.db.selected[k] and not A.current and not A.db.targetKey then A.current=k;A.db.targetKey=k end
    A.ReplyRouteChanged()
    A.Refresh()
   end); A.dockRows[index]=row
  end
  local c=A.channels[key]; row.channelKey=key; row:SetChecked(A.db.selected[key]); row.choose.label:SetText((A.current==key and "> " or "")..A.Cut(c.name,19).." ("..#c.messages..")"); row:Show(); row.choose:Show()
 end
 for n=#keys+1,#A.dockRows do A.dockRows[n]:Hide(); A.dockRows[n].choose:Hide() end
 A.dockChannelContent:SetHeight(math.max(26,#keys*26))
 local selected=0; for _,key in ipairs(A.order) do if A.db.selected[key] then selected=selected+1 end end
 A.dockEmpty:SetText("监听 "..selected.." 个 | 勾选仅监听；点击名称锁定发言频道")
end
function A.RenderChatDock()
 if not A.dock then return end
 local p=A.pending; local c=A.current and A.channels[A.current]; local replyTarget=p and p.channel or c
 A.dockTarget.label:SetText(c and A.Cut(c.name,12).." v" or "选择频道 v")
 A.dockAuto.label:SetText(A.MasterAutoEnabled() and "总控:开" or "总控:关")
 if A.dockWhisper then A.dockWhisper.label:SetText(A.AutoOptionLabel("私聊",A.db.whisperAuto));A.dockWhisperStatus:SetText(A.Cut(A.whisperDiagnostic or "按人合并，自动判断是否接话",24)) end
 A.dockSignalAuto.label:SetText(A.AutoOptionLabel("信号",A.db.signalAuto))
 if A.dockPublicAuto then A.dockPublicAuto.label:SetText(A.AutoOptionLabel("频道",A.db.auto));A.dockWaterThanks.label:SetText(A.AutoOptionLabel("感谢",A.db.waterThanksAuto));A.dockActivities.label:SetText(A.AutoOptionLabel("事件",A.db.activityAuto)) end
 A.dockSignalStatus:SetText(A.Cut(A.signalDiagnostic or (A.signalEventAvailable and "等待自己的信号" or "客户端不支持信号事件"),18))
 A.dockGenerate.label:SetText(A.status=="GENERATING" and "生成中" or (p and p.reply and not p.confirmed and "重生成" or "生成"))
 local ready=A.status=="READY" and p and p.reply and not p.submitted
 if ready then A.dockSend:Enable(); A.dockSend:SetAlpha(1) else A.dockSend:Disable(); A.dockSend:SetAlpha(.45) end
 local reply=p and p.reply or ""
 if reply~="" and A.dockSeenReply~=p.id then A.dockSeenReply=p.id; A.db.dockExpanded=true end
 if not A.dockDraft:HasFocus() and A.dockDraft:GetText()~=reply then A.dockDraft:SetText(reply) end
 local detail=A.bridgeInitError or (A.status=="OFFLINE" and A.bridgeError and A.bridgeError~="") and A.bridgeError or A.detail
 A.dockStatus:SetText(A.status.." · "..A.Cut(detail or "",42).." · "..(A.MasterAutoEnabled() and "总控开" or "总控关/仅手动")..(A.WhisperCount()>0 and ("("..A.WhisperCount()..")") or ""))
 A.dockCaption:SetText(reply~="" and ((p and p.confirmed and "已发送 → " or p and p.submitted and "确认中 → " or "待发送 → ")..(replyTarget and replyTarget.name or "未选择")) or "AI 回复会显示在这里；不会填入普通聊天输入框")
 A.dockToggle.label:SetText(A.db.dockExpanded and "AI -" or "AI +")
 A.LayoutChatDock(); A.RenderDockChannels()
end
function A.MakeChatDock()
 if A.dock then return end
 local d=A.db; if d.dockPlacementVersion~=2 then d.dockDetached=false; d.dockPlacementVersion=2 end; if d.dockVisible==nil then d.dockVisible=true end
 local f=CreateFrame("Frame","DFYChatDock",UIParent,"BackdropTemplate"); A.dock=f; skin(f); A.NormalWindow(f,1); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
 f:SetScript("OnDragStart",function() f:StartMoving() end)
 f:SetScript("OnDragStop",function() f:StopMovingOrSizing(); d.dockDetached=true; d.dockX=f:GetLeft(); d.dockY=f:GetBottom(); d.dockWidth=f:GetWidth(); A.dockAnchor="detached" end)
 A.dockToggle=button(f,"AI",32,function() d.dockExpanded=not d.dockExpanded end,"展开/收起回复。拖动下方状态行可移动；右键 AI 贴回聊天框。")
 A.dockToggle:RegisterForClicks("LeftButtonUp","RightButtonUp")
 A.dockToggle:SetScript("OnClick",function(_,which) if which=="RightButton" then A.AttachChatDock() else d.dockExpanded=not d.dockExpanded end; A.Refresh() end)
 A.dockTarget=button(f,"选择频道 ▾",130,function() if A.dockChannels:IsShown() then A.dockChannels:Hide() else A.SeedDockChannels(); A.dockChannels:Show(); A.RenderDockChannels() end end,function() return "当前回复目标："..(A.current and A.channels[A.current] and A.channels[A.current].name or "未选择").."。点击选择监听频道和回复目标；滚轮切换目标并勾选该频道。" end)
 A.dockTarget:EnableMouseWheel(true); A.dockTarget:SetScript("OnMouseWheel",function(_,delta) A.DockCycleChannel(delta) end)
 A.dockGenerate=button(f,"生成",48,function() clearDraft(); A.Generate() end,"根据所选频道上下文生成；只生成，不发送。")
 A.dockSend=button(f,"发送",44,function() clearDraft(); A.Send() end,"将预览回复发送到生成时锁定的目标；仅 READY 时可用。")
 A.dockAuto=button(f,"自动:关",60,function() A.SetMasterAuto(not A.MasterAutoEnabled()) end,function() return "自动总开关：统一控制频道、私聊、信号、事件和收水感谢。关闭清除自动任务；开启只处理新触发。各分项偏好保留；手动生成、发送和讨水仍可用。"..(A.publicDiagnostic or "") end)
 A.dockConnect=button(f,"自动连",44,function() end,"连接自动恢复，无需点击；不打断普通输入，不重发结果不确定的聊天。"); A.dockConnect:Disable(); A.dockConnect:SetAlpha(.7)
 A.dockWater=button(f,"讨水",44,function() A.AskTargetForWater() end,"选中友方法师玩家后点击：立即私聊讨水，带大肥鱼前缀。不调用AI，不改现有草稿或回复频道。");
 A.dockSettings=button(f,"···",30,function() A.frame:Show() end,"打开完整设置和最近8条上下文；/dfy settings 也可打开。")
 A.dockStatus=text(f,""); A.dockStatus:SetPoint("TOPLEFT",6,-29); A.dockStatus:SetHeight(14)
 local preview=CreateFrame("Frame",nil,f); A.dockPreview=preview; preview:SetPoint("TOPLEFT",0,-44); preview:SetPoint("BOTTOMRIGHT",0,0)
 A.dockCaption=text(preview,""); A.dockCaption:SetPoint("TOPLEFT",8,-6); A.dockCaption:SetWidth(300)
 A.dockCancel=button(preview,"丢弃 ×",64,function() A.Cancel() end,"取消生成或丢弃待发回复；迟到回包失效。已提交消息不能撤回。"); A.dockCancel:SetPoint("TOPRIGHT",-8,0)
 local draft=CreateFrame("EditBox",nil,preview,"BackdropTemplate"); A.dockDraft=draft; skin(draft); draft:SetPoint("TOPLEFT",8,-28); draft:SetSize(440,64);draft:SetJustifyV("TOP");draft:SetSpacing(3); draft:SetMultiLine(true); draft:SetAutoFocus(false); draft:SetFontObject(ChatFontNormal); draft:SetTextInsets(6,6,3,3); draft:SetText("")
 draft:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
 draft:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
 draft:SetScript("OnTextChanged",function(self,user) if user and A.pending and A.status=="READY" and not A.pending.submitted then A.pending.reply=A.FormatPendingReply(A.pending,self:GetText():gsub('[\r\n|]',' ')); if A.reply and not A.reply:HasFocus() then A.reply:SetText(A.pending.reply) end end end)
 local scene=CreateFrame("EditBox",nil,preview,"BackdropTemplate"); A.dockScene=scene; skin(scene); scene:SetPoint("TOPLEFT",8,-98); scene:SetSize(330,24); scene:SetAutoFocus(false); scene:SetFontObject(ChatFontNormal); scene:SetTextInsets(6,6,0,0); scene:SetMaxLetters(160); scene:SetText("")
 local hint=text(scene,"场景提示：如 开怪提醒 / 感谢队友"); hint:SetPoint("LEFT",6,0)
 scene:SetScript("OnTextChanged",function(self) if self:GetText()=="" then hint:Show() else hint:Hide() end end)
 scene:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
 scene:SetScript("OnEnterPressed",function(self) local value=self:GetText(); self:ClearFocus(); A.GenerateScene(value) end)
 A.dockSceneGenerate=button(preview,"润色生成",72,function() local value=scene:GetText(); clearDraft(); A.GenerateScene(value) end,"按人设把场景提示写成一句话；只生成预览，绝不自动发送。"); A.dockSceneGenerate:SetPoint("TOPRIGHT",-8,-98)
 A.dockSignalAuto=button(preview,"信号:关",66,function() d.signalAuto=not d.signalAuto; if not d.signalAuto then A.queuedSignal=nil end; if not d.signalAuto and A.pending and A.pending.mode=="signal" and not A.pending.submitted then A.Cancel(); d.dockExpanded=true end; A.detail=d.signalAuto and "信号发言跟随当前回复频道；无冷却、无每小时上限" or "信号自动发言已关闭" end,function() return "只响应自己的信号，发送到工具条选择的回复频道；单人也能用。未选频道时：组队跟随队伍，单人用说。注意/危险/目标按钮：关时预览，开时自动发。"..(A.signalEventAvailable and "" or " 当前客户端不支持信号事件，请使用按钮。")..(A.signalDiagnostic or "") end); A.dockSignalAuto:SetPoint("TOPLEFT",8,-128)
 A.dockAttention=button(preview,"注意",48,function() clearDraft(); A.SignalButton("attention") end); A.dockAttention:SetPoint("LEFT",A.dockSignalAuto,"RIGHT",6,0)
 A.dockDanger=button(preview,"危险",48,function() clearDraft(); A.SignalButton("danger") end); A.dockDanger:SetPoint("LEFT",A.dockAttention,"RIGHT",6,0)
 A.dockTargetSignal=button(preview,"目标",48,function() clearDraft(); A.SignalButton("target") end); A.dockTargetSignal:SetPoint("LEFT",A.dockDanger,"RIGHT",6,0)
 A.dockActivities=button(preview,"事件发言",76,function() A.ToggleActivityPanel() end,"任务、奖励和装备掉落的独立开关；跟随当前回复频道。"); A.dockActivities:SetPoint("TOPLEFT",8,-156)
 A.dockWhisper=button(preview,"私聊:开",76,function() A.SetWhisperAuto(not d.whisperAuto) end,"角色与战网好友私聊独立开关，无需关键词或勾选联系人；每个人独立上下文，同一人连发合并，多人轮流回复。受自动总控控制；显示“停”表示偏好开启但总控关闭。/dfy whisper off 可关闭。")
 A.dockWhisper:SetPoint("TOPLEFT",90,-156)
 A.dockPublicAuto=button(preview,"频道:关",76,function() A.SetPublicAuto(not d.auto) end,"只在顶部锁定频道自动接话；其他勾选频道仅监听，不混入回复。受总控控制。");A.dockPublicAuto:SetPoint("TOPLEFT",172,-156)
 A.dockWaterThanks=button(preview,"感谢:开",76,function() d.waterThanksAuto=not d.waterThanksAuto;A.waterRequests={};A.waterTrade=nil end,"讨水后交易收到水自动私聊感谢；受自动总控控制。不补发过去的感谢。");A.dockWaterThanks:SetPoint("TOPLEFT",254,-156)
 A.dockWhisperStatus=text(preview,"");A.dockWhisperStatus:SetPoint("LEFT",A.dockWhisper,"RIGHT",6,0);A.dockWhisperStatus:SetWidth(230);A.dockWhisperStatus:SetHeight(18);A.dockWhisperStatus:Hide()
 local signalHelp=text(preview,"等待自己的信号"); A.dockSignalStatus=signalHelp; signalHelp:SetWidth(164); signalHelp:SetHeight(14); signalHelp:SetWordWrap(false); signalHelp:SetPoint("LEFT",A.dockTargetSignal,"RIGHT",6,0)
 local menu=CreateFrame("Frame","DFYDockChannels",f,"BackdropTemplate"); A.dockChannels=menu; skin(menu); menu:SetSize(360,300); menu:SetPoint("TOPLEFT",f,"BOTTOMLEFT",0,-3); A.NormalWindow(menu,3); menu:SetClampedToScreen(true); menu:EnableMouse(true)
 A.dockEmpty=text(menu,""); A.dockEmpty:SetPoint("TOPLEFT",10,-10)
 local searchLabel=text(menu,"搜索"); searchLabel:SetPoint("TOPLEFT",10,-35)
 local search=CreateFrame("EditBox",nil,menu,"BackdropTemplate"); A.dockSearch=search; skin(search); search:SetPoint("TOPLEFT",46,-30); search:SetSize(302,22); search:SetFontObject(ChatFontNormal); search:SetAutoFocus(false); search:SetTextInsets(5,5,0,0); search:SetText("")
 search:SetScript("OnTextChanged",function(self) A.dockFilter=self:GetText(); A.RenderDockChannels() end)
 search:SetScript("OnEscapePressed",function(self) self:ClearFocus(); menu:Hide() end)
 search:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
 menu:SetScript("OnHide",function() search:ClearFocus() end)
 local scroll=CreateFrame("ScrollFrame",nil,menu,"UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",8,-60); scroll:SetPoint("BOTTOMRIGHT",-28,36)
 local content=CreateFrame("Frame",nil,scroll); content:SetSize(304,26); scroll:SetScrollChild(content); A.dockChannelContent=content; A.dockRows={}
 local follow=button(menu,"锁定当前",96,function() d.targetKey=A.current; A.ReplyRouteChanged();A.detail="当前公开发言频道已锁定，其他频道只监听"; menu:Hide() end); follow:SetPoint("BOTTOMLEFT",110,6)
 A.dockSelectAll=button(menu,"全选",44,function() for _,key in ipairs(A.DockChannelKeys()) do A.db.selected[key]=true end; A.detail="已勾选列表内频道" end); A.dockSelectAll:SetPoint("BOTTOMLEFT",8,6)
 A.dockClearAll=button(menu,"清空",44,function() for key in pairs(A.db.selected) do A.db.selected[key]=false end; A.current=nil; A.db.targetKey=nil;A.ReplyRouteChanged(); A.detail="已清空监听与公开频道待发内容" end); A.dockClearAll:SetPoint("BOTTOMLEFT",58,6)
 local close=button(menu,"关闭",48,function() menu:Hide() end); close:SetPoint("BOTTOMRIGHT",-8,6)
 UISpecialFrames[#UISpecialFrames+1]="DFYDockChannels"; menu:Hide()
 local elapsed=0; f:SetScript("OnUpdate",function(_,dt) elapsed=elapsed+dt; if elapsed>.5 then elapsed=0; A.LayoutChatDock() end end)
 A.RenderChatDock(); if d.dockVisible then f:Show() else f:Hide() end
end
