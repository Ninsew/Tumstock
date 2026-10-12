-- Tumstock settings: defaults, stored per character in TumstockCharDB.settings.
-- T.cfg is the live settings table; change it, then call T.ApplySettings().
local _, T = ...

T.Defaults = {
    mode = "bar",           -- "text" | "bar" | "both"
    locked = false,
    mouseover = true,       -- show mouseover when there is no target
    focus = true,           -- show focus when there is no target/mouseover
    hideNoUnit = false,     -- hide the displays when there is nothing to measure
    hideInCombat = false,   -- hide all displays (nameplates too) while in combat
    colorStyle = "smooth",  -- "smooth" | "bands" | "off"
    unitAlpha = { target = 1, mouseover = 0.6, focus = 0.8 },
    text = {
        scale = 1, alpha = 1, bgAlpha = 0.4, showUnit = true,
    },
    bar = {
        vertical = true,    -- false = horizontal
        reversed = false,   -- false: near end at the bottom (vertical) / left (horizontal)
        maxYd = 50,
        length = 260, thickness = 14,
        scale = 1, alpha = 1, bgAlpha = 0.5,
        ticks = true, labels = true, showText = true,
        uncertainty = true, -- highlight the bracket the target is somewhere in
    },
    plates = {
        enemy = true, friendly = true, -- friendly plates need the game's friendly nameplates on
        size = 11, offsetX = 0, offsetY = 0,
    },
    minimap = { angle = 225, hidden = false },
}

-- Fills in missing keys from defaults (recursively), keeping stored values.
local function merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do
        c[k] = type(v) == "table" and copy(v) or v
    end
    return c
end

T.WhenDBReady(function(db)
    db.settings = db.settings or {}
    -- 0.1/0.2 kept the text box under db.readout.
    local old = db.readout
    if old then
        db.settings.text = db.settings.text or {}
        db.settings.text.point = db.settings.text.point or old.point
        if db.settings.locked == nil then
            db.settings.locked = old.locked
        end
        db.readout = nil
    end
    -- 0.3/0.4 had an on/off "colors" switch.
    if db.settings.colors ~= nil then
        if db.settings.colors == false then
            db.settings.colorStyle = "off"
        end
        db.settings.colors = nil
    end
    merge(db.settings, T.Defaults)
    T.cfg = db.settings
end)

-- Restores one section ("text", "bar", or nil for everything) to defaults.
function T.ResetSettings(section)
    if section then
        T.cfg[section] = copy(T.Defaults[section])
    else
        for k in pairs(T.cfg) do
            T.cfg[k] = nil
        end
        merge(T.cfg, T.Defaults)
    end
    T.ApplySettings()
end
