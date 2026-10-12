-- Tumstock probe (phase 1): find out which range tests work on this client.
--   /tum debug status  - client/API/savedvariable facts
--   /tum debug scan    - which candidate items exist and respond against the target
--   /tum debug probe   - every working threshold vs the target right now
--   /tum debug combat  - like probe, but shows nil/secret/blocked per threshold
local _, T = ...

local function yn(b)
    return b and "yes" or "no"
end

local function safeStr(fn, ...)
    local s, v = T.SafeCall(fn, ...)
    if s == "ok" then
        return tostring(v)
    end
    return s
end

local function buildLine()
    local ok, ver, build, _, iface = pcall(GetBuildInfo)
    if not ok then
        return "build ?"
    end
    return string.format("build %s (%s) iface %s", tostring(ver), tostring(build), tostring(iface))
end

local function header(lines, what, unit)
    lines[#lines + 1] = string.format("Tumstock %s %s | %s | %s", T.version, what, buildLine(), date("%Y-%m-%d %H:%M"))
    if unit then
        lines[#lines + 1] = string.format("unit %s: %s \"%s\" lvl %s | combat %s | friendly-locked %s",
            unit, T.UnitKind(unit), safeStr(UnitName, unit), safeStr(UnitLevel, unit),
            yn(T.InCombat()), yn(T.FriendlyLocked(unit)))
    end
end

local function needTarget()
    if not T.UnitExists("target") then
        T.Print("select a target first.")
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- /tum debug status
---------------------------------------------------------------------------
T.DebugCommand("status", "client, API and saved-variable facts", function()
    local lines = {}
    header(lines, "status")
    lines[#lines + 1] = "WOW_PROJECT_ID " .. tostring(WOW_PROJECT_ID) .. " (MAINLINE=" .. tostring(WOW_PROJECT_MAINLINE) .. ")"
    local apis = {
        { "C_Item.IsItemInRange", C_Item and C_Item.IsItemInRange },
        { "IsItemInRange (global)", IsItemInRange },
        { "C_Item.RequestLoadItemDataByID", C_Item and C_Item.RequestLoadItemDataByID },
        { "C_Item.GetItemInfoInstant", C_Item and C_Item.GetItemInfoInstant },
        { "C_Spell.IsSpellInRange", C_Spell and C_Spell.IsSpellInRange },
        { "C_Spell.GetSpellInfo", C_Spell and C_Spell.GetSpellInfo },
        { "C_SpellBook.GetNumSpellBookSkillLines", C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines },
        { "CheckInteractDistance", CheckInteractDistance },
        { "issecretvalue", issecretvalue },
        { "C_EventUtils.IsEventValid", C_EventUtils and C_EventUtils.IsEventValid },
    }
    for _, a in ipairs(apis) do
        lines[#lines + 1] = string.format("  %-38s %s", a[1], type(a[2]) == "function" and "ok" or "MISSING")
    end
    local db = T.db or {}
    lines[#lines + 1] = string.format("SavedVariablesPerCharacter read back: %s (sessions=%s)", yn(T.svWasLoaded), tostring(db.sessions))
    local L = T.itemLoad
    lines[#lines + 1] = string.format("items: requested %d, noexist %d, loaded %d, failed %d, done %s",
        L.requested, L.noexist, L.loaded, L.failed, yn(L.done))
    if #T.skippedEvents > 0 then
        lines[#lines + 1] = "events not registered: " .. table.concat(T.skippedEvents, ", ")
    end
    lines[#lines + 1] = "spellbook spells with range: " .. #T.GetSpellbookSpells(false)
    lines[#lines + 1] = "last error: " .. tostring(T.lastError)
    T.ShowOutput("Tumstock status", lines)
end)

---------------------------------------------------------------------------
-- /tum debug scan
---------------------------------------------------------------------------
local srcOrder = { "E", "C", "R" }

local function scanList(lines, listName, list, unit, store)
    local yards, byYd = T.ItemsByYards(list)
    local total, exist, resp = 0, 0, 0
    local srcResp = { E = 0, C = 0, R = 0 }
    for _, e in ipairs(list) do
        total = total + 1
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = listName .. "  (yd: candidates/exist/respond/in  respondingIDs)"
    local stored = {}
    store[listName] = stored
    local all, allByYd = {}, {}
    for _, e in ipairs(list) do
        if not allByYd[e[1]] then
            allByYd[e[1]] = 0
            all[#all + 1] = e[1]
        end
        allByYd[e[1]] = allByYd[e[1]] + 1
    end
    table.sort(all)
    for _, yd in ipairs(all) do
        local entries = byYd[yd] or {}
        local ex, rs, inn = #entries, 0, 0
        local ids, inIDs, outIDs = {}, {}, {}
        for _, e in ipairs(entries) do
            local st, b = T.TestItem(e[2], unit)
            if st == "ok" then
                rs = rs + 1
                if b then
                    inn = inn + 1
                    inIDs[#inIDs + 1] = e[2]
                else
                    outIDs[#outIDs + 1] = e[2]
                end
                ids[#ids + 1] = e[2]
                for i = 1, #e[3] do
                    local c = e[3]:sub(i, i)
                    srcResp[c] = srcResp[c] + 1
                end
            end
        end
        exist = exist + ex
        resp = resp + rs
        local shown = {}
        for i = 1, math.min(#ids, 6) do
            shown[i] = tostring(ids[i])
        end
        local more = #ids > 6 and (" +" .. (#ids - 6)) or ""
        -- When the items disagree, name the minority side (likely wrong range on Forever).
        local mixed = ""
        if #inIDs > 0 and #outIDs > 0 then
            local few, tag = inIDs, "in:"
            if #outIDs < #inIDs then
                few, tag = outIDs, "out:"
            end
            local f = {}
            for i = 1, math.min(#few, 6) do
                f[i] = tostring(few[i])
            end
            mixed = "  MIXED " .. tag .. table.concat(f, ",") .. (#few > 6 and ",..." or "")
        end
        lines[#lines + 1] = string.format("  %3g: %d/%d/%d/%d  %s%s%s", yd, allByYd[yd], ex, rs, inn, table.concat(shown, " "), more, mixed)
        if #ids > 0 then
            stored[#stored + 1] = { yd = yd, ids = ids, inIDs = inIDs }
        end
    end
    lines[#lines + 1] = string.format("  total %d candidates, %d exist, %d respond | responders by source: E=%d C=%d R=%d",
        total, exist, resp, srcResp.E, srcResp.C, srcResp.R)
end

T.DebugCommand("scan", "item scan against current target", function()
    if not needTarget() then
        return
    end
    T.WhenItemsLoaded(function()
        local unit = "target"
        local lines = {}
        header(lines, "scan", unit)
        local L = T.itemLoad
        lines[#lines + 1] = string.format("items: requested %d, noexist %d, loaded %d, failed %d",
            L.requested, L.noexist, L.loaded, L.failed)
        if T.FriendlyLocked(unit) then
            lines[#lines + 1] = "NOTE: friendly target in combat - item checks skipped. Leave combat and rerun."
        end
        local store = { time = date("%Y-%m-%d %H:%M:%S"), unit = T.UnitKind(unit), name = safeStr(UnitName, unit) }
        scanList(lines, "HARM", T.HarmItems, unit, store)
        scanList(lines, "FRIEND", T.FriendItems, unit, store)
        if T.db then
            T.db.scans = T.db.scans or {}
            T.db.scans[store.unit] = store
        end
        T.ShowOutput("Tumstock scan", lines)
        T.Print("scan done (" .. store.unit .. "). Also saved to SavedVariables on /reload or logout.")
    end)
end)

---------------------------------------------------------------------------
-- /tum debug probe and /tum debug combat
---------------------------------------------------------------------------
local statusOrder = { "ok", "nil", "secret", "blocked", "error", "missing" }

local function probe(mode, arg)
    if not needTarget() then
        return
    end
    T.WhenItemsLoaded(function()
        local unit = "target"
        local force = mode == "combat" and arg == "force"
        local lines = {}
        header(lines, mode == "combat" and ("combat" .. (force and " FORCE" or "")) or "probe", unit)
        if mode == "combat" and not T.InCombat() then
            lines[#lines + 1] = "WARNING: you are NOT in combat - rerun while in combat."
        end
        local hostile = T.IsHostile(unit)
        local list = T.ItemList(hostile and "harm" or "friend")
        local yards, byYd = T.ItemsByYards(list)
        local results = {}

        lines[#lines + 1] = ""
        lines[#lines + 1] = (hostile and "HARM" or "FRIEND") .. " items  (yd  result  in/out  [other statuses])"
        for _, yd in ipairs(yards) do
            local cnt = {}
            local nIn, nOut = 0, 0
            local inIDs, outIDs = {}, {}
            for _, e in ipairs(byYd[yd]) do
                local st, b = T.TestItem(e[2], unit, force)
                cnt[st] = (cnt[st] or 0) + 1
                if st == "ok" then
                    if b then
                        nIn = nIn + 1
                        inIDs[#inIDs + 1] = e[2]
                    else
                        nOut = nOut + 1
                        outIDs[#outIDs + 1] = e[2]
                    end
                end
            end
            local other = {}
            for _, st in ipairs(statusOrder) do
                if st ~= "ok" and cnt[st] then
                    other[#other + 1] = st .. "=" .. cnt[st]
                end
            end
            local works = nIn + nOut > 0
            if works or mode == "combat" then
                local res = "-"
                if nIn > 0 and nOut > 0 then
                    res = "MIXED"
                elseif nIn > 0 then
                    res = "IN"
                    results[#results + 1] = { yd, true }
                elseif nOut > 0 then
                    res = "OUT"
                    results[#results + 1] = { yd, false }
                end
                local otherStr = (mode == "combat" and #other > 0) and ("  [" .. table.concat(other, " ") .. "]") or ""
                if res == "MIXED" then
                    -- Name the minority side: those items likely have a different range here.
                    local few, tag = inIDs, "in:"
                    if #outIDs < #inIDs then
                        few, tag = outIDs, "out:"
                    end
                    local shown = {}
                    for i = 1, math.min(#few, 6) do
                        shown[i] = tostring(few[i])
                    end
                    otherStr = otherStr .. "  " .. tag .. table.concat(shown, ",") .. (#few > 6 and ",..." or "")
                end
                lines[#lines + 1] = string.format("  %3g  %-5s %d/%d%s", yd, res, nIn, nOut, otherStr)
            end
        end

        lines[#lines + 1] = ""
        lines[#lines + 1] = "spells  (yd  result  name(id) minRange)"
        for _, sp in ipairs(T.GetSpellbookSpells(true)) do
            local st, b = T.TestSpell(sp[1], unit, sp[2])
            local res = st == "ok" and (b and "IN" or "OUT") or st
            if st == "ok" or mode == "combat" then
                lines[#lines + 1] = string.format("  %3g  %-6s %s(%d)%s", sp[4], res, sp[2], sp[1],
                    sp[3] > 0 and (" min " .. sp[3]) or "")
            end
            -- Spells with a minimum range are ambiguous when "out"; only use "in".
            if st == "ok" and sp[4] > 0 and (sp[3] == 0 or b) then
                if sp[3] == 0 then
                    results[#results + 1] = { sp[4], b }
                else
                    results[#results + 1] = { sp[4], true }
                    results[#results + 1] = { sp[3], false }
                end
            end
        end

        lines[#lines + 1] = ""
        local parts = {}
        for _, idx in ipairs({ 1, 2, 3, 4, 5 }) do
            local st, b = T.TestInteract(idx, unit, force)
            parts[#parts + 1] = idx .. "=" .. (st == "ok" and (b and "IN" or "OUT") or st)
        end
        lines[#lines + 1] = "interact (3~8yd, 4~28yd): " .. table.concat(parts, " ")

        local minYd, maxYd, bad = T.ComputeRange(results)
        lines[#lines + 1] = ""
        lines[#lines + 1] = "=> range " .. T.FormatRange(minYd, maxYd) .. " yd" .. (bad and "  (INCONSISTENT thresholds above max)" or "")
        T.ShowOutput("Tumstock " .. mode, lines)
    end)
end

T.DebugCommand("probe", "all working thresholds vs target", function(arg)
    probe("probe", arg)
end)

T.DebugCommand("combat", "probe in combat; shows nil/secret/blocked ('force' = call blocked APIs anyway)", function(arg)
    probe("combat", arg)
end)

---------------------------------------------------------------------------
-- /tum debug engine
---------------------------------------------------------------------------
T.DebugCommand("engine", "what the range engine is using, and its answer for the target", function()
    local lines = {}
    header(lines, "engine", T.UnitExists("target") and "target" or nil)
    for _, l in ipairs(T.EngineSummary()) do
        lines[#lines + 1] = l
    end
    if T.UnitExists("target") then
        local minYd, maxYd, known, exact = T.Measure("target")
        lines[#lines + 1] = "=> target: " .. (exact and string.format("exact %.1f", minYd)
            or known and T.FormatRange(minYd, maxYd) or "?")
    end
    T.ShowOutput("Tumstock engine", lines)
end)
