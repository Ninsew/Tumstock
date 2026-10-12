-- Tumstock checks: individual "is unit within N yards?" tests and range math.
local _, T = ...

---------------------------------------------------------------------------
-- Single tests. Each returns status, inRange:
--   status = "ok" (inRange is true/false), "nil", "secret", "error",
--            "missing", or "blocked" (skipped: friendly target in combat).
---------------------------------------------------------------------------
local function classify(status, v)
    if status == "ok" then
        local b = T.ToBool(status, v)
        if b == nil then
            return "nil"
        end
        return "ok", b
    end
    return status
end

function T.TestItem(id, unit, force)
    if not force and T.FriendlyLocked(unit) then
        return "blocked"
    end
    local fn = (C_Item and C_Item.IsItemInRange) or IsItemInRange
    return classify(T.SafeCall(fn, id, unit))
end

function T.TestSpell(spellID, unit, name)
    if C_Spell and C_Spell.IsSpellInRange then
        return classify(T.SafeCall(C_Spell.IsSpellInRange, spellID, unit))
    end
    return classify(T.SafeCall(IsSpellInRange, name, unit))
end

function T.TestInteract(idx, unit, force)
    if not force and T.FriendlyLocked(unit) then
        return "blocked"
    end
    return classify(T.SafeCall(CheckInteractDistance, unit, idx))
end

-- Approximate yards for CheckInteractDistance indexes: 3 = duel, 2 = trade,
-- 4 = follow. Values measured by LibRangeCheck-3.0 (trade is off there; Range
-- Lens uses it with a duel cross-check). Tauren/Undead have shorter reach.
T.InteractYards = { [3] = 8, [2] = 9, [4] = 28 }
T.On("PLAYER_LOGIN", function()
    local ok, _, race = pcall(UnitRace, "player")
    if ok and race == "Tauren" then
        T.InteractYards = { [3] = 6, [2] = 7, [4] = 25 }
    elseif ok and race == "Scourge" then
        T.InteractYards = { [3] = 7, [2] = 8, [4] = 27 }
    end
end)

-- Exact distance, if the client gives one for this unit (normally only group
-- members). Returns yards or nil.
function T.ExactDistance(unit)
    if type(UnitDistanceSquared) ~= "function" then
        return nil
    end
    local ok, sq, checked = pcall(UnitDistanceSquared, unit)
    if not ok or T.IsSecret(sq) or T.IsSecret(checked) then
        return nil
    end
    if checked and type(sq) == "number" and sq >= 0 then
        return math.sqrt(sq)
    end
    return nil
end

-- Narrows [minYd, maxYd] with min-range spells that said "out" (e.g. Charge
-- 8-25 out while something <= 25 is in means closer than 8). excluded is a
-- list of { minRange, maxRange }.
function T.ApplyMinRangeOuts(minYd, maxYd, excluded)
    for _ = 1, #excluded do
        local changed = false
        for _, ex in ipairs(excluded) do
            -- Only narrow when the result stays a valid bracket; otherwise
            -- the checks contradict each other and the spell is ignored.
            if maxYd and maxYd <= ex[2] and maxYd > ex[1] and (not minYd or ex[1] > minYd) then
                maxYd = ex[1]
                changed = true
            elseif minYd and minYd >= ex[1] and minYd < ex[2] and (not maxYd or ex[2] < maxYd) then
                minYd = ex[2]
                changed = true
            end
        end
        if not changed then
            break
        end
    end
    return minYd, maxYd
end

---------------------------------------------------------------------------
-- Spellbook: every active spell with a range.
---------------------------------------------------------------------------
local function spellInfo(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local s, info = T.SafeCall(C_Spell.GetSpellInfo, spellID)
        if s == "ok" and type(info) == "table" then
            return info.name, info.minRange or 0, info.maxRange or 0
        end
        return nil
    end
    if GetSpellInfo then
        local ok, name, _, _, _, minR, maxR = pcall(GetSpellInfo, spellID)
        if ok and name then
            return name, minR or 0, maxR or 0
        end
    end
    return nil
end

local function collectSpellIDs()
    local ids = {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
        local s, n = T.SafeCall(C_SpellBook.GetNumSpellBookSkillLines)
        if s ~= "ok" then
            return ids
        end
        for line = 1, n do
            local s2, info = T.SafeCall(C_SpellBook.GetSpellBookSkillLineInfo, line)
            local offSpec = type(info) == "table" and info.offSpecID and info.offSpecID ~= 0
            if s2 == "ok" and type(info) == "table" and not offSpec then
                local first = (info.itemIndexOffset or 0) + 1
                local last = (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0)
                for idx = first, last do
                    local s3, item = T.SafeCall(C_SpellBook.GetSpellBookItemInfo, idx, bank)
                    if s3 == "ok" and type(item) == "table" and item.itemType == spellType
                        and not item.isPassive and not item.isOffSpec then
                        local id = item.spellID or item.actionID
                        if id then
                            ids[#ids + 1] = id
                        end
                    end
                end
            end
        end
    end
    return ids
end

-- Returns a list of { spellID, name, minRange, maxRange } (maxRange > 0 only
-- unless includeMelee), sorted by maxRange. Duplicate spellIDs collapsed.
function T.GetSpellbookSpells(includeMelee)
    local out, seen = {}, {}
    for _, id in ipairs(collectSpellIDs()) do
        if not seen[id] then
            seen[id] = true
            local name, minR, maxR = spellInfo(id)
            if name and (maxR > 0 or includeMelee) then
                out[#out + 1] = { id, name, minR, maxR }
            end
        end
    end
    table.sort(out, function(a, b)
        if a[4] ~= b[4] then
            return a[4] < b[4]
        end
        return a[1] < b[1]
    end)
    return out
end

---------------------------------------------------------------------------
-- Item candidates grouped by yards.
---------------------------------------------------------------------------
-- An item's real range on this client is the range of its use-spell. It is
-- read for every candidate once item data has loaded (ResolveItemRanges) and
-- for /tum debug discover results, and overrides the LibRangeCheck tables.
T.ItemYardsFromSpell = {} -- itemID -> max range (items without a minimum)
T.ItemMinRange = {}       -- itemID -> min range, for items that have one

-- Range of an item's use-spell: minRange, maxRange, or nil if unknown.
function T.ItemSpellRange(id)
    local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local ok, _, spellID = pcall(fn, id)
    if not ok or type(spellID) ~= "number" or T.IsSecret(spellID) then
        return nil
    end
    local _, minR, maxR = spellInfo(spellID)
    if maxR and maxR > 0 then
        return minR, maxR
    end
    return nil
end

local function learnItemRange(id, minR, maxR)
    if minR and minR > 0 then
        T.ItemMinRange[id] = minR
    elseif maxR then
        T.ItemYardsFromSpell[id] = maxR
    end
end

-- Reads the use-spell range of every loaded candidate item.
function T.ResolveItemRanges()
    local n = 0
    for _, list in ipairs({ T.HarmItems, T.FriendItems }) do
        for _, e in ipairs(list) do
            local id = e[2]
            if T.itemState[id] == "loaded" and not T.ItemYardsFromSpell[id] and not T.ItemMinRange[id] then
                local minR, maxR = T.ItemSpellRange(id)
                if maxR then
                    learnItemRange(id, minR, maxR)
                    n = n + 1
                end
            end
        end
    end
    local disc = T.db and T.db.discover and T.db.discover.items
    for _, it in ipairs(disc or {}) do
        learnItemRange(it.id, it.minR, it.maxR)
    end
    return n
end

-- Candidate items for a kind of unit ("harm" | "friend"): the LibRangeCheck
-- table plus discovered items that answered against that kind.
function T.ItemList(kind)
    local base = kind == "harm" and T.HarmItems or T.FriendItems
    local disc = T.db and T.db.discover and T.db.discover.items
    if not disc then
        return base
    end
    local list = {}
    for _, e in ipairs(base) do
        list[#list + 1] = e
    end
    for _, d in ipairs(disc) do
        if d[kind] == "ok" and d.minR == 0 and d.maxR > 0 then
            list[#list + 1] = { d.maxR, d.id, "D", "" }
        end
    end
    return list
end

-- The yards an item really checks, or nil if it should not be used:
-- spell data first, then a hand-verified value, then the table value, but
-- only if the tables agree on a single range for it.
local function itemYards(id, tableYards)
    if T.ItemMinRange[id] then
        return nil -- min-range items are ambiguous when "out"
    end
    local yd = T.ItemYardsFromSpell[id] or (T.VerifiedItemYards and T.VerifiedItemYards[id])
    if yd then
        return yd
    end
    local only = next(tableYards)
    if only and next(tableYards, only) == nil then
        return only
    end
    return nil
end

-- Returns sorted list of yards and map yards -> { entry, ... } where each
-- entry is { yards, itemID, sources, name }. Every item appears once, at its
-- real range; unknown/ambiguous/bad items and items missing from the client
-- are dropped.
function T.ItemsByYards(list)
    local tableYards, first = {}, {}
    for _, e in ipairs(list) do
        local id = e[2]
        tableYards[id] = tableYards[id] or {}
        tableYards[id][e[1]] = true
        first[id] = first[id] or e
    end
    local byYd, yards, seen = {}, {}, {}
    for _, e in ipairs(list) do
        local id = e[2]
        if not seen[id] and T.itemState[id] ~= "noexist" then
            seen[id] = true
            local yd = itemYards(id, tableYards[id])
            if yd and not (T.BadItems and T.BadItems[yd .. ":" .. id]) then
                if not byYd[yd] then
                    byYd[yd] = {}
                    yards[#yards + 1] = yd
                end
                local src = first[id]
                table.insert(byYd[yd], { yd, id, src[3], src[4] })
            end
        end
    end
    table.sort(yards)
    return yards, byYd
end

---------------------------------------------------------------------------
-- Range math. results: list of { yards, inRange(bool) }.
-- Returns minYd, maxYd, inconsistent:
--   maxYd = smallest threshold reporting "in range" (nil if none)
--   minYd = largest threshold below maxYd reporting "out of range" (nil if none)
--   inconsistent = true if some threshold above maxYd said "out of range"
---------------------------------------------------------------------------
function T.ComputeRange(results)
    local maxYd
    for _, r in ipairs(results) do
        if r[2] == true and (not maxYd or r[1] < maxYd) then
            maxYd = r[1]
        end
    end
    local minYd, inconsistent = nil, false
    for _, r in ipairs(results) do
        if r[2] == false then
            if not maxYd or r[1] < maxYd then
                if not minYd or r[1] > minYd then
                    minYd = r[1]
                end
            else
                inconsistent = true
            end
        end
    end
    return minYd, maxYd, inconsistent
end

-- "15-20", "100+", "<2", or "?".
function T.FormatRange(minYd, maxYd)
    if minYd and maxYd then
        return string.format("%g-%g", minYd, maxYd)
    elseif minYd then
        return string.format("%g+", minYd)
    elseif maxYd then
        return string.format("<%g", maxYd)
    end
    return "?"
end
