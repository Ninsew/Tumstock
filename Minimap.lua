-- Tumstock minimap button: drag it around the minimap edge; left-click opens
-- the settings, right-click locks/unlocks the displays. Hand-built (no
-- LibDBIcon), same textures as Blizzard's own minimap buttons.
local _, T = ...

local RADIUS = 80
local button
local dragging = false

local function positionAt(deg)
    local a = math.rad(deg)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * RADIUS, math.sin(a) * RADIUS)
end

local function build()
    local b = CreateFrame("Button", "TumstockMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            T.cfg.locked = not T.cfg.locked
            T.ApplySettings()
            T.Print(T.cfg.locked and "displays locked." or "displays unlocked - drag them to move.")
        else
            T.ToggleSettings()
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Tumstock")
        GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
        GameTooltip:AddLine("Right-click: lock/unlock displays", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStart", function()
        dragging = true
    end)
    b:SetScript("OnDragStop", function()
        dragging = false
    end)
    b:SetScript("OnUpdate", function()
        if not dragging then
            return
        end
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        if not (mx and px and scale and scale ~= 0) then
            return
        end
        local deg = math.deg(math.atan2(py / scale - my, px / scale - mx))
        T.cfg.minimap.angle = deg
        positionAt(deg)
    end)
    return b
end

function T.ApplyMinimapSettings()
    if not button then
        return
    end
    positionAt(T.cfg.minimap.angle)
    button:SetShown(not T.cfg.minimap.hidden)
end

T.On("PLAYER_LOGIN", function()
    if not Minimap then
        return
    end
    button = build()
    T.ApplyMinimapSettings()
end)

T.Command("minimap", "show/hide the minimap button", function()
    T.cfg.minimap.hidden = not T.cfg.minimap.hidden
    T.ApplyMinimapSettings()
end)
