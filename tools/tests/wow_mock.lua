-- Explicit API doubles. No real game process or keyboard input is used.
now=1000; clock=100; sent={}; SlashCmdList={}; UISpecialFrames={}; textures={}; bindings={}; buttons={}; focus=nil; combat=false
function time() return now end
function GetTime() return clock end
function GetRealmName() return '全自动大肥鱼' end
function UnitFullName() return '圣鲸鲸','全自动大肥鱼' end
function UnitGUID() return 'player-guid' end
function GetCurrentKeyBoardFocus() return focus end
function GetPhysicalScreenSize() return 2560,physicalHeight or 1440 end
function InCombatLockdown() return combat end
function GetBindingAction(k) return bindings[k] or '' end
function SetBinding(k,v) if combat then error('combat protected') end; bindings[k]=v; return true end
function SetBindingClick(k,name,button) if not allowExtendedKeys and tonumber(k:match('^F(%d+)$') or '0')>12 then return false end;return SetBinding(k,'CLICK '..name..':'..button) end
function FireBinding(k) local name=(bindings[k] or ''):match('^CLICK (.-):LeftButton$'); if name and buttons[name] and buttons[name].OnClick then buttons[name].OnClick(buttons[name]);return true end;return false end
function GetChannelName(n) return n,channelOverride or '自定义测试' end
function SendChatMessage(t,k,lang,target) table.insert(sent,{text=t,kind=k,target=target}) end
local frame={}
frame.__index=function(self,key)
 if key=='SetFont' then return function(self,path,size,flags) self.fontPath=path;self.fontSize=size;self.fontFlags=flags;return true end end
 if key=='GetFont' then return function(self)return rawget(self,'fontPath'),rawget(self,'fontSize'),rawget(self,'fontFlags') end end
 if key=='SetFontObject' then return function(self,font) if type(font)=='table' then self.fontPath,self.fontSize,self.fontFlags=font:GetFont() end end end
 if key=='CreateTexture' then return function() local t=setmetatable({},frame); textures[#textures+1]=t; return t end end
 if key=='CreateFontString' then return function() return setmetatable({},frame) end end
 if key=='GetEffectiveScale' then return function() return 1 end end
 if key=='SetScale' then return function(self,s) self.scale=s end end
 if key=='SetChecked' then return function(self,v) self.checked=v end end
 if key=='GetChecked' then return function(self) return rawget(self,'checked') or false end end
 if key=='SetWidth' then return function(self,w) self.width=w end end
 if key=='SetHeight' then return function(self,h) self.height=h end end
 if key=='SetPoint' then return function(self,...) self.point={...} end end
 if key=='GetPoint' then return function(self) return unpack(self.point or {}) end end
 if key=='GetLeft' then return function() return 30 end end
 if key=='GetBottom' then return function() return 180 end end
 if key=='Enable' then return function(self) self.enabled=true end end
 if key=='Disable' then return function(self) self.enabled=false end end
 if key=='GetWidth' then return function(self) return self.width or 660 end end
 if key=='GetHeight' then return function(self) return self.height or 540 end end
 if key=='GetText' then return function(self) return rawget(self,'text') or '' end end
 if key=='SetText' then return function(self,s) self.text=s; local fn=rawget(self,'OnTextChanged');if fn then fn(self,false) end end end
 if key=='SetColorTexture' then return function(self,r,g,b,a) self.rgb={r,g,b} end end
 if key=='IsShown' then return function(self) return self.shown~=false end end
 if key=='Show' then return function(self) self.shown=true end end
 if key=='Hide' then return function(self) self.shown=false end end
 if key=='HasFocus' then return function(self) return focus==self end end
 if key=='SetFocus' then return function(self) focus=self end end
 if key=='ClearFocus' then return function(self) if focus==self then focus=nil end end end
 if key=='SetSize' then return function(self,w,h) self.width=w; self.height=h end end
 if key=='SetScript' then return function(self,k,fn) self[k]=fn end end
 return function() end
end
function CreateFrame(_,name) local f=setmetatable({},frame); if name then buttons[name]=f end;return f end
UIParent=CreateFrame()
function chat(typ,text,speaker,number)
 DFY.Chat('CHAT_MSG_'..typ,text,speaker,nil,nil,nil,nil,nil,number,'自定义测试',nil,nil,'other-guid')
end
function eq(a,b,msg) if a~=b then error(msg..': '..tostring(a)..' ~= '..tostring(b)) end end
