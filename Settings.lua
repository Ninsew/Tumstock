-- Tumstock settings window (minimap button, /tum or /tum config).
-- Every control writes T.cfg and calls T.ApplySettings() straight away.
local _, T = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GOLD = { 1, 0.82, 0 }
local COL1, COL2 = 16, 316 -- column x offsets
local window
local refreshers = {}
local refreshing = false

local function changed()
    if not refreshing then
        T.ApplySettings()
    end
end

local function refreshAll()
    refreshing = true
    for _, fn in ipairs(refreshers) do
        fn()
    end
    refreshing = false
end

---------------------------------------------------------------------------
-- Controls. Each takes (parent, x, y, ...) and returns the next free y.
---------------------------------------------------------------------------
local function header(p, x, y, text)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    local line = p:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.4)
    line:SetSize(270, 1)
    line:SetPoint("TOPLEFT", x, y - 16)
    return y - 24
end

local function toggle(p, x, y, label, get, set)
    local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x - 4, y + 2)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        changed()
        refreshAll()
    end)
    table.insert(refreshers, function()
        cb:SetChecked(get() and true or false)
    end)
    return y - 24
end

-- A labelled button that steps through options; textOf(value) names one.
local function cycle(p, x, y, label, values, textOf, get, set)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y - 4)
    fs:SetText(label)
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(140, 22)
    b:SetPoint("TOPLEFT", x + 130, y)
    b:SetScript("OnClick", function()
        local cur, nextIndex = get(), 1
        for i, v in ipairs(values) do
            if v == cur then
                nextIndex = i % #values + 1
            end
        end
        set(values[nextIndex])
        changed()
        refreshAll()
    end)
    table.insert(refreshers, function()
        b:SetText(textOf(get()))
    end)
    return y - 28
end

local function slider(p, x, y, label, min, max, step, fmt, get, set)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(label)
    local value = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("TOPRIGHT", p, "TOPLEFT", x + 270, y)
    local s = CreateFrame("Slider", nil, p)
    s:SetPoint("TOPLEFT", x, y - 16)
    s:SetSize(270, 16)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then
        s:SetObeyStepOnDrag(true)
    end
    s:EnableMouseWheel(true)
    s:SetThumbTexture(WHITE)
    local thumb = s:GetThumbTexture()
    thumb:SetSize(8, 16)
    thumb:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(WHITE)
    track:SetVertexColor(0.25, 0.27, 0.3, 1)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    local function show(v)
        value:SetText(string.format(fmt, v))
    end
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        show(v)
        if not refreshing then
            set(v)
            changed()
        end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * step)
    end)
    table.insert(refreshers, function()
        s:SetValue(get())
        show(get())
    end)
    return y - 40
end

local function button(p, x, y, w, text, onClick)
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", function()
        onClick()
        refreshAll()
    end)
    return y - 28
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local MODES = { "text", "bar", "both" }
local MODE_TEXT = { text = "Text box", bar = "Bar", both = "Both" }
local COLOR_STYLES = { "smooth", "bands", "off" }
local COLOR_TEXT = { smooth = "Smooth blend", bands = "Hard bands", off = "Off (white)" }
local PCT = "%d%%"

local function pct(get, set)
    return function()
        return math.floor(get() * 100 + 0.5)
    end, function(v)
        set(v / 100)
    end
end

local function build()
    local f = CreateFrame("Frame", "TumstockSettings", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(616, 730)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        f:SetBackdropColor(0.05, 0.06, 0.08, 0.95)
        f:SetBackdropBorderColor(0.3, 0.6, 0.8, 1)
    end
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("Tumstock")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    table.insert(UISpecialFrames, "TumstockSettings")

    local cfg = T.cfg

    -- General (left column)
    local y = header(f, COL1, -44, "General")
    y = cycle(f, COL1, y, "Display", MODES, function(v) return MODE_TEXT[v] end,
        function() return cfg.mode end, function(v) cfg.mode = v end)
    y = toggle(f, COL1, y, "Lock displays", function() return cfg.locked end, function(v) cfg.locked = v end)
    y = toggle(f, COL1, y, "Mouseover when no target", function() return cfg.mouseover end, function(v) cfg.mouseover = v end)
    y = toggle(f, COL1, y, "Focus when no target", function() return cfg.focus end, function(v) cfg.focus = v end)
    y = toggle(f, COL1, y, "Hide with no target/mouseover (locked)", function() return cfg.hideNoUnit end,
        function(v) cfg.hideNoUnit = v end)
    y = toggle(f, COL1, y, "Hide in combat (locked)", function() return cfg.hideInCombat end,
        function(v) cfg.hideInCombat = v end)
    y = cycle(f, COL1, y, "Colours", COLOR_STYLES, function(v) return COLOR_TEXT[v] end,
        function() return cfg.colorStyle end, function(v) cfg.colorStyle = v end)
    y = toggle(f, COL1, y, "Minimap button", function() return not cfg.minimap.hidden end,
        function(v) cfg.minimap.hidden = not v end)

    -- Text box (left column)
    y = header(f, COL1, y - 10, "Text box")
    y = slider(f, COL1, y, "Size", 0.5, 3, 0.05, "%.2f", function() return cfg.text.scale end, function(v) cfg.text.scale = v end)
    local g, s = pct(function() return cfg.text.alpha end, function(v) cfg.text.alpha = v end)
    y = slider(f, COL1, y, "Opacity", 10, 100, 5, PCT, g, s)
    g, s = pct(function() return cfg.text.bgAlpha end, function(v) cfg.text.bgAlpha = v end)
    y = slider(f, COL1, y, "Background opacity", 0, 100, 5, PCT, g, s)
    y = toggle(f, COL1, y, "Show unit letter (T / M / F)", function() return cfg.text.showUnit end,
        function(v) cfg.text.showUnit = v end)
    y = button(f, COL1, y - 4, 130, "Reset text box", function() T.ResetSettings("text") end)

    -- Nameplates (left column)
    y = header(f, COL1, y - 10, "Nameplates")
    y = toggle(f, COL1, y, "Range above enemy nameplates", function() return cfg.plates.enemy end,
        function(v) cfg.plates.enemy = v end)
    y = toggle(f, COL1, y, "Range above friendly nameplates", function() return cfg.plates.friendly end,
        function(v) cfg.plates.friendly = v end)
    y = slider(f, COL1, y, "Text size", 8, 24, 1, "%d", function() return cfg.plates.size end, function(v) cfg.plates.size = v end)
    y = slider(f, COL1, y, "Height above plate", -30, 40, 1, "%d px", function() return cfg.plates.offsetY end,
        function(v) cfg.plates.offsetY = v end)

    -- Bar (right column)
    y = header(f, COL2, -44, "Bar (0 - max yards)")
    y = cycle(f, COL2, y, "Orientation", { true, false }, function(v) return v and "Vertical" or "Horizontal" end,
        function() return cfg.bar.vertical end, function(v) cfg.bar.vertical = v end)
    y = cycle(f, COL2, y, "Near end", { false, true }, function(v)
        if cfg.bar.vertical then
            return v and "Top" or "Bottom"
        end
        return v and "Right" or "Left"
    end, function() return cfg.bar.reversed end, function(v) cfg.bar.reversed = v end)
    y = slider(f, COL2, y, "Max yards", 20, 100, 5, "%d yd", function() return cfg.bar.maxYd end, function(v) cfg.bar.maxYd = v end)
    y = slider(f, COL2, y, "Length", 80, 600, 10, "%d px", function() return cfg.bar.length end, function(v) cfg.bar.length = v end)
    y = slider(f, COL2, y, "Thickness", 6, 60, 1, "%d px", function() return cfg.bar.thickness end, function(v) cfg.bar.thickness = v end)
    y = slider(f, COL2, y, "Size", 0.5, 3, 0.05, "%.2f", function() return cfg.bar.scale end, function(v) cfg.bar.scale = v end)
    g, s = pct(function() return cfg.bar.alpha end, function(v) cfg.bar.alpha = v end)
    y = slider(f, COL2, y, "Opacity", 10, 100, 5, PCT, g, s)
    g, s = pct(function() return cfg.bar.bgAlpha end, function(v) cfg.bar.bgAlpha = v end)
    y = slider(f, COL2, y, "Background opacity", 0, 100, 5, PCT, g, s)
    y = toggle(f, COL2, y, "White dividing lines", function() return cfg.bar.ticks end, function(v) cfg.bar.ticks = v end)
    y = toggle(f, COL2, y, "Yard labels", function() return cfg.bar.labels end, function(v) cfg.bar.labels = v end)
    y = toggle(f, COL2, y, "Range text by the arrow", function() return cfg.bar.showText end, function(v) cfg.bar.showText = v end)
    y = toggle(f, COL2, y, "Highlight the uncertain range", function() return cfg.bar.uncertainty end,
        function(v) cfg.bar.uncertainty = v end)
    y = button(f, COL2, y - 4, 130, "Reset bar", function() T.ResetSettings("bar") end)

    -- Opacity by unit (right column): multiplies each display's own opacity.
    y = header(f, COL2, y - 10, "Opacity by unit (text box and bar)")
    for _, u in ipairs({ { "target", "Target" }, { "mouseover", "Mouseover" }, { "focus", "Focus" } }) do
        g, s = pct(function() return cfg.unitAlpha[u[1]] end, function(v) cfg.unitAlpha[u[1]] = v end)
        y = slider(f, COL2, y, u[2], 10, 100, 5, PCT, g, s)
    end

    -- Bottom row
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(130, 22)
    b:SetPoint("BOTTOMLEFT", COL1, 14)
    b:SetText("Reset positions")
    b:SetScript("OnClick", function()
        cfg.text.point, cfg.bar.point = nil, nil
        T.ApplySettings()
    end)
    local all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    all:SetSize(130, 22)
    all:SetPoint("LEFT", b, "RIGHT", 8, 0)
    all:SetText("Reset everything")
    all:SetScript("OnClick", function()
        T.ResetSettings()
        cfg = T.cfg
        refreshAll()
    end)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", -16, 18)
    hint:SetText("Right-click the minimap icon to lock/unlock.")
    return f
end

function T.ToggleSettings()
    if not T.cfg then
        return
    end
    if not window then
        window = build()
    end
    if window:IsShown() then
        window:Hide()
    else
        refreshAll()
        window:Show()
    end
end

T.Command("config", "open the settings window", function()
    T.ToggleSettings()
end)
