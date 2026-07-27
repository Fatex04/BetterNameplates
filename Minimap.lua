local _, addon = ...
local L = addon.L
local ADDON_ICON = "Interface\\AddOns\\BetterNameplates\\assets\\bnp_logo.tga"

local function Atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    elseif x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then
        return math.pi / 2
    elseif x == 0 and y < 0 then
        return -math.pi / 2
    end
    return 0
end

local function PlaceButton(button)
    if not button or not Minimap then
        return
    end

    -- If a minimap-button collector reparents BNP, it controls positioning.
    if button:GetParent() ~= Minimap then
        return
    end

    local angle = math.rad(tonumber(addon.db.minimapAngle) or 225)
    local width = Minimap:GetWidth() or 140
    local height = Minimap:GetHeight() or width
    local radius = (math.max(width, height) / 2) + 5

    button:ClearAllPoints()
    button:SetPoint(
        "CENTER",
        Minimap,
        "CENTER",
        math.cos(angle) * radius,
        math.sin(angle) * radius
    )
end

local function UpdateDrag(button)
    if not Minimap or not GetCursorPosition then
        return
    end

    local centerX, centerY = Minimap:GetCenter()
    if not centerX or not centerY then
        return
    end

    local scale = Minimap:GetEffectiveScale()
    if not scale or scale <= 0 then
        scale = 1
    end

    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    local angle = math.deg(Atan2(cursorY - centerY, cursorX - centerX))
    if angle < 0 then
        angle = angle + 360
    end

    addon.db.minimapAngle = angle
    PlaceButton(button)
end

function addon:UpdateMinimapButton()
    local button = self.minimapButton
    if not button or not self.db then
        return
    end

    if self.db.showMinimapButton == false then
        button:Hide()
    else
        button:Show()
        PlaceButton(button)
    end
end

function addon:CreateMinimapButton()
    if self.minimapButton or not Minimap then
        return
    end

    local button = CreateFrame("Button", "BNPMinimapButton", Minimap)
    button:SetParent(Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(23, 23)
    button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.icon:SetTexture(ADDON_ICON)
    button.icon:SetTexCoord(0, 1, 0, 1)

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetSize(54, 54)
    button.border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetPoint("TOPLEFT", button.icon, "TOPLEFT")
    button.highlight:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT")
    button.highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    button.highlight:SetBlendMode("ADD")

    button.label = button:CreateFontString(nil, "OVERLAY")
    button.label:SetFont(STANDARD_TEXT_FONT, 7, "OUTLINE")
    button.label:SetPoint("BOTTOM", button.icon, "BOTTOM", 0, 1)
    button.label:SetText("BNP")
    button.label:SetTextColor(0.65, 0.9, 1)

    button:SetScript("OnClick", function(self)
        if self.suppressClick then
            return
        end
        addon:ToggleOptions()
    end)
    button:SetScript("OnDragStart", function(self)
        self.suppressClick = true
        self:SetScript("OnUpdate", UpdateDrag)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        UpdateDrag(self)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if self then
                    self.suppressClick = nil
                end
            end)
        else
            self.suppressClick = nil
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cff40c7ebBNP|r - BetterNameplates")
        GameTooltip:AddLine(L.MINIMAP_TOOLTIP_LEFT, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TOOLTIP_DRAG, 0.75, 0.85, 0.95)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    self.minimapButton = button
    self:UpdateMinimapButton()
end
