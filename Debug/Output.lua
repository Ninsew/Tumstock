-- Tumstock output window: a scrollable, selectable text box for copy/paste.
local _, T = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local frame

local function build()
    local f = CreateFrame("Frame", "TumstockOutputFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(620, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        f:SetBackdropColor(0.05, 0.06, 0.08, 0.95)
        f:SetBackdropBorderColor(0.3, 0.6, 0.8, 1)
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Tumstock output  (Ctrl+A, Ctrl+C to copy)")
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local selectBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    selectBtn:SetSize(90, 20)
    selectBtn:SetPoint("TOPRIGHT", -30, -5)
    selectBtn:SetText("Select all")

    local scroll = CreateFrame("ScrollFrame", "TumstockOutputScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -32)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(570)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    -- Keep the text read-only-ish: restore it if the user types.
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and f.text then
            self:SetText(f.text)
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(edit)
    f.edit = edit

    selectBtn:SetScript("OnClick", function()
        edit:SetFocus()
        edit:HighlightText()
    end)

    table.insert(UISpecialFrames, "TumstockOutputFrame")
    return f
end

-- Shows lines (a table of strings) in the window, all selected.
function T.ShowOutput(titleText, lines)
    if not frame then
        frame = build()
    end
    local text = table.concat(lines, "\n")
    frame.text = text
    frame.title:SetText(titleText .. "  (Ctrl+C to copy)")
    frame.edit:SetText(text)
    frame:Show()
    frame.edit:SetFocus()
    frame.edit:HighlightText()
end
