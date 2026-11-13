-- Dedicated addon receiver. Never opens ChatFrame edit boxes and never submits Enter.
local A=DFY
BINDING_HEADER_DFY_BRIDGE="大肥鱼：专用数据接收"
BINDING_NAME_DFY_BRIDGE_OPEN="准备接收（不发聊天）"
BINDING_NAME_DFY_BRIDGE_EXECUTE="执行已校验请求"
A.bridgeRxDiagnostic=""; A.reconnectNonce=0; A.bridgeNonce=0; A.bridgeAck=0; A.bridgeAckChecksum=0; A.bridgeError=""
local keys={}
local candidates={}
for _,n in ipairs({8,9,10,11,12,6,7,5,4,3,2,1}) do candidates[#candidates+1]={name='F'..n,vk=n+111} end
candidates[#candidates+1]={name="INSERT",vk=45}
candidates[#candidates+1]={name="DELETE",vk=46}
candidates[#candidates+1]={name="HOME",vk=36}
candidates[#candidates+1]={name="END",vk=35}
candidates[#candidates+1]={name="PAGEUP",vk=33}
candidates[#candidates+1]={name="PAGEDOWN",vk=34}
candidates[#candidates+1]={name="NUMPADMULTIPLY",vk=106}
candidates[#candidates+1]={name="NUMPADPLUS",vk=107}
candidates[#candidates+1]={name="NUMPADMINUS",vk=109}
candidates[#candidates+1]={name="NUMPADDIVIDE",vk=111}
candidates[#candidates+1]={name="[",vk=219}
candidates[#candidates+1]={name="]",vk=221}
candidates[#candidates+1]={name="\\",vk=220}
candidates[#candidates+1]={name=";",vk=186}
candidates[#candidates+1]={name="'",vk=222}
candidates[#candidates+1]={name=",",vk=188}
candidates[#candidates+1]={name=".",vk=190}
candidates[#candidates+1]={name="`",vk=192}
candidates[#candidates+1]={name="-",vk=189}
candidates[#candidates+1]={name="=",vk=187}

local openAction='CLICK DFYBridgeOpenKeyButton:LeftButton'
local executeAction='CLICK DFYBridgeExecuteKeyButton:LeftButton'
local function ours(action)
 return type(action)=='string' and (action==openAction or action==executeAction or action=='DFY_BRIDGE_OPEN' or action=='DFY_BRIDGE_EXECUTE' or action:match('^CLICK DFYBridgeData%d+:LeftButton$'))
end
function A.BindingsReady()
 if A.bridgeTransport~='keys1-v1' and A.bridgeTransport~='keys2-v1' and A.bridgeTransport~='keys-safe1-v1' and A.bridgeTransport~='keys-safe2-v1' then return false end
 if A.bridgeOpenMods~=0 or A.bridgeExecuteMods~=0 or not next(keys) then return false end
 for key,action in pairs(keys) do if GetBindingAction(key)~=action then return false end end
 return true
end
local function vacant(bound)
 return bound==nil or bound=='' or bound=='NONE'
end
local function setupUnmodified(count)
 local proposed,previous,chosen={},{},{}
 local actions={openAction,executeAction}
 for i=0,count-1 do actions[#actions+1]='CLICK DFYBridgeData'..i..':LeftButton' end
 for _,action in ipairs(actions) do
  local pick,pickVK
  for _,candidate in ipairs(candidates) do local k=candidate.name;local ok,bound=pcall(GetBindingAction,k)
   if ok and not proposed[k] and (vacant(bound) or ours(bound)) then pick=k;pickVK=candidate.vk;break end
  end
  if not pick then A.bindingFailure='insufficient_free_keys';return false end
  proposed[pick]=action;chosen[#chosen+1]=pickVK
 end
 for key,action in pairs(proposed) do
  local before=GetBindingAction(key)
  if before~=action then
   previous[key]=before or ''
   local ok,result=pcall(SetBindingClick,key,action:match('^CLICK (.-):LeftButton$'),'LeftButton')
   if not ok or result==false or GetBindingAction(key)~=action then
    A.bindingFailure='registration_rejected:'..key..':'..tostring(result)..':'..tostring(GetBindingAction(key))
    for k,v in pairs(previous) do if ours(GetBindingAction(k)) then pcall(SetBinding,k,not vacant(v) and v or nil) end end
    return false
   end
  end
 end
 for _,candidate in ipairs(candidates) do local k=candidate.name;if not proposed[k] and ours(GetBindingAction(k)) then pcall(SetBinding,k) end end
 for n=13,24 do local k='F'..n;if ours(GetBindingAction(k)) then pcall(SetBinding,k) end end
 keys=proposed;A.bridgeOpenKey=chosen[1];A.bridgeExecuteKey=chosen[2];A.bridgeOpenMods=0;A.bridgeExecuteMods=0
 A.bridgeDataKeys=A.Array();for i=3,count+2 do A.bridgeDataKeys[#A.bridgeDataKeys+1]={key=chosen[i],mods=0} end
 local allFunction=true;for _,vk in ipairs(chosen) do if vk<112 or vk>123 then allFunction=false end end
 A.bridgeTransport=allFunction and (count==2 and 'keys1-v1' or 'keys2-v1') or (count==2 and 'keys-safe1-v1' or 'keys-safe2-v1');A.bridgeError='';A.bindingFailure=nil;A.bridgeRxDiagnostic='unmodified_bindings_ready';return true
end
function A.SetupBindings()
 if A.BindingsReady() then return true end
 if InCombatLockdown() then A.bridgeError="等待客户端允许初始化通信"; return false end
 if A.bindingRetryAt and GetTime()<A.bindingRetryAt then return false end
 A.bindingRetryAt=GetTime()+5 -- Failed setup backoff only; no reply cooldown or rate limit.
 -- Remove only our obsolete modifier bindings; never touch user actions.
 for _,prefix in ipairs({'CTRL-SHIFT-','ALT-CTRL-SHIFT-','CTRL-ALT-SHIFT-'}) do
  for n=1,24 do local k=prefix..'F'..n;if ours(GetBindingAction(k)) then pcall(SetBinding,k) end end
 end
 keys={};A.bridgeTransport='';A.bridgeOpenKey=nil;A.bridgeExecuteKey=nil;A.bridgeDataKeys=A.Array()
 A.bridgeOpenMods=0;A.bridgeExecuteMods=0
 if setupUnmodified(4) or setupUnmodified(2) then return A.BindingsReady() end
 local diagnostic={A.bindingFailure or 'unknown'}
 for _,candidate in ipairs(candidates) do local key=candidate.name;diagnostic[#diagnostic+1]=key..'='..tostring(GetBindingAction(key)) end
 A.bridgeRxDiagnostic=table.concat(diagnostic,';')
 A.bridgeError=A.bindingFailure and A.bindingFailure:match('^registration_rejected') and "客户端未接受通信初始化；已记录诊断，不会改动其他键位" or "通信通道暂不可用；已记录键位诊断，无需按组合键"
 return false
end
function A.BridgeChecksum(s)
 local sum=0; for i=1,#s do sum=(sum+s:byte(i)*i)%65536 end; return sum
end
function A.CloseReceiver(clearPending)
 -- No EditBox or focus operations in this transport.
 A.receiverActive=false
 if clearPending then A.prepared=nil end
end
function A.RequestConnection()
 -- An explicit panel click cancels old work; reconnect must never replay an uncertain send.
 A.CloseReceiver(true); A.pending=nil; A.queuedSignal=nil; A.db.auto=false; A.db.signalAuto=false; A.lastBridge=0
 A.reconnectNonce=A.reconnectNonce+1
 if not A.BindingsReady() then A.SetupBindings() end
 A.State("OFFLINE","连接请求 #"..A.reconnectNonce.."："..(A.BindingsReady() and "请松开按键，助手正在连接" or A.bridgeError))
end
function A.OpenReceiver()
 if A.ProfessionBusy and A.ProfessionBusy() then return end
 if not A.db or not A.receiverFrame then return end
 if GetCurrentKeyBoardFocus() then A.State("OFFLINE","请先关闭当前输入框"); return end
 if not A.BindingsReady() then A.State("OFFLINE",A.bridgeError~="" and A.bridgeError or "空闲接收键位未就绪"); return end
 A.prepared=nil; A.bridgeNonce=A.bridgeNonce+1; A.receiverActive=true; A.receiverDeadline=GetTime()+4; A.bridgeError=""
 A.bridgeRxDiagnostic="key_stream_opened"; A.receiverBuffer=""; A.receiverProgressChecksum=0; A.receiverHigh=nil; A.receiverDigitCount=0; A.Refresh()
end
local function receiveDiagnostic(reason,text)
 local _,pipes=text:gsub("|","")
 local head={}; for n=1,math.min(#text,20) do head[#head+1]=string.format("%02x",text:byte(n)) end
 A.bridgeRxDiagnostic=reason..";length="..#text..";pipes="..pipes..";headHex="..table.concat(head)
end
local allowed={ping=true,keywords=true,generate=true,rx=true,fail=true,commit=true}
function A.AcceptBridge(text)
 if A.ProfessionBusy and A.ProfessionBusy() then A.CloseReceiver(true);return false end
 if not A.receiverActive or GetCurrentKeyBoardFocus() or GetTime()>A.receiverDeadline then return false end
 if #text>480 then A.bridgeError="接收数据过长"; A.CloseReceiver(true); return false end
 if text:sub(-1)~="!" then return false end
 local session,nonce,b64,sum=text:match('^DFY4;(%d+);(%d+);([A-Za-z0-9+/=]+);(%d+)!$')
 local unsigned=session and 'DFY4;'..session..';'..nonce..';'..b64
 local reason
 if not session then reason="帧格式不匹配"
 elseif session~=A.session then reason="会话不匹配"
 elseif tonumber(nonce)~=A.bridgeNonce then reason="接收序号不匹配"
 elseif A.BridgeChecksum(unsigned)~=tonumber(sum) then reason="校验和不匹配："..A.BridgeChecksum(unsigned).."/"..sum end
 if reason then receiveDiagnostic(reason,text); A.bridgeError=reason.."，已丢弃"; A.CloseReceiver(true); A.Refresh(); return false end
 receiveDiagnostic("validated",text)
 local command=A.Unbase64(b64); local kind=command and command:match('^(%w+)')
 if not kind or not allowed[kind] or command:find('[%z\1-\31\127-\255]') then A.bridgeError="拒绝无效内部请求"; A.CloseReceiver(true); A.Refresh(); return false end
 A.prepared={nonce=tonumber(nonce),checksum=tonumber(sum),command=command,kind=kind,deadline=GetTime()+4}
 A.CloseReceiver(false); A.Refresh(); return true
end
function A.ExecuteBridge()
 if A.ProfessionBusy and A.ProfessionBusy() then A.CloseReceiver(true);return false end
 local p=A.prepared
 if not p or p.nonce<=A.bridgeAck or GetTime()>p.deadline or GetCurrentKeyBoardFocus() or not A.BindingsReady() then return false end
 -- Consume before dispatch: replayed execute keys cannot repeat generation or sending.
 A.prepared=nil; A.bridgeAck=p.nonce; A.bridgeAckChecksum=p.checksum; A.bridgeExecuting=true
 local ok,err=pcall(A.Command,p.command); A.bridgeExecuting=false
 A.bridgeError=ok and "" or "执行失败："..tostring(err)
 A.Refresh(); return ok
end
function A.ReceiveNibble(n)
 if A.ProfessionBusy and A.ProfessionBusy() then A.CloseReceiver(true);return end
 if not A.receiverActive then return end
 if GetCurrentKeyBoardFocus() or GetTime()>A.receiverDeadline then A.CloseReceiver(true); A.Refresh(); return end
 local value
 local binary=A.bridgeTransport=='keys1-v1' or A.bridgeTransport=='keys-safe1-v1'
 if not binary and A.bridgeTransport~='keys2-v1' and A.bridgeTransport~='keys-safe2-v1' then A.CloseReceiver(true);return end
 local radix=binary and 2 or 4;local digits=binary and 8 or 4
 if type(n)~='number' or n<0 or n>=radix or n%1~=0 then A.CloseReceiver(true);return end
 A.receiverHigh=(A.receiverHigh or 0)*radix+n;A.receiverDigitCount=(A.receiverDigitCount or 0)+1
 if A.receiverDigitCount<digits then return end
 value=A.receiverHigh;A.receiverHigh=nil;A.receiverDigitCount=0
 if value<32 or value>126 or #A.receiverBuffer>=480 then A.bridgeError="键流数据无效"; A.CloseReceiver(true); A.Refresh(); return end
 A.receiverBuffer=A.receiverBuffer..string.char(value)
 A.receiverProgressChecksum=(A.receiverProgressChecksum+value*#A.receiverBuffer)%65536
 A.receiverDeadline=GetTime()+4
 if value==33 then A.AcceptBridge(A.receiverBuffer)
 elseif #A.receiverBuffer%4==0 then A.Publish() end
end
function A.MakeReceiver()
 if A.receiverFrame then A.SetupBindings();return end
 local function binding(name,callback)
  local b=CreateFrame("Button",name,UIParent); b:SetSize(1,1); b:SetPoint("BOTTOMLEFT",0,0); b:SetAlpha(0); b:SetScript("OnClick",callback); return b
 end
 binding("DFYBridgeOpenKeyButton",function() A.OpenReceiver() end)
 binding("DFYBridgeExecuteKeyButton",function() A.ExecuteBridge() end)
 for i=0,15 do local n=i; binding("DFYBridgeData"..i,function() A.ReceiveNibble(n) end) end
 -- An invisible timer only. Never creates an EditBox, shows a receiving panel, or takes focus.
 local f=CreateFrame("Frame",nil,UIParent); A.receiverFrame=f; f:SetSize(1,1); f:SetAlpha(0)
 f:SetScript("OnUpdate",function()
  if A.receiverActive and GetTime()>A.receiverDeadline then A.bridgeError="键流接收超时，已丢弃"; A.CloseReceiver(true); A.Refresh() end
 end)
 A.SetupBindings()
end
