-- Mock focused on the display/settings layer.
local dir = arg[1]
events = {}; date = os.date
local frames = {}
local calls = {}
local function obj(kind)
  local o = { _shown = true, _kind = kind }
  return setmetatable(o, {__index=function(t,k)
    if k:match("^[%l_]") then return nil end
    if k=="GetPoint" then return function() return "CENTER",nil,"CENTER",1,2 end end
    if k=="GetFont" then return function() return "Fonts/FRIZQT__.TTF", 12, "" end end
    if k=="GetThumbTexture" then return function(self) local t = rawget(self, "_thumb") or obj(); rawset(self, "_thumb", t); return t end end
    if k=="IsVisible" then return function(self) return rawget(self,"_shown") end end
    if k=="IsShown" then return function(self) return rawget(self,"_shown") end end
    if k=="Show" then return function(self) rawset(self,"_shown",true) end end
    if k=="Hide" then return function(self) rawset(self,"_shown",false) end end
    if k=="SetShown" then return function(self,v) rawset(self,"_shown",not not v) end end
    if k=="GetChecked" then return function(self) return rawget(self,"_checked") end end
    if k=="SetChecked" then return function(self,v) rawset(self,"_checked",v) end end
    if k=="GetValue" then return function(self) return rawget(self,"_value") or 0 end end
    if k=="SetValue" then return function(self,v) rawset(self,"_value",v); local f=rawget(self,"_OnValueChanged"); if f then f(self,v) end end end
    if k=="SetText" then return function(self,v) rawset(self,"_text",v) end end
    if k=="GetSize" then return function() return 14, 260 end end
    if k=="GetFrameLevel" then return function() return 1 end end
    if k=="GetCenter" then return function() return 100,100 end end
    if k=="GetEffectiveScale" then return function() return 1 end end
    if k:match("^Create") then return function(self, ...) local c=obj(k); frames[#frames+1]=c; return c end end
    return function(self, ...) if k=="SetScript" then local n,f=...; rawset(self, "_"..n, f) end if k=="RegisterEvent" then events[(...)]=true end calls[k]=(calls[k] or 0)+1 return nil end
  end})
end
function CreateFrame(kind) local f=obj(kind); frames[#frames+1]=f; return f end
UIParent = obj(); Minimap = obj(); GameTooltip = obj(); UISpecialFrames = {}
function GetCursorPosition() return 150, 120 end
SlashCmdList = {}
local timers = {}
C_Timer = { After=function(d,f) timers[#timers+1]={f=f} end,
  NewTicker=function(d,f) local t={f=f,live=true}; t.Cancel=function() t.live=false end; timers[#timers+1]=t; return t end }
local clock=0; function GetTime() clock=clock+0.1; return clock end; wipe=function(t) for k in pairs(t) do t[k]=nil end end
C_Item = { GetItemInfoInstant=function(id) if id < 100000 then return id end end, RequestLoadItemDataByID=function() end,
  GetItemInfo=function() return "x" end, GetItemSpell=function(id) return "Sp", 5000 + id end, IsItemDataCachedByID=function() return true end,
  IsItemInRange=function(id,u) return id % 3 ~= 0 end }
local ranges = {}
C_Spell = { IsSpellInRange=function() return false end, GetSpellInfo=function(id) if id >= 5000 then local iid=id-5000 return {name="I", minRange=0, maxRange=(iid%9+1)*5} end return {name="Charge", minRange=8, maxRange=25} end,
  IsSpellHarmful=function() return true end, IsSpellHelpful=function() return false end }
C_SpellBook = { GetNumSpellBookSkillLines=function() return 1 end, GetSpellBookSkillLineInfo=function() return {itemIndexOffset=0, numSpellBookItems=1} end,
  GetSpellBookItemInfo=function(i) return {itemType=1, spellID=100} end }
Enum = {SpellBookSpellBank={Player=0}, SpellBookItemType={Spell=1}}
C_EventUtils = {IsEventValid=function() return true end}
function issecretvalue() return false end
function UnitExists(u) return u=="target" or u=="nameplate1" or u=="nameplate2" end
function UnitCanAttack(_, u) return u ~= "nameplate2" end
C_NamePlate = { GetNamePlateForUnit = function(u) local p = CreateFrame("Frame"); return p end }

function UnitIsPlayer() return false end
function UnitIsUnit() return false end
function UnitIsVisible() return true end
function UnitName() return "Mob" end
function UnitLevel() return 5 end
function UnitRace() return "Orc","Orc" end
function UnitDistanceSquared() return 0, false end
function InCombatLockdown() return false end
function CheckInteractDistance(u,i) return i==4 end
function GetBuildInfo() return "1.60.1","70338","Oct",16001 end
BackdropTemplateMixin = {}
print = function(...) local t={...}; for i=1,select('#',...) do t[i]=tostring(t[i]) end io.write(table.concat(t," "),"\n") end
TumstockCharDB = { readout = { point = {"CENTER","CENTER",5,6}, locked = true } }
local T = {}
for line in io.lines(dir.."/Tumstock.toc") do
  if not line:match("^#") and line:match("%S") then assert(loadfile(dir.."/"..line))("Tumstock", T) end
end
local function fire(e, ...) for _,f in ipairs(frames) do if rawget(f,"_OnEvent") then f._OnEvent(f,e,...) end end end
fire("ADDON_LOADED","Tumstock"); fire("PLAYER_LOGIN")
for round=1,200 do local cur=timers; timers={}; for _,t in ipairs(cur) do if t.live==nil or t.live then t.f() if t.live then timers[#timers+1]=t end end end if #timers==0 then break end end
print("migrated point:", T.cfg.text.point and T.cfg.text.point[3], "locked:", T.cfg.locked, "readout gone:", TumstockCharDB.readout == nil)
print("thresholds:", table.concat(T.Thresholds("harm"), " "))
print("measure:", T.Measure("target"))
local function tick(n) for _=1,n do for _,f in ipairs(frames) do local u=rawget(f,"_OnUpdate"); if u then u(f, 0.2) end end end end
for _, mode in ipairs{"text","bar","both"} do
  T.cfg.mode = mode; T.ApplySettings(); tick(3)
end
T.cfg.bar.vertical = false; T.cfg.bar.reversed = true; T.ApplySettings(); tick(3)
SlashCmdList.TUMSTOCK("")          -- open settings
SlashCmdList.TUMSTOCK("config")    -- close
SlashCmdList.TUMSTOCK("config")    -- open again
-- click every button / checkbox / slider in the settings window
local clicked = 0
for _,f in ipairs(frames) do
  local c = rawget(f,"_OnClick"); if c then c(f, "LeftButton"); clicked = clicked + 1 end
  local v = rawget(f,"_OnValueChanged"); if v then v(f, 1.234); clicked = clicked + 1 end
end
tick(3)
print("controls exercised:", clicked, "mode now:", T.cfg.mode)
SlashCmdList.TUMSTOCK("lock"); SlashCmdList.TUMSTOCK("unlock"); SlashCmdList.TUMSTOCK("reset"); SlashCmdList.TUMSTOCK("minimap"); SlashCmdList.TUMSTOCK("help"); SlashCmdList.TUMSTOCK("bar")
tick(2)
print("lastError", T.lastError)
fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
tick(5)
local shown = 0
for _,f in ipairs(frames) do if rawget(f,"value") and rawget(f.value,"_text") and rawget(f,"_shown") then shown = shown + 1; print("plate label:", f.value._text) end end
T.cfg.plates.enemy = false; T.ApplySettings(); tick(3)
fire("NAME_PLATE_UNIT_REMOVED", "nameplate1"); fire("NAME_PLATE_UNIT_REMOVED", "nameplate2"); tick(2)
print("labels shown:", shown, "lastError", T.lastError)
-- colour styles, combat hide, unit alpha
for _, st in ipairs{"smooth","bands","off"} do T.cfg.colorStyle = st; T.ApplySettings(); tick(3) end
T.cfg.colorStyle = "smooth"
local r1 = {T.ColorAt(0)}; local r2 = {T.ColorAt(31.5)}; local r3 = {T.ColorAt(60)}
print(string.format("colors 0:%.2f,%.2f,%.2f 31.5:%.2f,%.2f,%.2f 60:%.2f,%.2f,%.2f", r1[1],r1[2],r1[3], r2[1],r2[2],r2[3], r3[1],r3[2],r3[3]))
T.cfg.locked = true; T.cfg.hideInCombat = true
InCombatLockdown = function() return true end
tick(3); print("hidden in combat:", T.DisplaysHidden(true))
InCombatLockdown = function() return false end
T.cfg.hideNoUnit = true
print("hidden no unit:", T.DisplaysHidden(false), "shown with unit:", not T.DisplaysHidden(true))
print("final lastError", T.lastError)
-- hold test: unit vanishes for one tick, then comes back
T.cfg.mode = "both"; T.cfg.locked = true; T.cfg.hideNoUnit = true; T.ApplySettings()
local function textNow() for _,f in ipairs(frames) do if rawget(f,"colorTarget") ~= nil or rawget(f,"label") then return rawget(f.value,"_text") end end end
tick(3); local before = textNow()
local real = UnitExists
UnitExists = function(u) return false end
tick(1); local during = textNow()
UnitExists = real
tick(1); local after = textNow()
print("hold:", before, during, after, "lastError", T.lastError)
