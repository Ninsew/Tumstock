-- Tumstock displays: a text box ("15-20") and a distance bar with an arrow.
-- Which one shows, and how, comes from T.cfg (Config.lua, Settings.lua).
-- Unit priority: target, then mouseover, then focus (each optional).
local _, T = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local INTERVAL = 0.15
local DEFAULT_Y = { text = -180, bar = -120 }

local textFrame, barFrame
local reading = {} -- latest: unit, letter, lo, hi, known, exact

---------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------
-- Colour style (T.cfg.colorStyle):
--   "bands"  - hard zones: green melee, white mid, orange far, red beyond
--   "smooth" - the same colours blended continuously along the distance
--   "off"    - white
local BANDS = { { 5, 0.3, 1, 0.3 }, { 30, 1, 1, 1 }, { 40, 1, 0.75, 0.2 }, { math.huge, 1, 0.3, 0.3 } }
-- Smooth gradient stops: yards, r, g, b.
local STOPS = {
    { 0, 0.3, 1, 0.3 }, { 5, 0.3, 1, 0.3 }, { 10, 0.85, 0.85, 0.85 }, { 28, 0.85, 0.85, 0.85 },
    { 35, 1, 0.85, 0.2 }, { 42, 1, 0.55, 0.15 }, { 48, 1, 0.3, 0.3 },
}

-- Colour for a distance in yards, by the current style.
function T.ColorAt(d)
    local style = T.cfg.colorStyle
    if style == "off" or not d then
        return 1, 1, 1
    end
    if style == "bands" then
        for _, b in ipairs(BANDS) do
            if d <= b[1] then
                return b[2], b[3], b[4]
            end
        end
    end
    if d <= STOPS[1][1] then
        return STOPS[1][2], STOPS[1][3], STOPS[1][4]
    end
    for i = 2, #STOPS do
        local a, b = STOPS[i - 1], STOPS[i]
        if d <= b[1] then
            local t = (d - a[1]) / (b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
        end
    end
    local last = STOPS[#STOPS]
    return last[2], last[3], last[4]
end

-- A single representative distance for a bracket: the middle of it.
function T.MidYards(lo, hi, exact)
    if exact then
        return lo
    end
    if lo and hi then
        return (lo + hi) / 2
    end
    if hi then
        return hi / 2
    end
    return lo -- "45+": the near edge of the open range
end

-- Bands colour by the far end of the bracket; smooth by its middle.
function T.RangeColor(lo, hi, exact)
    if T.cfg.colorStyle == "bands" then
        return T.ColorAt(exact and lo or hi or (lo and lo + 1) or 0)
    end
    return T.ColorAt(T.MidYards(lo, hi, exact))
end

-- Eases a displayed distance toward its target, for smooth colour changes.
local function ease(cur, target, dt)
    if not cur then
        return target
    end
    return cur + (target - cur) * math.min(1, dt * 6)
end

local function rangeText(r)
    if not r.unit then
        return "--"
    end
    if r.exact then
        return r.lo == 0 and "0" or string.format("%.1f", r.lo)
    end
    if not r.known then
        return "?"
    end
    return T.FormatRange(r.lo, r.hi)
end

local function pickUnit()
    if T.UnitExists("target") then
        return "target", "T"
    end
    if T.cfg.mouseover and T.UnitExists("mouseover") then
        return "mouseover", "M"
    end
    if T.cfg.focus and T.UnitExists("focus") then
        return "focus", "F"
    end
end

-- Dragging, saving the position into T.cfg[key].point, and a tinted
-- "mover" overlay shown while unlocked.
local function makeMovable(f, key, title)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not T.cfg.locked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        T.cfg[key].point = { point, relPoint, x, y }
    end)
    local mover = f:CreateTexture(nil, "OVERLAY")
    mover:SetPoint("TOPLEFT", -3, 3)
    mover:SetPoint("BOTTOMRIGHT", 3, -3)
    mover:SetTexture(WHITE)
    mover:SetVertexColor(0.2, 0.6, 1, 0.25)
    f.mover = mover
    local moverText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moverText:SetPoint("BOTTOM", f, "TOP", 0, 4)
    moverText:SetText(title)
    f.moverText = moverText
end

local function place(f, key)
    local p = T.cfg[key].point
    f:ClearAllPoints()
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, DEFAULT_Y[key])
    end
end

local function applyMover(f)
    local unlocked = not T.cfg.locked
    f:EnableMouse(unlocked)
    f.mover:SetShown(unlocked)
    f.moverText:SetShown(unlocked)
end

---------------------------------------------------------------------------
-- Text box
---------------------------------------------------------------------------
local function buildText()
    local f = CreateFrame("Frame", "TumstockText", UIParent)
    f:SetSize(90, 30)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(WHITE)
    f.bg = bg
    f.value = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("LEFT", 4, 0)
    makeMovable(f, "text", "Tumstock text")
    -- Smooth colour: the colour follows an eased distance, not the jumps.
    f:SetScript("OnUpdate", function(self, dt)
        if T.cfg.colorStyle ~= "smooth" or not self.colorTarget then
            return
        end
        self.colorYd = ease(self.colorYd, self.colorTarget, dt)
        self.value:SetTextColor(T.ColorAt(self.colorYd))
    end)
    return f
end

local function applyText()
    local c = T.cfg.text
    textFrame:SetScale(c.scale)
    textFrame:SetAlpha(c.alpha)
    textFrame.bg:SetVertexColor(0, 0, 0, c.bgAlpha)
    textFrame.label:SetShown(c.showUnit)
    textFrame.value:ClearAllPoints()
    textFrame.value:SetPoint("CENTER", c.showUnit and 4 or 0, 0)
    place(textFrame, "text")
    applyMover(textFrame)
end

local function refreshText(r)
    textFrame.label:SetText(r.letter or "")
    textFrame.value:SetText(rangeText(r))
    if r.unit and (r.known or r.exact) then
        textFrame.colorTarget = T.MidYards(r.lo, r.hi, r.exact)
        if T.cfg.colorStyle ~= "smooth" then
            textFrame.value:SetTextColor(T.RangeColor(r.lo, r.hi, r.exact))
        end
    else
        textFrame.colorTarget, textFrame.colorYd = nil, nil
        textFrame.value:SetTextColor(0.6, 0.6, 0.6)
    end
end

---------------------------------------------------------------------------
-- Bar: 0..maxYd along its length, near end at bottom/left unless reversed.
---------------------------------------------------------------------------
local function clamp01(x)
    return x < 0 and 0 or (x > 1 and 1 or x)
end

-- Pixel offset of d yards from the bar's near end.
local function offsetOf(d)
    local c = T.cfg.bar
    return clamp01(d / c.maxYd) * c.length
end

-- Places a texture so it covers the bar between pixel offsets a and b.
local function span(tex, a, b)
    local c, f = T.cfg.bar, barFrame
    if b - a < 1 then
        b = a + 1
    end
    tex:ClearAllPoints()
    if c.vertical and not c.reversed then
        tex:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, a)
        tex:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, b)
    elseif c.vertical then
        tex:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -a)
        tex:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, -b)
    elseif not c.reversed then
        tex:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", a, 0)
        tex:SetPoint("TOPRIGHT", f, "TOPLEFT", b, 0)
    else
        tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -a, 0)
        tex:SetPoint("TOPLEFT", f, "TOPRIGHT", -b, 0)
    end
end

-- Anchors a region beside the bar at pixel offset off. side "arrow" is
-- left (vertical) / above (horizontal); side "label" is the opposite side.
local function beside(region, off, side, gap)
    local c, f = T.cfg.bar, barFrame
    region:ClearAllPoints()
    if c.vertical then
        local y = c.reversed and -off or off
        local edge = c.reversed and "TOP" or "BOTTOM"
        if side == "arrow" then
            region:SetPoint("RIGHT", f, edge .. "LEFT", -gap, y)
        else
            region:SetPoint("LEFT", f, edge .. "RIGHT", gap, y)
        end
    else
        local x = c.reversed and -off or off
        local edge = c.reversed and "RIGHT" or "LEFT"
        if side == "arrow" then
            region:SetPoint("BOTTOM", f, "TOP" .. edge, x, gap)
        else
            region:SetPoint("TOP", f, "BOTTOM" .. edge, x, -gap)
        end
    end
end

local ZONES = { { 0, 5, 0.3, 1, 0.3 }, { 5, 30, 1, 1, 1 }, { 30, 40, 1, 0.75, 0.2 }, { 40, 1000, 1, 0.3, 0.3 } }

local function pooled(pool, i, create)
    local r = pool[i]
    if not r then
        r = create()
        pool[i] = r
    end
    r:Show()
    return r
end

local function buildBar()
    local f = CreateFrame("Frame", "TumstockBar", UIParent)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(WHITE)
    f.bg = bg
    f.zones, f.ticks, f.labels, f.grad = {}, {}, {}, {}
    for i = 1, #ZONES do
        local z = f:CreateTexture(nil, "BORDER")
        z:SetTexture(WHITE)
        f.zones[i] = z
    end
    local bracket = f:CreateTexture(nil, "ARTWORK")
    bracket:SetTexture(WHITE)
    f.bracket = bracket
    f.arrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.value = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.arrowPos = nil      -- animated arrow offset (pixels)
    f.arrowTarget = nil   -- where the arrow is heading
    makeMovable(f, "bar", "Tumstock bar")
    f:SetScript("OnUpdate", function(self, dt)
        if not self.arrowTarget then
            return
        end
        self.arrowPos = self.arrowPos or self.arrowTarget
        self.arrowPos = self.arrowPos + (self.arrowTarget - self.arrowPos) * math.min(1, dt * 12)
        beside(self.arrow, self.arrowPos, "arrow", 2)
        if T.cfg.colorStyle == "smooth" then
            -- Colour follows the gliding arrow, so it blends instead of jumping.
            local c = T.cfg.bar
            local r, g, b = T.ColorAt(self.arrowPos / c.length * c.maxYd)
            self.arrow:SetTextColor(r, g, b)
            self.value:SetTextColor(r, g, b)
        end
    end)
    return f
end

local function applyBar()
    local c, f = T.cfg.bar, barFrame
    if c.vertical then
        f:SetSize(c.thickness, c.length)
    else
        f:SetSize(c.length, c.thickness)
    end
    f:SetScale(c.scale)
    f:SetAlpha(c.alpha)
    f.bg:SetVertexColor(0, 0, 0, c.bgAlpha)

    -- Background colour: hard zones, or a 1-yard-step gradient when smooth.
    local style = T.cfg.colorStyle
    for i, z in ipairs(ZONES) do
        local tex = f.zones[i]
        if style == "bands" and z[1] < c.maxYd then
            span(tex, offsetOf(z[1]), offsetOf(z[2]))
            tex:SetVertexColor(z[3], z[4], z[5], 0.25)
            tex:Show()
        else
            tex:Hide()
        end
    end
    for _, g in ipairs(f.grad) do
        g:Hide()
    end
    if style == "smooth" then
        for yd = 0, c.maxYd - 1 do
            local g = pooled(f.grad, yd + 1, function()
                local tex = f:CreateTexture(nil, "BORDER")
                tex:SetTexture(WHITE)
                return tex
            end)
            span(g, offsetOf(yd), offsetOf(yd + 1))
            local r, gg, b = T.ColorAt(yd + 0.5)
            g:SetVertexColor(r, gg, b, 0.25)
        end
    end

    for _, t in ipairs(f.ticks) do
        t:Hide()
    end
    if c.ticks then
        local i = 0
        for _, yd in ipairs(T.Thresholds("harm")) do
            if yd > 0 and yd < c.maxYd then
                i = i + 1
                local t = pooled(f.ticks, i, function()
                    local tex = f:CreateTexture(nil, "ARTWORK", nil, 1)
                    tex:SetTexture(WHITE)
                    return tex
                end)
                local off = offsetOf(yd)
                span(t, off, off + 1)
                t:SetVertexColor(1, 1, 1, 0.45)
            end
        end
    end

    for _, l in ipairs(f.labels) do
        l:Hide()
    end
    if c.labels then
        local step = c.maxYd <= 60 and 10 or 20
        local i = 0
        for yd = 0, c.maxYd, step do
            i = i + 1
            local l = pooled(f.labels, i, function()
                return f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            end)
            l:SetText(tostring(yd))
            beside(l, offsetOf(yd), "label", 3)
        end
    end

    local font, _, flags = f.arrow:GetFont()
    local size = math.max(14, math.floor(c.thickness * 1.4))
    if font then
        f.arrow:SetFont(font, size, flags)
    end
    f.arrow:SetText(c.vertical and ">" or "v")
    f.value:ClearAllPoints()
    if c.vertical then
        f.value:SetPoint("RIGHT", f.arrow, "LEFT", -2, 0)
    else
        f.value:SetPoint("BOTTOM", f.arrow, "TOP", 0, 0)
    end
    f.arrowPos = nil
    place(f, "bar")
    applyMover(f)
end

local function refreshBar(r)
    local f, c = barFrame, T.cfg.bar
    local d = r.unit and (r.known or r.exact) and T.MidYards(r.lo, r.hi, r.exact)
    if not d then
        f.arrowTarget = nil
        f.arrow:Hide()
        f.bracket:Hide()
        f.value:SetShown(c.showText and r.unit ~= nil)
        f.value:SetText(rangeText(r))
        f.value:SetTextColor(0.6, 0.6, 0.6)
        return
    end
    local cr, cg, cb = T.RangeColor(r.lo, r.hi, r.exact)
    local smooth = T.cfg.colorStyle == "smooth"
    f.arrowTarget = offsetOf(d)
    if not f.arrowPos then
        f.arrowPos = f.arrowTarget
        beside(f.arrow, f.arrowPos, "arrow", 2)
    end
    if not smooth then
        f.arrow:SetTextColor(cr, cg, cb)
        f.value:SetTextColor(cr, cg, cb)
    end
    f.arrow:Show()
    if c.uncertainty and not r.exact then
        span(f.bracket, offsetOf(r.lo or 0), offsetOf(r.hi or c.maxYd))
        -- Fainter when smooth, so the band does not draw hard edges.
        f.bracket:SetVertexColor(cr, cg, cb, smooth and 0.22 or 0.45)
        f.bracket:Show()
    else
        f.bracket:Hide()
    end
    f.value:SetShown(c.showText)
    f.value:SetText(rangeText(r))
end

---------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------
local function wanted(kind)
    local m = T.cfg.mode
    return m == "both" or m == kind
end

-- True when the settings say the displays should be out of the way now.
-- While unlocked they always show, so they can be found and moved.
function T.DisplaysHidden(hasUnit)
    if not T.cfg.locked then
        return false
    end
    if T.cfg.hideInCombat and T.InCombat() then
        return true
    end
    return not hasUnit and T.cfg.hideNoUnit
end

-- How long the last good reading is kept when the unit briefly disappears
-- or gives no answer (e.g. the moment a mouseover is clicked into a target).
local HOLD = 0.5
local lastGood = 0

local function update()
    local unit, letter = pickUnit()
    local now = GetTime()
    if not unit and now - lastGood < HOLD then
        return -- keep showing the previous reading
    end
    local hidden = T.DisplaysHidden(unit ~= nil)
    textFrame:SetShown(not hidden and wanted("text"))
    barFrame:SetShown(not hidden and wanted("bar"))
    if hidden then
        return -- nothing shown, nothing measured
    end
    local lo, hi, known, exact
    if unit then
        lo, hi, known, exact = T.Measure(unit)
    end
    if known or exact then
        lastGood = now
    elseif unit and now - lastGood < HOLD then
        return -- no answer yet for this unit; keep the previous reading
    end
    local r = reading
    r.unit, r.letter = unit, letter
    r.lo, r.hi, r.known, r.exact = lo, hi, known or false, exact or false
    -- Opacity per unit type (target / mouseover / focus) on top of each display's own.
    local ua = unit and T.cfg.unitAlpha[unit] or 1
    textFrame:SetAlpha(T.cfg.text.alpha * ua)
    barFrame:SetAlpha(T.cfg.bar.alpha * ua)
    if textFrame:IsShown() then
        refreshText(r)
    end
    if barFrame:IsShown() then
        refreshBar(r)
    end
end

function T.ApplySettings()
    if not textFrame then
        return
    end
    -- Each part on its own, so one failing cannot leave the others unbuilt.
    local ok, err = pcall(applyText)
    if not ok then
        T.Error("text box", err)
    end
    ok, err = pcall(applyBar)
    if not ok then
        T.Error("bar", err)
    end
    textFrame:SetShown(wanted("text"))
    barFrame:SetShown(wanted("bar"))
    if T.ApplyMinimapSettings then
        ok, err = pcall(T.ApplyMinimapSettings)
        if not ok then
            T.Error("minimap", err)
        end
    end
    if T.ApplyPlateSettings then
        ok, err = pcall(T.ApplyPlateSettings)
        if not ok then
            T.Error("nameplates", err)
        end
    end
end

T.WhenDBReady(function()
    textFrame = buildText()
    barFrame = buildBar()
    T.ApplySettings()
    local driver = CreateFrame("Frame")
    local elapsed = 0
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < INTERVAL then
            return
        end
        elapsed = 0
        local ok, err = pcall(update)
        if not ok then
            T.Error("display", err)
        end
    end)
end)

-- Tick marks depend on what the engine can measure; redraw when it changes.
T.OnEngineChanged = function()
    if barFrame then
        local ok, err = pcall(applyBar)
        if not ok then
            T.Error("bar", err)
        end
    end
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
T.Command("lock", "lock the displays in place", function()
    T.cfg.locked = true
    T.ApplySettings()
    T.Print("displays locked.")
end)

T.Command("unlock", "unlock the displays (drag to move)", function()
    T.cfg.locked = false
    T.ApplySettings()
    T.Print("displays unlocked - drag them with the left mouse button.")
end)

T.Command("bar", "show the bar (mode Both) in its default spot, unlocked", function()
    if T.cfg.mode == "text" then
        T.cfg.mode = "both"
    end
    T.cfg.bar.point = nil
    T.cfg.locked = false
    T.ApplySettings()
    local w, h = barFrame:GetSize()
    local x, y = barFrame:GetCenter()
    local diag = string.format("bar: mode %s, shown %s, visible %s, size %dx%d, center %s,%s, scale %.2f, alpha %.2f, last error: %s",
        T.cfg.mode, tostring(barFrame:IsShown()), tostring(barFrame:IsVisible()), w or 0, h or 0,
        tostring(x and math.floor(x)), tostring(y and math.floor(y)), T.cfg.bar.scale, T.cfg.bar.alpha, tostring(T.lastError))
    T.db.barDiag = date("%H:%M:%S") .. " " .. diag
    T.Print("bar turned on and unlocked. Type /reload so the details are saved for checking.")
end)

T.Command("reset", "move the displays back to their default spots", function()
    T.cfg.text.point = nil
    T.cfg.bar.point = nil
    T.ApplySettings()
end)
