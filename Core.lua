-- Tumstock core: shared helpers, events, saved variables, item cache, slash commands.
local ADDON_NAME, T = ...

T.version = "0.5.0"

---------------------------------------------------------------------------
-- Printing
---------------------------------------------------------------------------
function T.Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    print("|cff66ccffTumstock:|r " .. table.concat(parts, " "))
end

-- Reports an internal error: red chat line (once per message), kept in
-- T.lastError and in TumstockCharDB.errors so it can be read after /reload.
local reported = {}
function T.Error(where, err)
    local msg = where .. ": " .. tostring(err)
    T.lastError = msg
    if T.db then
        T.db.errors = T.db.errors or {}
        if #T.db.errors < 20 then
            table.insert(T.db.errors, date("%H:%M:%S") .. " " .. msg)
        end
    end
    if not reported[msg] then
        reported[msg] = true
        print("|cffff4444Tumstock error:|r " .. msg)
    end
end

---------------------------------------------------------------------------
-- Secret-value safety
---------------------------------------------------------------------------
-- True if v is a secret value (or if we cannot prove it is not).
function T.IsSecret(v)
    if type(issecretvalue) ~= "function" then
        return false
    end
    local ok, res = pcall(issecretvalue, v)
    if not ok then
        return true
    end
    return res == true
end

-- Calls fn(...) and classifies the first return value:
--   "ok", value   - a plain, non-secret value (may be false)
--   "nil"         - returned nil
--   "secret"      - returned a secret value (never inspect it)
--   "error", msg  - the call raised an error
--   "missing"     - fn is not a function
function T.SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return "missing"
    end
    local ok, v = pcall(fn, ...)
    if not ok then
        return "error", tostring(v)
    end
    if T.IsSecret(v) then
        return "secret"
    end
    if v == nil then
        return "nil"
    end
    return "ok", v
end

-- Normalises an "in range" result to true/false, or nil if unusable.
-- Accepts booleans and the legacy 1/0 numbers.
function T.ToBool(status, v)
    if status ~= "ok" then
        return nil
    end
    if v == true or v == 1 then
        return true
    end
    if v == false or v == 0 then
        return false
    end
    return nil
end

---------------------------------------------------------------------------
-- Unit helpers
---------------------------------------------------------------------------
function T.UnitExists(unit)
    local s, v = T.SafeCall(UnitExists, unit)
    return s == "ok" and v and true or false
end

function T.IsHostile(unit)
    local s, v = T.SafeCall(UnitCanAttack, "player", unit)
    return s == "ok" and v and true or false
end

function T.InCombat()
    local s, v = T.SafeCall(InCombatLockdown)
    return s == "ok" and v and true or false
end

-- Same rule as LibRangeCheck: friendly-target item/interact checks are
-- protected while in combat lockdown.
function T.FriendlyLocked(unit)
    return T.InCombat() and not T.IsHostile(unit)
end

function T.UnitKind(unit)
    if not T.UnitExists(unit) then
        return "none"
    end
    local isPlayer = select(2, T.SafeCall(UnitIsPlayer, unit)) == true
    local hostile = T.IsHostile(unit)
    return (hostile and "hostile" or "friendly") .. (isPlayer and "-player" or "-npc")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function T.EventValid(event)
    if C_EventUtils and type(C_EventUtils.IsEventValid) == "function" then
        local s, v = T.SafeCall(C_EventUtils.IsEventValid, event)
        return s == "ok" and v == true
    end
    return true -- cannot verify; RegisterEvent is pcall-guarded below anyway
end

T.skippedEvents = {}

function T.On(event, fn)
    if not handlers[event] then
        if not T.EventValid(event) then
            T.skippedEvents[#T.skippedEvents + 1] = event
            return
        end
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            T.skippedEvents[#T.skippedEvents + 1] = event
            return
        end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then
        return
    end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, event, ...)
        if not ok then
            T.Error(event, err)
        end
    end
end)

---------------------------------------------------------------------------
-- Saved variables (per character; account SVs are not read back on Forever)
---------------------------------------------------------------------------
T.dbReady = {}

-- Runs fn(db) once the saved variables are loaded.
function T.WhenDBReady(fn)
    table.insert(T.dbReady, fn)
end

T.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then
        return
    end
    T.svWasLoaded = type(TumstockCharDB) == "table"
    if not T.svWasLoaded then
        TumstockCharDB = {}
    end
    local db = TumstockCharDB
    db.sessions = (db.sessions or 0) + 1
    T.db = db
    for _, fn in ipairs(T.dbReady) do
        local ok, err = pcall(fn, db)
        if not ok then
            T.Error("db ready", err)
        end
    end
end)

---------------------------------------------------------------------------
-- Item cache: request every candidate item once and track the results.
---------------------------------------------------------------------------
-- itemState[id] = "pending" | "loaded" | "failed" | "noexist"
T.itemState = {}
T.itemLoad = { requested = 0, loaded = 0, failed = 0, noexist = 0, done = false }

local function allCandidateIDs()
    local seen, ids = {}, {}
    for _, list in ipairs({ T.HarmItems, T.FriendItems }) do
        for _, e in ipairs(list) do
            if not seen[e[2]] then
                seen[e[2]] = true
                ids[#ids + 1] = e[2]
            end
        end
    end
    return ids
end

-- True if the client's item database knows this ID at all.
function T.ItemExists(id)
    if C_Item and C_Item.GetItemInfoInstant then
        local s, v = T.SafeCall(C_Item.GetItemInfoInstant, id)
        if s == "ok" then
            return true
        end
        if s == "nil" then
            return false
        end
    end
    return nil -- unknown
end

local function finishLoad()
    local L = T.itemLoad
    if L.done then
        return
    end
    L.done = true
    for id, st in pairs(T.itemState) do
        if st == "pending" then
            -- No callback arrived; if the client already has it cached it never fires.
            local s = T.SafeCall(C_Item.GetItemInfo, id)
            if s == "ok" then
                T.itemState[id] = "loaded"
                L.loaded = L.loaded + 1
            else
                T.itemState[id] = "failed"
                L.failed = L.failed + 1
            end
        end
    end
    if T.OnItemsLoaded then
        T.OnItemsLoaded()
    end
end

function T.LoadItems()
    if T.itemLoad.requested > 0 then
        return
    end
    local ids = allCandidateIDs()
    local L = T.itemLoad
    local i = 0
    local ticker
    -- Spread the requests over several frames: 150 per tick.
    ticker = C_Timer.NewTicker(0.05, function()
        for _ = 1, 150 do
            i = i + 1
            local id = ids[i]
            if not id then
                ticker:Cancel()
                C_Timer.After(5, finishLoad)
                return
            end
            L.requested = L.requested + 1
            if T.ItemExists(id) == false then
                T.itemState[id] = "noexist"
                L.noexist = L.noexist + 1
            else
                T.itemState[id] = "pending"
                if C_Item and C_Item.RequestLoadItemDataByID then
                    pcall(C_Item.RequestLoadItemDataByID, id)
                end
            end
        end
    end)
end

T.On("ITEM_DATA_LOAD_RESULT", function(_, id, success)
    if T.itemState[id] ~= "pending" then
        return
    end
    local L = T.itemLoad
    if success then
        T.itemState[id] = "loaded"
        L.loaded = L.loaded + 1
    else
        T.itemState[id] = "failed"
        L.failed = L.failed + 1
    end
end)

-- Runs fn once item loading is finished (immediately if it already is).
function T.WhenItemsLoaded(fn)
    if T.itemLoad.done then
        fn()
        return
    end
    T.LoadItems()
    T.Print("loading item data, wait a few seconds...")
    local ticker
    ticker = C_Timer.NewTicker(0.5, function()
        if T.itemLoad.done then
            ticker:Cancel()
            fn()
        end
    end)
end

T.On("PLAYER_LOGIN", function()
    T.LoadItems()
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
-- Everyday commands: /tum <name>. Test tools: /tum debug <name>.
T.commands = {}
T.debugCommands = {}

function T.Command(name, help, fn)
    T.commands[name] = { help = help, fn = fn }
end

function T.DebugCommand(name, help, fn)
    T.debugCommands[name] = { help = help, fn = fn }
end

-- Chat message shown only while debug output is on (/tum debug verbose).
function T.Debug(...)
    if T.db and T.db.debugVerbose then
        T.Print(...)
    end
end

local function listCommands(set, prefix)
    local names = {}
    for n in pairs(set) do
        names[#names + 1] = n
    end
    table.sort(names)
    for _, n in ipairs(names) do
        print("  " .. prefix .. n .. " - " .. set[n].help)
    end
end

local function run(c, rest)
    local ok, err = pcall(c.fn, rest)
    if not ok then
        T.Print("|cffff4444error:|r " .. tostring(err))
    end
end

T.DebugCommand("verbose", "toggle extra chat messages from the engine", function()
    T.db.debugVerbose = not T.db.debugVerbose
    T.Print("verbose " .. (T.db.debugVerbose and "on" or "off"))
end)

SLASH_TUMSTOCK1 = "/tum"
SLASH_TUMSTOCK2 = "/tumstock"
SlashCmdList.TUMSTOCK = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "debug" then
        local sub, subRest = rest:match("^(%S*)%s*(.-)$")
        local c = T.debugCommands[(sub or ""):lower()]
        if c then
            run(c, subRest)
        else
            T.Print("debug commands:")
            listCommands(T.debugCommands, "/tum debug ")
        end
        return
    end
    if cmd == "" and T.commands.config then
        run(T.commands.config, "")
        return
    end
    local c = T.commands[cmd]
    if c then
        run(c, rest)
        return
    end
    if T.debugCommands[cmd] then
        T.Print("that is a test tool now: /tum debug " .. cmd)
        return
    end
    T.Print("commands:")
    listCommands(T.commands, "/tum ")
    print("  /tum debug - test tools")
end
