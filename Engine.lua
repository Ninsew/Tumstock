-- Tumstock engine: works out a [min, max] yards bracket for a unit.
--
-- Sources, all verified on WoW Forever 1.60:
--   * items (C_Item.IsItemInRange) at their use-spell range: 5..45 step 5, 100
--   * interact distance: 3 = duel ~8, 2 = trade ~9, 4 = follow ~28
--   * the player's own spells with a range (min-range spells too)
--   * UnitDistanceSquared when the client gives it (group members only)
-- Every threshold is tested each update (about 13 + spells, a few dozen
-- cheap calls) rather than binary-searched: a full sweep lets one wrong
-- answer be outvoted instead of sending the search the wrong way.
local _, T = ...

-- Up to VOTERS working items per yards group vote; a single item with a
-- wrong range on this client is outvoted. Ties count as "no answer".
local VOTERS = 3

-- voters[cache][yd] = itemIDs that gave real answers; dead[cache][id] = true
-- once an item returned something unusable against a visible unit. cache is
-- the item list kind plus player/NPC ("harmP", "friendN"...): some items
-- only work on players (bandages) or only on NPCs.
local voters, dead = {}, {}

local function cacheFor(key)
    if not voters[key] then
        voters[key], dead[key] = {}, {}
    end
    return voters[key], dead[key]
end
local itemGroups = {} -- kind -> { yards = {...}, byYd = {...} }
local spells = { harm = {}, friend = {} }

-- Set when trade (2) says "out" while duel (3, shorter) says "in": the trade
-- check does not work here, so it is dropped for the session (as Range Lens does).
local tradeBroken = false

---------------------------------------------------------------------------
-- Building the checker lists
---------------------------------------------------------------------------
local function rebuildItems()
    T.ResolveItemRanges()
    voters, dead = {}, {}
    for _, kind in ipairs({ "harm", "friend" }) do
        local yards, byYd = T.ItemsByYards(T.ItemList(kind))
        itemGroups[kind] = { yards = yards, byYd = byYd }
    end
    if T.OnEngineChanged then
        T.OnEngineChanged()
    end
end

local function isKind(fn, id)
    if type(fn) ~= "function" then
        return true -- cannot tell; an unusable spell just answers nil
    end
    local s, v = T.SafeCall(fn, id)
    return s == "ok" and v == true
end

local function rebuildSpells()
    spells = { harm = {}, friend = {} }
    for _, sp in ipairs(T.GetSpellbookSpells(false)) do
        if isKind(C_Spell and C_Spell.IsSpellHarmful, sp[1]) then
            table.insert(spells.harm, sp)
        end
        if isKind(C_Spell and C_Spell.IsSpellHelpful, sp[1]) then
            table.insert(spells.friend, sp)
        end
    end
    if T.OnEngineChanged then
        T.OnEngineChanged()
    end
end

T.RebuildItems = rebuildItems
T.OnItemsLoaded = rebuildItems

T.On("PLAYER_LOGIN", function()
    rebuildItems()
    rebuildSpells()
end)
for _, ev in ipairs({ "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE", "PLAYER_EQUIPMENT_CHANGED" }) do
    T.On(ev, rebuildSpells)
end
-- An item that gave nothing on one target may work on the next.
T.On("PLAYER_TARGET_CHANGED", function()
    for key in pairs(dead) do
        dead[key] = {}
    end
end)

---------------------------------------------------------------------------
-- Measuring
---------------------------------------------------------------------------
-- Tests one yards group; returns true/false or nil if nothing answered.
local function testGroup(kind, cache, yd, unit, visible)
    local v, d = cacheFor(cache)
    local list = v[yd]
    if not list then
        list = {}
        v[yd] = list
    end
    local nIn, nOut = 0, 0
    local i = 1
    while list[i] do
        local st, b = T.TestItem(list[i], unit)
        if st == "ok" then
            if b then nIn = nIn + 1 else nOut = nOut + 1 end
            i = i + 1
        elseif st == "blocked" or st == "secret" then
            return nil
        else
            table.remove(list, i)
        end
    end
    -- Recruit more voters (only against a visible unit, so dead-marking is fair).
    if #list < VOTERS and visible then
        local inList = {}
        for _, id in ipairs(list) do
            inList[id] = true
        end
        for _, e in ipairs(itemGroups[kind].byYd[yd]) do
            local cid = e[2]
            if not d[cid] and not inList[cid] then
                local st, b = T.TestItem(cid, unit)
                if st == "ok" then
                    list[#list + 1] = cid
                    if b then nIn = nIn + 1 else nOut = nOut + 1 end
                    if #list >= VOTERS then
                        break
                    end
                elseif st == "blocked" or st == "secret" then
                    return nil
                else
                    d[cid] = true
                end
            end
        end
    end
    if nIn > nOut then
        return true
    elseif nOut > nIn then
        return false
    end
    return nil
end

function T.UnitIsMe(unit)
    local s, v = T.SafeCall(UnitIsUnit, unit, "player")
    return s == "ok" and v == true
end

-- Returns minYd, maxYd, known, exact.
--   known = false/nil when nothing answered.
--   exact = true when minYd == maxYd is a real measured distance.
--   minYd nil = closer than maxYd; maxYd nil = farther than minYd.
function T.Measure(unit)
    if T.UnitIsMe(unit) then
        return 0, 0, true, true
    end
    local exact = T.ExactDistance(unit)
    if exact then
        return exact, exact, true, true
    end
    local _, visible = T.SafeCall(UnitIsVisible, unit)
    visible = visible == true
    local kind = T.IsHostile(unit) and "harm" or "friend"
    local isPlayer = select(2, T.SafeCall(UnitIsPlayer, unit)) == true
    local cache = kind .. (isPlayer and "P" or "N")
    local results = {}

    local grp = itemGroups[kind]
    if grp and not T.FriendlyLocked(unit) then
        for _, yd in ipairs(grp.yards) do
            local b = testGroup(kind, cache, yd, unit, visible)
            if b ~= nil then
                results[#results + 1] = { yd, b }
            end
        end
    end

    local excluded = {}
    for _, sp in ipairs(spells[kind]) do
        local st, b = T.TestSpell(sp[1], unit, sp[2])
        if st == "ok" then
            if sp[3] == 0 then
                results[#results + 1] = { sp[4], b }
            elseif b then
                -- Min-range spell (e.g. Charge 8-25): "in" pins both ends.
                results[#results + 1] = { sp[4], true }
                results[#results + 1] = { sp[3], false }
            else
                -- "Out" is too close or too far; resolved after the others.
                excluded[#excluded + 1] = { sp[3], sp[4] }
            end
        end
    end

    local inter = {}
    for idx, yd in pairs(T.InteractYards) do
        if not (idx == 2 and tradeBroken) then
            local st, b = T.TestInteract(idx, unit)
            if st == "ok" then
                inter[idx] = b
                results[#results + 1] = { yd, b }
            end
        end
    end
    if inter[2] == false and inter[3] == true and not tradeBroken then
        tradeBroken = true
        T.Debug("trade-distance check contradicts duel check, dropping it.")
    end

    if #results == 0 then
        return nil, nil, false
    end
    local minYd, maxYd = T.ComputeRange(results)
    minYd, maxYd = T.ApplyMinRangeOuts(minYd, maxYd, excluded)
    return minYd, maxYd, true, false
end

-- Sorted distinct yards the engine can tell apart for a kind of unit.
function T.Thresholds(kind)
    local set, out = {}, {}
    local g = itemGroups[kind]
    for _, yd in ipairs(g and g.yards or {}) do
        set[yd] = true
    end
    for idx, yd in pairs(T.InteractYards) do
        if not (idx == 2 and tradeBroken) then
            set[yd] = true
        end
    end
    for _, sp in ipairs(spells[kind]) do
        set[sp[4]] = true
        if sp[3] > 0 then
            set[sp[3]] = true
        end
    end
    for yd in pairs(set) do
        out[#out + 1] = yd
    end
    table.sort(out)
    return out
end

-- Short summary of what the engine is using, for /tum debug engine.
function T.EngineSummary()
    local lines = {}
    for _, kind in ipairs({ "harm", "friend" }) do
        local g = itemGroups[kind]
        local parts = {}
        for _, yd in ipairs(g and g.yards or {}) do
            parts[#parts + 1] = string.format("%g(%d)", yd, #g.byYd[yd])
        end
        lines[#lines + 1] = kind .. " item yards (candidates): " .. table.concat(parts, " ")
        local sp = {}
        for _, s in ipairs(spells[kind]) do
            sp[#sp + 1] = string.format("%s %g-%g", s[2], s[3], s[4])
        end
        lines[#lines + 1] = kind .. " spells: " .. (#sp > 0 and table.concat(sp, ", ") or "none")
    end
    local inter = {}
    for idx, yd in pairs(T.InteractYards) do
        inter[#inter + 1] = idx .. "=" .. yd .. ((idx == 2 and tradeBroken) and "(off)" or "")
    end
    table.sort(inter)
    lines[#lines + 1] = "interact: " .. table.concat(inter, " ")
    return lines
end
