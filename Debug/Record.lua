-- Tumstock record: log every range test's flips while you walk away from a
-- target, to learn the real order (and so the real spacing) of thresholds.
--   /tum debug record   - start; run again to stop and show the log
local _, T = ...

local INTERVAL = 0.1
local MAX_EVENTS = 20000
local PER_YARDS = 4 -- items tested per yards group

local ticker, rec, checkers, last

local function short(st, b)
    if st == "ok" then
        return b and "1" or "0"
    end
    return st:sub(1, 1) -- n(il) s(ecret) b(locked) e(rror) m(issing)
end

local function buildCheckers(unit)
    local list = {}
    local kind = T.IsHostile(unit) and "harm" or "friend"
    local yards, byYd = T.ItemsByYards(T.ItemList(kind))
    for _, yd in ipairs(yards) do
        local n = 0
        for _, e in ipairs(byYd[yd]) do
            -- Only items that answer right now are worth logging.
            if T.TestItem(e[2], unit) == "ok" then
                list[#list + 1] = { key = string.format("i%g:%d", yd, e[2]), fn = function(u)
                    return T.TestItem(e[2], u)
                end }
                n = n + 1
                if n >= PER_YARDS then
                    break
                end
            end
        end
    end
    -- Discovered items with a minimum range (logged, not used by the readout yet).
    local disc = T.db.discover and T.db.discover.items or {}
    local perGroup = {}
    for _, it in ipairs(disc) do
        local g = it.minR .. "-" .. it.maxR
        if it.minR > 0 and it[kind] == "ok" and (perGroup[g] or 0) < PER_YARDS then
            perGroup[g] = (perGroup[g] or 0) + 1
            list[#list + 1] = { key = string.format("i%g-%g:%d", it.minR, it.maxR, it.id), fn = function(u)
                return T.TestItem(it.id, u)
            end }
        end
    end
    for _, sp in ipairs(T.GetSpellbookSpells(true)) do
        local label = sp[3] > 0 and string.format("%g-%g", sp[3], sp[4]) or string.format("%g", sp[4])
        list[#list + 1] = { key = string.format("s%s:%d", label, sp[1]), fn = function(u)
            return T.TestSpell(sp[1], u, sp[2])
        end }
    end
    for idx = 1, 5 do
        list[#list + 1] = { key = "x" .. idx, fn = function(u)
            return T.TestInteract(idx, u)
        end }
    end
    return list
end

local function stop()
    ticker:Cancel()
    ticker = nil
    local lines = {}
    lines[#lines + 1] = string.format("Tumstock %s record | %s | %s \"%s\" | %d checkers, %d events, %.1fs",
        T.version, rec.time, rec.unit, rec.name, #checkers, #rec.events, GetTime() - rec.start)
    lines[#lines + 1] = "time  key  value  (i=item s=spell x=interact; 1=in 0=out n=nil s=secret b=blocked)"
    for _, ev in ipairs(rec.events) do
        lines[#lines + 1] = ev
    end
    T.ShowOutput("Tumstock record", lines)
    T.Print("recording stopped, " .. #rec.events .. " events. /reload to save them.")
end

T.DebugCommand("record", "start/stop logging every range test while you move", function()
    if ticker then
        stop()
        return
    end
    if not T.UnitExists("target") then
        T.Print("target something first.")
        return
    end
    local unit = "target"
    checkers = buildCheckers(unit)
    last = {}
    rec = { time = date("%Y-%m-%d %H:%M"), unit = T.UnitKind(unit), name = select(2, T.SafeCall(UnitName, unit)) or "?",
        start = GetTime(), events = {} }
    if T.IsSecret(rec.name) then
        rec.name = "?"
    end
    T.db.record = rec
    ticker = C_Timer.NewTicker(INTERVAL, function()
        if not T.UnitExists(unit) then
            return
        end
        local t = GetTime() - rec.start
        for _, c in ipairs(checkers) do
            local v = short(c.fn(unit))
            if v ~= last[c.key] then
                last[c.key] = v
                if #rec.events < MAX_EVENTS then
                    rec.events[#rec.events + 1] = string.format("%.1f %s %s", t, c.key, v)
                end
            end
        end
    end)
    T.Print("recording " .. #checkers .. " checkers. Walk slowly straight away from the target and back, then /tum debug record again.")
end)
