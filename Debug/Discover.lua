-- Tumstock discover: search the client's whole item database for items that
-- can be used for range checks, and read their exact range from their spell.
--   /tum debug discover        - full search (needs a target; takes a minute or two)
--   /tum debug discover test   - re-test the found items against the current target
--   /tum debug discover show   - show the last result again
local _, T = ...

local MAX_ID = 260000
local EXIST_PER_TICK = 4000
local SPELL_PER_TICK = 400
local REQUESTS_PER_TICK = 20 -- item data requests, to stay gentle on the server
local LOAD_WAIT = 15 -- seconds without a load result before giving up

-- True if the item's data is already in the client cache (nil = unknown).
local function isCached(id)
    if C_Item and C_Item.IsItemDataCachedByID then
        local s, v = T.SafeCall(C_Item.IsItemDataCachedByID, id)
        if s == "ok" then
            return v == true
        end
    end
    return false
end

local PHASE3_MAX = 90 -- never wait longer than this for item data

local running = false
local forceFinish = false
local pendingLoad = {} -- itemID -> true while waiting for ITEM_DATA_LOAD_RESULT

local function itemSpellID(id)
    local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local ok, _, spellID = pcall(fn, id)
    if ok and type(spellID) == "number" and not T.IsSecret(spellID) then
        return spellID
    end
end

local function spellRange(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local s, info = T.SafeCall(C_Spell.GetSpellInfo, spellID)
        if s == "ok" and type(info) == "table" then
            return info.minRange or 0, info.maxRange or 0, info.name
        end
    end
end

-- Rebuilds the engine's item lists; ResolveItemRanges reads the saved results.
function T.ApplyDiscovery()
    if T.RebuildItems then
        T.RebuildItems()
    end
end

-- Tests every found item against unit; stores status under it.harm/it.friend.
local function testAll(items, unit)
    local key = T.IsHostile(unit) and "harm" or "friend"
    for _, it in ipairs(items) do
        local st = T.TestItem(it.id, unit)
        -- Keep a previous "ok"; a later nil may just be a different unit type.
        if it[key] ~= "ok" then
            it[key] = st
        end
    end
    return key
end

local function report(title)
    local d = T.db.discover
    local lines = {}
    lines[#lines + 1] = string.format("Tumstock %s discover | %s | ids 1-%d", T.version, d.time, d.maxID)
    lines[#lines + 1] = string.format("items in database %d, with a use-spell %d, spell has a range %d, still unloaded %d",
        d.exist, d.withSpell, #d.items, d.unloaded)
    lines[#lines + 1] = "tested against: " .. table.concat(d.testedOn, ", ")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "yd(min)  ranged/harmOK/friendOK  IDs that answered (H=harm F=friend B=both)"
    local groups, keys = {}, {}
    for _, it in ipairs(d.items) do
        local k = it.minR > 0 and string.format("%g(%g)", it.maxR, it.minR) or string.format("%g", it.maxR)
        if not groups[k] then
            groups[k] = { maxR = it.maxR, minR = it.minR, n = 0, h = 0, f = 0, ids = {} }
            keys[#keys + 1] = k
        end
        local g = groups[k]
        g.n = g.n + 1
        local h, f = it.harm == "ok", it.friend == "ok"
        if h then g.h = g.h + 1 end
        if f then g.f = g.f + 1 end
        if h or f then
            g.ids[#g.ids + 1] = it.id .. (h and f and "B" or h and "H" or "F")
        end
    end
    table.sort(keys, function(a, b)
        local ga, gb = groups[a], groups[b]
        if ga.maxR ~= gb.maxR then
            return ga.maxR < gb.maxR
        end
        return ga.minR < gb.minR
    end)
    for _, k in ipairs(keys) do
        local g = groups[k]
        local shown = {}
        for i = 1, math.min(#g.ids, 8) do
            shown[i] = g.ids[i]
        end
        lines[#lines + 1] = string.format("  %-8s %d/%d/%d  %s%s", k, g.n, g.h, g.f,
            table.concat(shown, " "), #g.ids > 8 and (" +" .. (#g.ids - 8)) or "")
    end
    -- Where the LibRangeCheck tables disagree with the spell data.
    local tableYd = {}
    for _, list in ipairs({ T.HarmItems, T.FriendItems }) do
        for _, e in ipairs(list) do
            tableYd[e[2]] = tableYd[e[2]] or {}
            tableYd[e[2]][e[1]] = true
        end
    end
    local diffs = {}
    for _, it in ipairs(d.items) do
        local t = tableYd[it.id]
        if t and not t[it.maxR] then
            local ys = {}
            for y in pairs(t) do
                ys[#ys + 1] = tostring(y)
            end
            diffs[#diffs + 1] = string.format("%d table %s spell %g", it.id, table.concat(ys, "/"), it.maxR)
        end
    end
    lines[#lines + 1] = ""
    local nDiffs = #diffs
    for i = #diffs, 31, -1 do
        diffs[i] = nil
    end
    lines[#lines + 1] = "table vs spell range mismatches (" .. nDiffs .. "): " .. (nDiffs > 0 and table.concat(diffs, "; ") or "none")
        .. (nDiffs > 30 and "; ..." or "")
    T.ShowOutput(title, lines)
end

local function finish(d, found)
    -- Resolve items that were waiting for data.
    local unloaded = 0
    for id in pairs(pendingLoad) do
        local spellID = itemSpellID(id)
        if spellID then
            found[#found + 1] = { id = id, spell = spellID }
        else
            unloaded = unloaded + 1
        end
    end
    wipe(pendingLoad)
    d.unloaded = unloaded
    d.withSpell = #found
    for _, f in ipairs(found) do
        local minR, maxR = spellRange(f.spell)
        if maxR and maxR > 0 then
            d.items[#d.items + 1] = { id = f.id, spell = f.spell, minR = minR, maxR = maxR }
        end
    end
    table.sort(d.items, function(a, b)
        if a.maxR ~= b.maxR then
            return a.maxR < b.maxR
        end
        return a.id < b.id
    end)
    if T.UnitExists("target") then
        local key = testAll(d.items, "target")
        d.testedOn = { key .. " " .. T.UnitKind("target") }
    end
    running = false
    T.ApplyDiscovery()
    report("Tumstock discover")
    T.Print("discover done: " .. #d.items .. " items with a range. /reload to save.")
end

local function start()
    if running then
        T.Print("discover is already running.")
        return
    end
    if not T.UnitExists("target") then
        T.Print("target something first (a mob is best), then /tum debug discover.")
        return
    end
    running = true
    local d = { time = date("%Y-%m-%d %H:%M"), maxID = MAX_ID, exist = 0, items = {}, testedOn = {} }
    T.db.discover = d
    local existing, found = {}, {}
    local id, idx, reported = 0, 0, 0
    local lastLoad = GetTime()
    local phase3Start, lastProgress = nil, 0
    forceFinish = false
    local ticker
    T.Print("discover: phase 1/3, scanning item IDs 1-" .. MAX_ID .. "...")
    ticker = C_Timer.NewTicker(0.02, function()
        -- Phase 1: which IDs exist at all.
        if id < MAX_ID then
            local fn = C_Item.GetItemInfoInstant
            for _ = 1, EXIST_PER_TICK do
                id = id + 1
                if id > MAX_ID then
                    break
                end
                local ok, r = pcall(fn, id)
                if ok and r then
                    existing[#existing + 1] = id
                end
            end
            if id >= MAX_ID then
                d.exist = #existing
                T.Print("discover: phase 2/3, " .. #existing .. " items exist, reading their spells...")
            end
            return
        end
        -- Phase 2: read each item's use-spell; request data for uncached ones.
        if idx < #existing then
            local requests = 0
            for _ = 1, SPELL_PER_TICK do
                if requests >= REQUESTS_PER_TICK then
                    break
                end
                idx = idx + 1
                local iid = existing[idx]
                if not iid then
                    break
                end
                local spellID = itemSpellID(iid)
                if spellID then
                    found[#found + 1] = { id = iid, spell = spellID }
                elseif not isCached(iid) and C_Item.RequestLoadItemDataByID then
                    -- Uncached: we cannot tell yet whether it has a spell.
                    pendingLoad[iid] = true
                    requests = requests + 1
                    pcall(C_Item.RequestLoadItemDataByID, iid)
                end
            end
            lastLoad = GetTime()
            if idx - reported >= 5000 then
                reported = idx
                T.Print(string.format("discover: %d/%d items read, %d with a spell so far", idx, #existing, #found))
            end
            if idx >= #existing then
                T.Print("discover: phase 3/3, waiting for item data...")
            end
            return
        end
        -- Phase 3: wait until loads stop arriving (hard cap PHASE3_MAX seconds).
        local now = GetTime()
        phase3Start = phase3Start or now
        if now - lastProgress >= 5 then
            lastProgress = now
            local n = 0
            for _ in pairs(pendingLoad) do
                n = n + 1
            end
            T.Print(string.format("discover: waiting for %d items (%ds of max %ds), /tum debug discover finish to stop now",
                n, math.floor(now - phase3Start), PHASE3_MAX))
        end
        if forceFinish or next(pendingLoad) == nil or now - lastLoad > LOAD_WAIT or now - phase3Start > PHASE3_MAX then
            ticker:Cancel()
            T.discoverOnLoad = nil
            local ok, err = pcall(finish, d, found)
            if not ok then
                running = false
                T.Print("|cffff4444discover failed in the final step:|r " .. tostring(err))
            end
        end
    end)
    -- Loaded items are resolved as they arrive.
    T.discoverOnLoad = function(iid)
        if pendingLoad[iid] then
            pendingLoad[iid] = nil
            lastLoad = GetTime()
            local spellID = itemSpellID(iid)
            if spellID then
                found[#found + 1] = { id = iid, spell = spellID }
            end
        end
    end
end

T.On("ITEM_DATA_LOAD_RESULT", function(_, iid)
    if T.discoverOnLoad then
        T.discoverOnLoad(iid)
    end
end)

T.DebugCommand("discover", "search all item IDs for range items ('test' = retest vs target, 'show', 'finish')", function(arg)
    arg = (arg or ""):lower()
    if arg == "finish" then
        if running then
            forceFinish = true
            T.Print("discover: finishing with what has loaded so far...")
        else
            T.Print("discover is not running.")
        end
        return
    end
    if arg == "test" or arg == "show" then
        local d = T.db and T.db.discover
        if not d or #d.items == 0 then
            T.Print("no discover result yet - run /tum debug discover first.")
            return
        end
        if arg == "test" then
            if not T.UnitExists("target") then
                T.Print("select a target first.")
                return
            end
            local key = testAll(d.items, "target")
            d.testedOn[#d.testedOn + 1] = key .. " " .. T.UnitKind("target")
            T.ApplyDiscovery()
        end
        report("Tumstock discover")
        return
    end
    start()
end)
