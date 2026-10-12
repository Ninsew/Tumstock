local dir = arg[1]
local function obj()
  local o = {}
  return setmetatable(o, {__index=function(t,k)
    if k=="GetPoint" then return function() return "CENTER",nil,"CENTER",1,2 end end
    if k=="GetText" then return function() return "" end end
    if k:match("^Create") then return function() return obj() end end
    return function(self, ...) if k=="SetScript" then local n,f=...; rawset(self, "_"..n, f) end if k=="RegisterEvent" then events[(...)]=true end return nil end
  end})
end
events = {}; date = os.date
frames = {}
function CreateFrame(...) local f=obj(); frames[#frames+1]=f; return f end
UIParent = obj(); UISpecialFrames = {}
SlashCmdList = {}
local timers = {}
C_Timer = { After=function(d,f) timers[#timers+1]={f=f} end,
  NewTicker=function(d,f) local t={f=f,live=true}; t.Cancel=function() t.live=false end; timers[#timers+1]=t; return t end }
local printed = {}
print = function(...) local t={...}; for i=1,select('#',...) do t[i]=tostring(t[i]) end io.write(table.concat(t," "),"\n") end
C_Item = {
  GetItemInfoInstant=function(id) if id < 100000 then return id end end,
  RequestLoadItemDataByID=function() end,
  GetItemInfo=function(id) return "x" end,
  GetItemSpell=function(id) if id%7==0 then return "Sp", 1000+id%40 end end,
  IsItemDataCachedByID=function(id) return id%3~=0 end,
  IsItemInRange=function(id,u) if id%5==0 then return nil end return id%2==0 end,
}
local clock=0; function GetTime() clock=clock+0.5; return clock end; wipe=function(t) for k in pairs(t) do t[k]=nil end end
C_Spell = { IsSpellInRange=function(id) return true end, GetSpellInfo=function(id) return {name="Spell"..id, minRange=(id%10==3) and 8 or 0, maxRange=(id%40)} end }
C_SpellBook = { GetNumSpellBookSkillLines=function() return 1 end,
  GetSpellBookSkillLineInfo=function() return {itemIndexOffset=0, numSpellBookItems=2} end,
  GetSpellBookItemInfo=function(i) return {itemType=1, spellID=100+i} end }
Enum = {SpellBookSpellBank={Player=0}, SpellBookItemType={Spell=1}}
C_EventUtils = {IsEventValid=function(e) return e ~= "LEARNED_SPELL_IN_TAB" end}
function issecretvalue(v) return false end
function UnitExists(u) return u=="target" end
function UnitCanAttack() return true end
function UnitIsPlayer() return false end
function UnitIsUnit() return false end
function UnitIsVisible() return true end
function UnitName() return "Mob" end
function UnitLevel() return 5 end
function InCombatLockdown() return false end
function CheckInteractDistance(u,i) return i==4 end
function GetBuildInfo() return "1.60.1","70009","Oct",16001 end
BackdropTemplateMixin = {}
function UnitRace() return "Orc","Orc" end
function UnitDistanceSquared() return 0, false end
C_CVar = {GetCVar=function(n) return "10" end, SetCVar=function() end}
C_NamePlate = {GetNamePlateForUnit=function() local p = {GetScale=function() return 0.8 end, GetCenter=function() error("Cannot measure restricted regions") end}; p.UnitFrame = {GetAlpha=function() return 1 end}; return p end}
local T = {}
for line in io.lines(dir.."/Tumstock.toc") do
  if not line:match("^#") and line:match("%S") then
    local f = assert(loadfile(dir.."/"..line:gsub("\\","/")))
    f("Tumstock", T)
  end
end
local function fire(e, ...) for _,f in ipairs(frames) do if rawget(f,"_OnEvent") then f._OnEvent(f,e,...) end end end
fire("ADDON_LOADED","Tumstock")
fire("PLAYER_LOGIN")
for round=1,40 do local cur=timers; timers={}; for _,t in ipairs(cur) do if t.live==nil or t.live then t.f() if t.live then timers[#timers+1]=t end end end end
print("load", T.itemLoad.requested, T.itemLoad.noexist, T.itemLoad.loaded, T.itemLoad.done)
T.ShowOutput = function(title, lines) print("== "..title); for i,l in ipairs(lines) do if i<=60 then print(l) end end print("("..#lines.." lines)") end
for _,c in ipairs{"", "scan", "debug", "debug status", "debug engine", "debug discover"} do SlashCmdList.TUMSTOCK(c) end
for round=1,3000 do local cur=timers; timers={}; for _,t in ipairs(cur) do if t.live==nil or t.live then t.f() if t.live then timers[#timers+1]=t end end end if #timers==0 then break end end
for _,c in ipairs{"debug discover test","debug probe","debug engine","debug plates","debug plates watch","debug plates watch","debug record"} do SlashCmdList.TUMSTOCK(c) end
for round=1,3 do for _,t in ipairs(timers) do if t.live then t.f() end end end
SlashCmdList.TUMSTOCK("debug record")
for _,f in ipairs(frames) do if rawget(f,"_OnUpdate") then f._OnUpdate(f, 1); f._OnUpdate(f, 1) end end
print("lastError", T.lastError)
