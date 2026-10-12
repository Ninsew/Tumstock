-- Tumstock nameplate readouts: a small "15-20" above enemy and/or friendly
-- nameplates. Same engine as the target displays. A child frame is anchored
-- above the plate (as Forever Range does); plate positions are never read.
-- Friendly plates only exist when the game's friendly nameplates are on.
local _, T = ...

local INTERVAL = 0.3 -- slower than the main display: there can be many plates

local plateUnits = {} -- unit token -> true while its plate exists
local labels = {}     -- unit token -> label frame
local spare = {}

local function plateKind(unit)
    return T.IsHostile(unit) and "enemy" or "friendly"
end

local function wantedKind(kind)
    local c = T.cfg.plates
    return (kind == "enemy" and c.enemy) or (kind == "friendly" and c.friendly)
end

local function style(label)
    local c = T.cfg.plates
    local font = label.value:GetFont()
    if font then
        label.value:SetFont(font, c.size, "OUTLINE")
    end
    label:ClearAllPoints()
    label:SetPoint("BOTTOM", label:GetParent(), "TOP", c.offsetX, c.offsetY)
end

local function attach(unit)
    if labels[unit] then
        return
    end
    if T.UnitIsMe(unit) then
        return -- personal resource display
    end
    local s, plate = T.SafeCall(C_NamePlate.GetNamePlateForUnit, unit)
    if s ~= "ok" then
        return
    end
    local label = table.remove(spare)
    if label then
        label:SetParent(plate)
    else
        label = CreateFrame("Frame", nil, plate)
        label:SetSize(1, 1)
        label:EnableMouse(false)
        label.value = label:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label.value:SetPoint("BOTTOM")
    end
    label:SetFrameLevel((plate:GetFrameLevel() or 0) + 20)
    style(label)
    label:Hide()
    labels[unit] = label
end

local function detach(unit)
    local label = labels[unit]
    if not label then
        return
    end
    labels[unit] = nil
    label:Hide()
    label:ClearAllPoints()
    label:SetParent(UIParent)
    spare[#spare + 1] = label
end

local function refresh(unit, label)
    if not T.UnitExists(unit) or not wantedKind(plateKind(unit)) then
        label:Hide()
        return
    end
    local lo, hi, known, exact = T.Measure(unit)
    if not known then
        label:Hide()
        return
    end
    if exact then
        label.value:SetText(string.format("%.0f", lo))
    else
        label.value:SetText(T.FormatRange(lo, hi))
    end
    label.value:SetTextColor(T.RangeColor(lo, hi))
    label:Show()
end

local function anyWanted()
    return T.cfg and (T.cfg.plates.enemy or T.cfg.plates.friendly)
end

-- Attaches/detaches labels to match the settings and the visible plates.
local function sync()
    for unit in pairs(labels) do
        if not plateUnits[unit] or not anyWanted() then
            detach(unit)
        end
    end
    if anyWanted() then
        for unit in pairs(plateUnits) do
            attach(unit)
        end
    end
end

function T.ApplyPlateSettings()
    sync()
    for _, label in pairs(labels) do
        style(label)
    end
end

T.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
    plateUnits[unit] = true
    if anyWanted() then
        attach(unit)
    end
end)

T.On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
    plateUnits[unit] = nil
    detach(unit)
end)

T.WhenDBReady(function()
    local driver = CreateFrame("Frame")
    local elapsed = 0
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < INTERVAL or not next(labels) then
            return
        end
        elapsed = 0
        if T.cfg.hideInCombat and T.InCombat() then
            for _, label in pairs(labels) do
                label:Hide()
            end
            return
        end
        for unit, label in pairs(labels) do
            local ok, err = pcall(refresh, unit, label)
            if not ok then
                T.Error("nameplates", err)
                label:Hide()
            end
        end
    end)
end)
