-- Tumstock plates: test whether the target's nameplate reveals distance.
-- Nameplates shrink/fade between two distances set by CVars. If an addon can
-- read the plate's scale or alpha, that would be a continuous distance signal.
--   /tum debug plates          - snapshot: plate scale/alpha, CVars, exact-distance API
--   /tum debug plates set      - spread scale and alpha over 0-60 yd (out of combat)
--   /tum debug plates restore  - put the CVars back
--   /tum debug plates watch    - print bracket + plate values every second (again = stop)
local _, T = ...

local CVARS = {
    "nameplateMaxDistance",
    "nameplateMinScale", "nameplateMaxScale", "nameplateMinScaleDistance", "nameplateMaxScaleDistance",
    "nameplateMinAlpha", "nameplateMaxAlpha", "nameplateMinAlphaDistance", "nameplateMaxAlphaDistance",
    "nameplateSelectedScale", "nameplateLargerScale",
}

-- Values for "set": full size at 0 yd, smallest at 60 yd; same for alpha.
local TEST_VALUES = {
    nameplateMinScale = "0.4", nameplateMaxScale = "1",
    nameplateMaxScaleDistance = "0", nameplateMinScaleDistance = "60",
    nameplateMinAlpha = "0.3", nameplateMaxAlpha = "1",
    nameplateMaxAlphaDistance = "0", nameplateMinAlphaDistance = "60",
    nameplateSelectedScale = "1",
}

local function getCVar(name)
    local fn = (C_CVar and C_CVar.GetCVar) or GetCVar
    local s, v = T.SafeCall(fn, name)
    return s == "ok" and tostring(v) or s
end

local function setCVar(name, value)
    local fn = (C_CVar and C_CVar.SetCVar) or SetCVar
    local ok, err = pcall(fn, name, value)
    return ok, err
end

-- Calls obj:method() safely; returns a short string.
local function read(obj, method)
    if not obj or type(obj[method]) ~= "function" then
        return "missing"
    end
    local ok, a, b = pcall(obj[method], obj)
    if not ok then
        return "ERR(" .. tostring(a):gsub("^.*:%d+: ", ""):sub(1, 60) .. ")"
    end
    if T.IsSecret(a) then
        return "secret"
    end
    if type(a) == "number" then
        if type(b) == "number" and not T.IsSecret(b) then
            return string.format("%.4f,%.4f", a, b)
        end
        return string.format("%.4f", a)
    end
    return tostring(a)
end

local function plateValues(unit)
    local s, plate = T.SafeCall(C_NamePlate and C_NamePlate.GetNamePlateForUnit, unit)
    if s ~= "ok" then
        return "plate: " .. s
    end
    local uf = plate.UnitFrame
    return string.format("plate scale=%s eff=%s alpha=%s size=%s,%s center=%s | unitframe scale=%s eff=%s alpha=%s",
        read(plate, "GetScale"), read(plate, "GetEffectiveScale"), read(plate, "GetAlpha"),
        read(plate, "GetWidth"), read(plate, "GetHeight"), read(plate, "GetCenter"),
        read(uf, "GetScale"), read(uf, "GetEffectiveScale"), read(uf, "GetAlpha"))
end

local function bracket(unit)
    local minYd, maxYd, any, exact = T.Measure(unit)
    if exact then
        return string.format("exact %.1f", minYd)
    end
    return any and T.FormatRange(minYd, maxYd) or "?"
end

local function exactLine(unit)
    if type(UnitDistanceSquared) ~= "function" then
        return "UnitDistanceSquared: missing"
    end
    local ok, sq, checked = pcall(UnitDistanceSquared, unit)
    if not ok then
        return "UnitDistanceSquared: error " .. tostring(sq)
    end
    local function show(v)
        if T.IsSecret(v) then
            return "secret"
        end
        return tostring(v)
    end
    return "UnitDistanceSquared: " .. show(sq) .. ", checked=" .. show(checked)
end

local watchTicker

T.DebugCommand("plates", "nameplate distance test ('set', 'restore', 'watch')", function(arg)
    arg = (arg or ""):lower()
    if arg == "set" or arg == "restore" then
        if T.InCombat() then
            T.Print("leave combat first (nameplate settings are locked in combat).")
            return
        end
        T.db.plateCVars = T.db.plateCVars or {}
        local saved = T.db.plateCVars
        for name, value in pairs(TEST_VALUES) do
            if arg == "set" then
                if saved[name] == nil then
                    saved[name] = getCVar(name)
                end
                local ok, err = setCVar(name, value)
                if not ok then
                    T.Print(name .. ": " .. tostring(err))
                end
            elseif saved[name] ~= nil then
                setCVar(name, saved[name])
            end
        end
        if arg == "restore" then
            T.db.plateCVars = nil
        end
        T.Print(arg == "set" and "test nameplate settings applied (/tum debug plates restore to undo)." or "nameplate settings restored.")
        return
    end
    if arg == "watch" then
        if watchTicker then
            watchTicker:Cancel()
            watchTicker = nil
            T.Print("watch stopped.")
            T.ShowOutput("Tumstock plates watch", T.db.plateWatch)
            return
        end
        local log = { string.format("Tumstock %s plates watch | %s", T.version, date("%Y-%m-%d %H:%M")) }
        for _, name in ipairs(CVARS) do
            log[#log + 1] = "  " .. name .. " " .. getCVar(name)
        end
        T.db.plateWatch = log
        local start, failed = GetTime(), false
        local function tick()
            local line
            if not T.UnitExists("target") then
                -- No target: log every visible plate (non-target plates may
                -- fade with distance, the target's never does).
                local s, plates = T.SafeCall(C_NamePlate and C_NamePlate.GetNamePlates)
                local parts = {}
                if s == "ok" and type(plates) == "table" then
                    for _, plate in ipairs(plates) do
                        local token = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
                        if token and not T.IsSecret(token) and #parts < 4 then
                            parts[#parts + 1] = string.format("%s %s s%s a%s", token:gsub("nameplate", "np"),
                                bracket(token), read(plate, "GetScale"), read(plate, "GetAlpha"))
                        end
                    end
                end
                line = #parts > 0 and table.concat(parts, " | ") or "(no target, no plates: " .. s .. ")"
            else
                local s, plate = T.SafeCall(C_NamePlate and C_NamePlate.GetNamePlateForUnit, "target")
                if s == "ok" then
                    line = string.format("%-6s scale %s alpha %s", bracket("target"),
                        read(plate, "GetScale"), read(plate, "GetAlpha"))
                else
                    line = bracket("target") .. "  (no nameplate: " .. s .. ")"
                end
            end
            line = string.format("%5.1f  %s", GetTime() - start, line)
            log[#log + 1] = line
            print(line)
        end
        watchTicker = C_Timer.NewTicker(1, function()
            local ok, err = pcall(tick)
            if not ok and not failed then
                failed = true
                T.Print("|cffff4444watch error:|r " .. tostring(err))
            end
        end)
        T.Print("watch started: walk slowly away from the target; /tum debug plates watch to stop.")
        local ok, err = pcall(tick)
        if not ok then
            failed = true
            T.Print("|cffff4444watch error:|r " .. tostring(err))
        end
        return
    end
    if not T.UnitExists("target") then
        T.Print("select a target first.")
        return
    end
    local lines = {}
    lines[#lines + 1] = string.format("Tumstock %s plates | %s | target %s | combat %s", T.version,
        date("%Y-%m-%d %H:%M"), T.UnitKind("target"), T.InCombat() and "yes" or "no")
    lines[#lines + 1] = "bracket now: " .. bracket("target")
    lines[#lines + 1] = exactLine("target")
    lines[#lines + 1] = plateValues("target")
    lines[#lines + 1] = ""
    for _, name in ipairs(CVARS) do
        lines[#lines + 1] = string.format("  %-28s %s", name, getCVar(name))
    end
    T.ShowOutput("Tumstock plates", lines)
end)
