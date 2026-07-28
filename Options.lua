local _, addon = ...
local L = addon.L

local ADDON_ICON = "Interface\\AddOns\\BetterNameplates\\assets\\bnp_logo.tga"
local DISCORD_ICON = "Interface\\AddOns\\BetterNameplates\\assets\\discord_icon.tga"
local THREAT_TAB_ICON = "Interface\\Icons\\Ability_Druid_Cower"
local DISCORD_URL = "https://discord.gg/ZfYDHV6Qgs"
local DISCORD_DIALOG_KEY = "BETTERNAMEPLATES_DISCORD_LINK"
local RESET_DIALOG_KEY = "BETTERNAMEPLATES_RESET_CONFIRM"
local CHANGELOG_TEXT = [=[|cff9d8cffV1.1|r

|cffffd100Threat reliability and live updates|r
• Increased the threat refresh rate to 0.1 seconds.
• Prevented brief missing threat samples from flickering at low frame rates.
• Fixed dynamic growth with visible full-frame scaling from the stable 0-100 threat percentage.
• Dynamic maximum size can be freely set from 1.0 to 3.0.
• Added Tiny Threat's blue cat icon to the Threat settings tab.

|cffffd100Controls and previews|r
• Nameplate features can now be disabled while threat remains active.
• Added separate scaling, level, threat, minimap, and live-preview switches.
• Added live nameplate and animated threat previews.
• Added independent 0.5-2.0 level scaling with the original 1.0 size as default.
• Added independent 0.5-2.0 size controls for names and visible HP numbers.
• BNP name and HP sizes now directly synchronize with BetterBlizzPlates and refresh its cache.
• Long names reserve the measured HP-number width and end in ... without overlap.
• Fixed repeated updates bypassing name truncation because of retained anchors.
• All sliders show their original default with a precisely aligned gold marker.
• Both previews now mirror the configured nameplate size and proportions.
• The nameplate preview also mirrors name, level, and HP-number sizes.
• The settings window can be resized from the bottom-right corner and remembers its layout.
• Reset now requires confirmation.

|cffffd100Classic level display|r
• Enemy and neutral levels now use Blizzard's Classic difficulty colors.
• Gray, green, yellow, orange, and red thresholds now match the default UI.
• Removed the incorrect custom skull rule for enemies ten levels above the player.
• A skull appears only for attackable bosses or enemies with a Blizzard-hidden level.
• Friendly units never show a skull and use their available numeric/effective level.

|cff9d8cffV1.0 - Initial Release|r

|cffffd100Modern Nameplates extension|r
• Extends Blizzard's Modern nameplates in WoW Classic Era without replacing them.
• Uses Blizzard CVars for taint-safe nameplate scaling.

|cffffd100Nameplate size|r
• Added stable nameplate scaling from 0.5 to 2.0 in 0.1 steps.
• Added compact horizontal proportions at smaller scales.

|cffffd100Unit levels|r
• Added enemy, neutral, and friendly unit levels inside the health bar.
• Added left and right placement beside the unit name.
• Added [35], lvl. 35, and plain 35 formats.
• Added gray, green, yellow, and red difficulty colors.
• Added a larger skull indicator for enemies with an unknown level.

|cffffd100Threat percentage|r
• Added threat percentages to visible enemy nameplates.
• Added display on all enemies or only the highest-threat enemy.
• Added above/below placement with left, center, and right alignment.
• Added size, signed vertical offset, and background opacity controls.
• Added a text-only mode by setting background opacity to 0.
• Added optional dynamic growth based on threat percentage and a configurable maximum size.
• Added the option to show threat only while in combat and after threat has been generated.
• Added optional percentage text coloring from green through yellow and orange to red.

|cffffd100Interface and compatibility|r
• Added a movable tabbed BNP settings window.
• Added a draggable BNP minimap button.
• Added automatic localization for supported WoW client languages.
• Added Classic Era unit-token fallbacks for reliable world nameplate updates.
• Added safeguards against restricted-frame measurement and direct nameplate scaling taint.

|cffaaaaaaKnown Blizzard limitation: friendly nameplates cannot be modified by addons in protected PvE instances.|r]=]

local controls = {}
local refreshing = false
local previewState = {
    threatPercentage = 0,
    threatElapsed = 0,
}

local function SetLabel(control, text)
    if control.Text then
        control.Text:SetText(text)
    elseif control:GetName() and _G[control:GetName() .. "Text"] then
        _G[control:GetName() .. "Text"]:SetText(text)
    end
end

local function CreateSectionTitle(parent, text, x, y)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    title:SetText(text)
    return title
end

local function CreateCheckBox(parent, name, text, x, y, onClick)
    local check = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    SetLabel(check, text)
    check:SetScript("OnClick", function(self)
        if not refreshing then
            onClick(not not self:GetChecked())
        end
    end)
    return check
end

local function CreateSlider(
    parent,
    name,
    label,
    minimum,
    maximum,
    step,
    x,
    y,
    width,
    defaultValue,
    onValueChanged
)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetWidth(width)
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    _G[name .. "Low"]:SetText(tostring(minimum))
    _G[name .. "High"]:SetText(tostring(maximum))

    local defaultRounded = addon.RoundToStep(
        addon.Clamp(defaultValue, minimum, maximum),
        step
    )
    slider.defaultSlider = CreateFrame("Slider", nil, slider)
    slider.defaultSlider:SetAllPoints(slider)
    slider.defaultSlider:SetOrientation("HORIZONTAL")
    slider.defaultSlider:SetMinMaxValues(minimum, maximum)
    slider.defaultSlider:SetValueStep(step)
    slider.defaultSlider:SetValue(defaultRounded)
    slider.defaultSlider:EnableMouse(false)
    slider.defaultSlider:SetFrameLevel(slider:GetFrameLevel() + 5)

    local activeThumb = slider:GetThumbTexture()
    local thumbWidth = activeThumb and activeThumb:GetWidth() or 16
    local thumbHeight = activeThumb and activeThumb:GetHeight() or 16
    if not thumbWidth or thumbWidth <= 0 then
        thumbWidth = 16
    end
    if not thumbHeight or thumbHeight <= 0 then
        thumbHeight = 16
    end

    slider.defaultThumb = slider.defaultSlider:CreateTexture(nil, "ARTWORK")
    slider.defaultThumb:SetSize(thumbWidth, thumbHeight)
    slider.defaultThumb:SetColorTexture(1, 1, 1, 0)
    slider.defaultSlider:SetThumbTexture(slider.defaultThumb)

    slider.defaultMarker = slider:CreateTexture(nil, "OVERLAY")
    slider.defaultMarker:SetSize(2, 14)
    slider.defaultMarker:SetColorTexture(1, 0.82, 0, 0.95)
    slider.defaultMarker:SetPoint("CENTER", slider.defaultThumb, "CENTER", 0, 0)

    local defaultFormat = step < 1 and "%.1f" or "%.0f"
    slider.defaultText = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    slider.defaultText:SetPoint("TOP", slider, "BOTTOM", 0, -13)
    slider.defaultText:SetText(
        string.format(L.DEFAULT_VALUE, string.format(defaultFormat, defaultRounded))
    )

    slider:SetScript("OnValueChanged", function(self, value)
        local rounded = addon.RoundToStep(value, step)
        local formatString = step < 1 and "%.1f" or "%.0f"
        _G[name .. "Text"]:SetText(label .. ": " .. string.format(formatString, rounded))
        if not refreshing then
            onValueChanged(rounded)
        end
    end)

    return slider
end

local function CreatePreviewBox(parent, x, y, height)
    local preview = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    preview:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    preview:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -x, y)
    preview:SetHeight(height)
    preview:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    preview:SetBackdropColor(0.008, 0.015, 0.025, 0.96)
    preview:SetBackdropBorderColor(0.14, 0.34, 0.5, 1)
    return preview
end

local function EnsureDiscordDialog()
    if not StaticPopupDialogs or StaticPopupDialogs[DISCORD_DIALOG_KEY] then
        return
    end

    StaticPopupDialogs[DISCORD_DIALOG_KEY] = {
        text = L.DISCORD_COPY_TEXT,
        button1 = L.CLOSE,
        hasEditBox = true,
        editBoxWidth = 320,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(dialog)
            local editBox = dialog.editBox or dialog.EditBox
            if editBox then
                editBox:SetText(DISCORD_URL)
                editBox:HighlightText()
                editBox:SetFocus()
            end
        end,
        EditBoxOnEscapePressed = function(editBox)
            editBox:GetParent():Hide()
        end,
        EditBoxOnEnterPressed = function(editBox)
            editBox:HighlightText()
        end,
    }
end

local function ShowDiscordLink()
    EnsureDiscordDialog()
    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs[DISCORD_DIALOG_KEY] then
        StaticPopup_Show(DISCORD_DIALOG_KEY)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat(DISCORD_URL)
    end
end

local function EnsureResetDialog()
    if not StaticPopupDialogs or StaticPopupDialogs[RESET_DIALOG_KEY] then
        return
    end

    StaticPopupDialogs[RESET_DIALOG_KEY] = {
        text = L.RESET_CONFIRM,
        button1 = L.RESET,
        button2 = L.CANCEL_BUTTON,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function()
            addon:ResetDatabase()
            addon:Print(L.SETTINGS_RESET)
        end,
    }
end

function addon:RequestReset()
    EnsureResetDialog()
    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs[RESET_DIALOG_KEY] then
        StaticPopup_Show(RESET_DIALOG_KEY)
    end
end

local function FormatPreviewLevel()
    if not addon.db.enabled or not addon.db.showLevel then
        return nil
    end

    local level = "35"
    if addon.db.levelFormat == "BRACKETS" then
        level = "[" .. level .. "]"
    elseif addon.db.levelFormat == "PREFIX" then
        level = L.LEVEL_PREFIX .. " " .. level
    end
    if addon.db.levelColorByDifficulty then
        level = "|cffffd100" .. level .. "|r"
    end
    return level
end

local function GetPreviewNameplateDimensions()
    local scale = addon.db.enabled and addon.db.scaleEnabled
        and addon.db.nameplateScale
        or 1.0
    local horizontalScale = addon.GetNameplateHorizontalScale(scale)
    local width = math.floor((210 * scale * horizontalScale) + 0.5)
    local height = math.floor((24 * scale) + 0.5)
    return scale, width, height
end

local function UpdateNameplatePreview(force)
    local preview = controls.nameplatePreview
    if not preview or not addon.db then
        return
    end
    if not force
        and controls.nameplateLivePreview
        and not controls.nameplateLivePreview:GetChecked()
    then
        return
    end

    local scale, width, height = GetPreviewNameplateDimensions()
    preview.healthBar:SetSize(width, height)
    preview.healthBar:SetValue(72)
    preview.name:SetFont(
        STANDARD_TEXT_FONT,
        math.max(
            7,
            math.floor((11 * scale * addon.db.nameScale) + 0.5)
        ),
        "OUTLINE"
    )
    preview.healthNumbers:SetFont(
        STANDARD_TEXT_FONT,
        math.max(
            7,
            math.floor((9 * scale * addon.db.healthNumberScale) + 0.5)
        ),
        "OUTLINE"
    )
    preview.healthNumbers:SetText("1212")
    preview.healthNumbers:ClearAllPoints()
    preview.healthNumbers:SetPoint("RIGHT", preview.healthBar, "RIGHT", -5, 0)
    local healthInset = math.ceil(preview.healthNumbers:GetStringWidth()) + 13

    local level = FormatPreviewLevel()
    preview.name:ClearAllPoints()
    preview.level:ClearAllPoints()
    if level and addon.db.showEnemyLevel then
        preview.level:SetFont(
            STANDARD_TEXT_FONT,
            math.max(
                7,
                math.floor((11 * scale * addon.db.levelScale) + 0.5)
            ),
            "OUTLINE"
        )
        preview.level:SetWidth(0)
        preview.level:SetText(level)
        local levelWidth = math.ceil(preview.level:GetStringWidth())
        local nameWidth = math.max(
            0,
            width - levelWidth - healthInset - 13
        )
        local truncatedName = addon.TruncateToWidth(
            preview.name,
            L.PREVIEW_UNIT_NAME,
            nameWidth
        )

        if addon.db.levelSide == "LEFT" then
            preview.level:SetPoint("LEFT", preview.healthBar, "LEFT", 5, 0)
            preview.name:SetPoint("LEFT", preview.level, "RIGHT", 4, 0)
            preview.name:SetPoint("RIGHT", preview.healthNumbers, "LEFT", -4, 0)
        else
            preview.level:SetPoint("RIGHT", preview.healthNumbers, "LEFT", -4, 0)
            preview.name:SetPoint("LEFT", preview.healthBar, "LEFT", 5, 0)
            preview.name:SetPoint("RIGHT", preview.level, "LEFT", -4, 0)
        end
        preview.name:SetJustifyH("LEFT")
        preview.name:SetText(truncatedName)
        preview.level:Show()
    else
        preview.name:SetPoint("LEFT", preview.healthBar, "LEFT", 5, 0)
        preview.name:SetPoint("RIGHT", preview.healthNumbers, "LEFT", -4, 0)
        preview.name:SetJustifyH("CENTER")
        preview.name:SetText(
            addon.TruncateToWidth(
                preview.name,
                L.PREVIEW_UNIT_NAME,
                width - healthInset - 9
            )
        )
        preview.level:Hide()
    end
    preview.scaleText:SetText(string.format(L.PREVIEW_SCALE, scale))
end

local function UpdateThreatPreview()
    local preview = controls.threatPreview
    if not preview or not addon.db then
        return
    end

    local scale, width, height = GetPreviewNameplateDimensions()
    preview.healthBar:SetSize(width, height)
    preview.name:SetFont(
        STANDARD_TEXT_FONT,
        math.max(8, math.floor((11 * scale) + 0.5)),
        "OUTLINE"
    )
    preview.name:SetText(
        addon.TruncateToWidth(preview.name, L.PREVIEW_ENEMY_NAME, width - 10)
    )

    local percentage = previewState.threatPercentage
    local offset = math.floor(
        (addon.Clamp(addon.db.threatOffset, -40, 40) * scale) + 0.5
    )
    addon.SetThreatPosition(
        preview.threatFrame,
        preview.unitFrame,
        addon.db.threatPosition,
        offset
    )
    addon.ApplyThreatAppearance(preview.threatFrame, preview.threatText, percentage)
    preview.threatFrame:SetScale(addon.GetThreatVisualSize(percentage) * scale)
    preview.threatFrame:SetShown(addon.db.showThreat)
    preview.disabledText:SetShown(not addon.db.showThreat)
end

function addon:UpdateOptionsPreviews(force)
    UpdateNameplatePreview(force)
    UpdateThreatPreview()
end

local function CreateSideDropdown(parent, x, y)
    local dropdown = CreateFrame("Frame", "BetterNameplatesLevelSideDropdown", parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dropdown, 125)

    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 18, 2)
    label:SetText(L.LEVEL_POSITION)

    UIDropDownMenu_Initialize(dropdown, function()
        local function AddChoice(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.checked = addon.db and addon.db.levelSide == value
            info.func = function()
                addon.db.levelSide = value
                UIDropDownMenu_SetSelectedValue(dropdown, value)
                UIDropDownMenu_SetText(dropdown, text)
                addon:ApplyAll()
                addon:UpdateOptionsPreviews()
            end
            UIDropDownMenu_AddButton(info)
        end

        AddChoice(L.LEFT, "LEFT")
        AddChoice(L.RIGHT, "RIGHT")
    end)

    return dropdown
end

local function CreateFormatDropdown(parent, x, y)
    local dropdown = CreateFrame("Frame", "BetterNameplatesLevelFormatDropdown", parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dropdown, 125)

    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 18, 2)
    label:SetText(L.LEVEL_FORMAT)

    UIDropDownMenu_Initialize(dropdown, function()
        local function AddChoice(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.checked = addon.db and addon.db.levelFormat == value
            info.func = function()
                addon.db.levelFormat = value
                UIDropDownMenu_SetSelectedValue(dropdown, value)
                UIDropDownMenu_SetText(dropdown, text)
                addon:ApplyAll()
                addon:UpdateOptionsPreviews()
            end
            UIDropDownMenu_AddButton(info)
        end

        AddChoice("[35]", "BRACKETS")
        AddChoice(L.LEVEL_PREFIX .. " 35", "PREFIX")
        AddChoice(L.FORMAT_NONE, "PLAIN")
    end)

    return dropdown
end

local function CreateThreatModeDropdown(parent, x, y)
    local dropdown = CreateFrame("Frame", "BetterNameplatesThreatModeDropdown", parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dropdown, 245)

    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 18, 2)
    label:SetText(L.THREAT_DISPLAY_MODE)

    UIDropDownMenu_Initialize(dropdown, function()
        local function AddChoice(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.checked = addon.db and addon.db.threatDisplayMode == value
            info.func = function()
                addon.db.threatDisplayMode = value
                UIDropDownMenu_SetSelectedValue(dropdown, value)
                UIDropDownMenu_SetText(dropdown, text)
                addon:UpdateThreatDisplays()
                addon:UpdateOptionsPreviews()
            end
            UIDropDownMenu_AddButton(info)
        end

        AddChoice(L.THREAT_MODE_ALL, "ALL")
        AddChoice(L.THREAT_MODE_HIGHEST, "HIGHEST")
    end)

    return dropdown
end

local function CreateThreatPositionDropdown(parent, x, y)
    local dropdown = CreateFrame("Frame", "BetterNameplatesThreatPositionDropdown", parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dropdown, 190)

    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 18, 2)
    label:SetText(L.THREAT_POSITION)

    UIDropDownMenu_Initialize(dropdown, function()
        local function AddChoice(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.checked = addon.db and addon.db.threatPosition == value
            info.func = function()
                addon.db.threatPosition = value
                UIDropDownMenu_SetSelectedValue(dropdown, value)
                UIDropDownMenu_SetText(dropdown, text)
                addon:UpdateThreatDisplays()
                addon:UpdateOptionsPreviews()
            end
            UIDropDownMenu_AddButton(info)
        end

        AddChoice(L.THREAT_POSITION_TOPLEFT, "TOPLEFT")
        AddChoice(L.THREAT_POSITION_TOP, "TOP")
        AddChoice(L.THREAT_POSITION_TOPRIGHT, "TOPRIGHT")
        AddChoice(L.THREAT_POSITION_BOTTOMLEFT, "BOTTOMLEFT")
        AddChoice(L.THREAT_POSITION_BOTTOM, "BOTTOM")
        AddChoice(L.THREAT_POSITION_BOTTOMRIGHT, "BOTTOMRIGHT")
    end)

    return dropdown
end

local function NormalizeWindowTopLeft(window)
    local left = window:GetLeft()
    local top = window:GetTop()
    if not left or not top then
        return nil, nil
    end

    left = math.floor(left + 0.5)
    top = math.floor(top + 0.5)
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    return left, top
end

local function CreateWindow()
    local window = CreateFrame("Frame", "BetterNameplatesWindow", UIParent, "BackdropTemplate")
    local parentWidth = UIParent:GetWidth() or 1920
    local parentHeight = UIParent:GetHeight() or 1080
    local maximumWidth = math.max(720, parentWidth - 20)
    local maximumHeight = math.max(650, parentHeight - 20)
    local savedWidth = addon.Clamp(addon.db.optionsWindowWidth, 720, maximumWidth)
    local savedHeight = addon.Clamp(addon.db.optionsWindowHeight, 650, maximumHeight)

    window:SetSize(math.floor(savedWidth + 0.5), math.floor(savedHeight + 0.5))
    if addon.db.optionsWindowX and addon.db.optionsWindowY then
        window:SetPoint(
            "TOPLEFT",
            UIParent,
            "BOTTOMLEFT",
            addon.db.optionsWindowX,
            addon.db.optionsWindowY
        )
    else
        window:SetPoint("CENTER")
    end
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:SetResizable(true)
    local function UpdateResizeBounds()
        local currentParentWidth = UIParent:GetWidth() or 1920
        local currentParentHeight = UIParent:GetHeight() or 1080
        window.maxResizeWidth = math.max(720, currentParentWidth - 20)
        window.maxResizeHeight = math.max(650, currentParentHeight - 20)
        if window.SetResizeBounds then
            window:SetResizeBounds(
                720,
                650,
                window.maxResizeWidth,
                window.maxResizeHeight
            )
        elseif window.SetMinResize then
            window:SetMinResize(720, 650)
            if window.SetMaxResize then
                window:SetMaxResize(
                    window.maxResizeWidth,
                    window.maxResizeHeight
                )
            end
        end
    end
    window.UpdateResizeBounds = UpdateResizeBounds
    UpdateResizeBounds()
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = NormalizeWindowTopLeft(self)
        addon.db.optionsWindowX = left
        addon.db.optionsWindowY = top
    end)
    window:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    window:SetBackdropColor(0.015, 0.025, 0.04, 0.97)
    window:SetBackdropBorderColor(0.28, 0.62, 0.82, 1)
    window:Hide()

    table.insert(UISpecialFrames, "BetterNameplatesWindow")

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function()
        window:Hide()
    end)

    local resize = CreateFrame("Button", nil, window)
    resize:SetSize(18, 18)
    resize:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -5, 5)
    resize:SetFrameLevel(window:GetFrameLevel() + 10)
    resize.texture = resize:CreateTexture(nil, "ARTWORK")
    resize.texture:SetAllPoints()
    resize.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetScript("OnEnter", function(self)
        self.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    end)
    resize:SetScript("OnLeave", function(self)
        self.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    end)
    resize:SetScript("OnMouseDown", function()
        NormalizeWindowTopLeft(window)
        window:StartSizing("BOTTOMRIGHT")
    end)
    resize:SetScript("OnMouseUp", function()
        window:StopMovingOrSizing()
        local width = math.min(
            window.maxResizeWidth,
            math.floor(window:GetWidth() + 0.5)
        )
        local height = math.min(
            window.maxResizeHeight,
            math.floor(window:GetHeight() + 0.5)
        )
        window:SetSize(width, height)
        addon.db.optionsWindowWidth = width
        addon.db.optionsWindowHeight = height
        local left, top = NormalizeWindowTopLeft(window)
        addon.db.optionsWindowX = left
        addon.db.optionsWindowY = top
        addon:UpdateOptionsPreviews(true)
    end)
    window.resizeButton = resize

    local logo = window:CreateTexture(nil, "ARTWORK")
    logo:SetPoint("TOPLEFT", window, "TOPLEFT", 22, -15)
    logo:SetSize(46, 46)
    logo:SetTexture(ADDON_ICON)
    logo:SetTexCoord(0, 1, 0, 1)

    local title = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -5)
    title:SetText("BetterNameplates |cff9d8cffV1.1|r")

    local subtitle = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetWidth(590)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(L.OPTIONS_SUBTITLE)

    local divider = window:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.25, 0.65, 0.85, 0.55)
    divider:SetPoint("TOPLEFT", window, "TOPLEFT", 20, -69)
    divider:SetPoint("TOPRIGHT", window, "TOPRIGHT", -20, -69)
    divider:SetHeight(1)

    return window
end

function addon:ResetOptionsWindowLayout()
    self.db.optionsWindowWidth = self.defaults.optionsWindowWidth
    self.db.optionsWindowHeight = self.defaults.optionsWindowHeight
    self.db.optionsWindowX = nil
    self.db.optionsWindowY = nil

    if self.optionsWindow then
        self.optionsWindow:StopMovingOrSizing()
        self.optionsWindow:SetSize(
            self.defaults.optionsWindowWidth,
            self.defaults.optionsWindowHeight
        )
        self.optionsWindow:ClearAllPoints()
        self.optionsWindow:SetPoint("CENTER")
        self:UpdateOptionsPreviews(true)
    end
end

local function CreateTabSystem(window)
    local nav = CreateFrame("Frame", nil, window, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", window, "TOPLEFT", 17, -80)
    nav:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 17, 48)
    nav:SetWidth(158)
    nav:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    nav:SetBackdropColor(0.018, 0.04, 0.065, 0.94)
    nav:SetBackdropBorderColor(0.18, 0.42, 0.62, 1)

    local content = CreateFrame("Frame", nil, window, "BackdropTemplate")
    content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -17, 48)
    content:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    content:SetBackdropColor(0.012, 0.025, 0.04, 0.9)
    content:SetBackdropBorderColor(0.18, 0.42, 0.62, 1)

    local tabDefinitions = {
        {
            key = "GENERAL",
            label = L.TAB_GENERAL,
            icon = "Interface\\Icons\\INV_Misc_Gear_01",
        },
        {
            key = "LEVEL",
            label = L.TAB_LEVEL,
            icon = "Interface\\Icons\\INV_Misc_Book_09",
        },
        {
            key = "THREAT",
            label = L.TAB_THREAT,
            icon = THREAT_TAB_ICON,
        },
        {
            key = "CHANGELOG",
            label = L.TAB_CHANGELOG,
            icon = "Interface\\Icons\\INV_Misc_Note_06",
        },
    }

    local tabs = {}
    local panels = {}

    local function SelectTab(key)
        addon.activeOptionsTab = key
        for _, definition in ipairs(tabDefinitions) do
            local selected = definition.key == key
            local button = tabs[definition.key]
            local panel = panels[definition.key]

            if selected then
                button:SetBackdropColor(0.045, 0.18, 0.29, 0.98)
                button:SetBackdropBorderColor(0.35, 0.75, 1, 1)
                button.text:SetTextColor(0.55, 0.88, 1)
                button:LockHighlight()
                panel:Show()
            else
                button:SetBackdropColor(0.02, 0.065, 0.105, 0.92)
                button:SetBackdropBorderColor(0.12, 0.3, 0.46, 1)
                button.text:SetTextColor(0.78, 0.84, 0.9)
                button:UnlockHighlight()
                panel:Hide()
            end
        end
    end

    for index, definition in ipairs(tabDefinitions) do
        local button = CreateFrame("Button", nil, nav, "BackdropTemplate")
        button:SetPoint("TOPLEFT", nav, "TOPLEFT", 7, -7 - ((index - 1) * 43))
        button:SetPoint("RIGHT", nav, "RIGHT", -7, 0)
        button:SetHeight(36)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("LEFT", button, "LEFT", 9, 0)
        button.icon:SetSize(22, 22)
        button.icon:SetTexture(definition.icon)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.text:SetPoint("LEFT", button.icon, "RIGHT", 8, 0)
        button.text:SetPoint("RIGHT", button, "RIGHT", -6, 0)
        button.text:SetJustifyH("LEFT")
        button.text:SetText(definition.label)

        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.15, 0.55, 0.8, 0.18)
        button:SetHighlightTexture(highlight)

        button:SetScript("OnClick", function()
            SelectTab(definition.key)
        end)

        tabs[definition.key] = button

        local panel = CreateFrame("Frame", nil, content)
        panel:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -12)
        panel:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -12, 12)
        panel:Hide()
        panels[definition.key] = panel
    end

    addon.optionsTabs = tabs
    addon.optionsPanels = panels
    addon.SelectOptionsTab = SelectTab
    SelectTab(addon.activeOptionsTab or "GENERAL")

    return panels
end

local function CreateNameplatePreview(panel)
    CreateSectionTitle(panel, L.PREVIEW, 10, -350)
    controls.nameplateLivePreview = CreateCheckBox(
        panel,
        "BetterNameplatesNameplateLivePreviewCheck",
        L.LIVE_PREVIEW,
        330,
        -350,
        function(value)
            if value then
                UpdateNameplatePreview(true)
            end
        end
    )
    controls.nameplateLivePreview:SetChecked(true)

    local preview = CreatePreviewBox(panel, 10, -385, 100)
    controls.nameplatePreview = preview

    preview.healthBar = CreateFrame("StatusBar", nil, preview, "BackdropTemplate")
    preview.healthBar:SetPoint("CENTER", preview, "CENTER", 0, 4)
    preview.healthBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    preview.healthBar:SetStatusBarColor(0.08, 0.63, 0.18, 1)
    preview.healthBar:SetMinMaxValues(0, 100)
    preview.healthBar:SetValue(72)
    preview.healthBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    preview.healthBar:SetBackdropColor(0.025, 0.06, 0.025, 1)
    preview.healthBar:SetBackdropBorderColor(0, 0, 0, 1)

    preview.name = preview.healthBar:CreateFontString(nil, "OVERLAY")
    preview.name:SetPoint("CENTER")
    preview.name:SetTextColor(1, 1, 1, 1)
    preview.name:SetShadowOffset(1, -1)
    preview.name:SetShadowColor(0, 0, 0, 1)

    preview.level = preview.healthBar:CreateFontString(nil, "OVERLAY")
    preview.level:SetShadowOffset(1, -1)
    preview.level:SetShadowColor(0, 0, 0, 1)
    preview.level:SetWordWrap(false)
    preview.level:SetMaxLines(1)

    preview.healthNumbers = preview.healthBar:CreateFontString(nil, "OVERLAY")
    preview.healthNumbers:SetTextColor(1, 1, 1, 1)
    preview.healthNumbers:SetShadowOffset(1, -1)
    preview.healthNumbers:SetShadowColor(0, 0, 0, 1)
    preview.healthNumbers:SetWordWrap(false)
    preview.healthNumbers:SetMaxLines(1)

    preview.scaleText = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    preview.scaleText:SetPoint("BOTTOM", preview, "BOTTOM", 0, 9)
end

local function CreateThreatPreview(panel)
    CreateSectionTitle(panel, L.PREVIEW, 10, -380)
    controls.threatLivePreview = CreateCheckBox(
        panel,
        "BetterNameplatesThreatLivePreviewCheck",
        L.LIVE_PREVIEW,
        330,
        -380,
        function(value)
            if value then
                previewState.threatPercentage = 0
                previewState.threatElapsed = 0
                UpdateThreatPreview()
            end
        end
    )
    controls.threatLivePreview:SetChecked(true)

    local preview = CreatePreviewBox(panel, 10, -415, 83)
    controls.threatPreview = preview

    preview.healthBar = CreateFrame("StatusBar", nil, preview, "BackdropTemplate")
    preview.healthBar:SetPoint("CENTER", preview, "CENTER", 0, -1)
    preview.healthBar:SetSize(270, 22)
    preview.healthBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    preview.healthBar:SetStatusBarColor(0.62, 0.08, 0.08, 1)
    preview.healthBar:SetMinMaxValues(0, 100)
    preview.healthBar:SetValue(82)
    preview.healthBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    preview.healthBar:SetBackdropColor(0.06, 0.015, 0.015, 1)
    preview.healthBar:SetBackdropBorderColor(0, 0, 0, 1)

    preview.name = preview.healthBar:CreateFontString(nil, "OVERLAY")
    preview.name:SetPoint("CENTER")
    preview.name:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    preview.name:SetText(L.PREVIEW_ENEMY_NAME)

    preview.unitFrame = { healthBar = preview.healthBar }
    preview.threatFrame = CreateFrame("Frame", nil, preview, "BackdropTemplate")
    preview.threatFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    preview.threatFrame:SetFrameLevel(preview.healthBar:GetFrameLevel() + 5)

    preview.threatText = preview.threatFrame:CreateFontString(nil, "OVERLAY")
    preview.threatText:SetPoint("CENTER")
    preview.threatText:SetShadowOffset(1, -1)
    preview.threatText:SetShadowColor(0, 0, 0, 1)

    preview.disabledText = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    preview.disabledText:SetPoint("TOP", preview.healthBar, "BOTTOM", 0, -7)
    preview.disabledText:SetText(L.PREVIEW_DISABLED)
    preview.disabledText:Hide()
end

local function CreateChangelogPanel(panel)
    CreateSectionTitle(panel, L.DISCORD_COMMUNITY, 10, -10)

    local discordButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    discordButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -39)
    discordButton:SetSize(360, 34)
    discordButton:SetText(DISCORD_URL)

    discordButton.icon = discordButton:CreateTexture(nil, "ARTWORK")
    discordButton.icon:SetPoint("LEFT", discordButton, "LEFT", 7, 0)
    discordButton.icon:SetSize(25, 25)
    discordButton.icon:SetTexture(DISCORD_ICON)
    discordButton.icon:SetTexCoord(0, 1, 0, 1)

    local discordText = discordButton:GetFontString()
    if discordText then
        discordText:ClearAllPoints()
        discordText:SetPoint("LEFT", discordButton.icon, "RIGHT", 8, 0)
        discordText:SetPoint("RIGHT", discordButton, "RIGHT", -8, 0)
        discordText:SetJustifyH("LEFT")
        discordText:SetTextColor(0.45, 0.58, 1)
    end

    discordButton:SetScript("OnClick", ShowDiscordLink)
    discordButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.DISCORD_COMMUNITY)
        GameTooltip:AddLine(L.DISCORD_TOOLTIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    discordButton:SetScript("OnLeave", GameTooltip_Hide)

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.25, 0.65, 0.85, 0.35)
    divider:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -86)
    divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -86)
    divider:SetHeight(1)

    CreateSectionTitle(panel, L.CHANGELOG_TITLE, 10, -101)

    local scroll = CreateFrame(
        "ScrollFrame",
        "BetterNameplatesChangelogScrollFrame",
        panel,
        "UIPanelScrollFrameTemplate"
    )
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -130)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -29, 8)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(430)
    content:SetHeight(1)
    scroll:SetScrollChild(content)

    local body = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    body:SetWidth(430)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(3)
    body:SetText(CHANGELOG_TEXT)

    local function UpdateChangelogLayout(_, width)
        local contentWidth = math.max(1, (width or scroll:GetWidth() or 434) - 4)
        content:SetWidth(contentWidth)
        body:SetWidth(contentWidth)
        content:SetHeight(math.max(1, body:GetStringHeight() + 18))
    end

    scroll:SetScript("OnSizeChanged", UpdateChangelogLayout)
    UpdateChangelogLayout(scroll, scroll:GetWidth())
end

function addon:RefreshOptions()
    if not self.db or not self.optionsWindow then
        return
    end

    refreshing = true

    controls.enabled:SetChecked(self.db.enabled)
    controls.scaleEnabled:SetChecked(self.db.scaleEnabled)
    controls.scale:SetValue(self.db.nameplateScale)
    controls.nameScale:SetValue(self.db.nameScale)
    controls.healthNumberScale:SetValue(self.db.healthNumberScale)
    controls.levelScale:SetValue(self.db.levelScale)
    controls.showLevel:SetChecked(self.db.showLevel)
    controls.showEnemyLevel:SetChecked(self.db.showEnemyLevel)
    controls.showFriendlyLevel:SetChecked(self.db.showFriendlyLevel)
    controls.levelColor:SetChecked(self.db.levelColorByDifficulty)
    UIDropDownMenu_SetSelectedValue(controls.levelSide, self.db.levelSide)
    UIDropDownMenu_SetText(controls.levelSide, self.db.levelSide == "LEFT" and L.LEFT or L.RIGHT)
    UIDropDownMenu_SetSelectedValue(controls.levelFormat, self.db.levelFormat)
    local formatText = L.FORMAT_NONE
    if self.db.levelFormat == "BRACKETS" then
        formatText = "[35]"
    elseif self.db.levelFormat == "PREFIX" then
        formatText = L.LEVEL_PREFIX .. " 35"
    end
    UIDropDownMenu_SetText(controls.levelFormat, formatText)

    controls.showThreat:SetChecked(self.db.showThreat)
    UIDropDownMenu_SetSelectedValue(controls.threatMode, self.db.threatDisplayMode)
    UIDropDownMenu_SetText(
        controls.threatMode,
        self.db.threatDisplayMode == "HIGHEST"
            and L.THREAT_MODE_HIGHEST
            or L.THREAT_MODE_ALL
    )
    controls.threatSize:SetValue(self.db.threatSize)
    controls.threatOffset:SetValue(self.db.threatOffset)
    controls.threatOpacity:SetValue(self.db.threatBackgroundOpacity)
    controls.dynamicThreatSize:SetChecked(self.db.dynamicThreatSize)
    controls.dynamicThreatMaxSize:SetValue(self.db.dynamicThreatMaxSize)
    controls.threatCombatOnly:SetChecked(self.db.threatCombatOnly)
    controls.colorizeThreatText:SetChecked(self.db.colorizeThreatText)
    UIDropDownMenu_SetSelectedValue(controls.threatPosition, self.db.threatPosition)
    local threatPositionText = {
        TOPLEFT = L.THREAT_POSITION_TOPLEFT,
        TOP = L.THREAT_POSITION_TOP,
        TOPRIGHT = L.THREAT_POSITION_TOPRIGHT,
        BOTTOMLEFT = L.THREAT_POSITION_BOTTOMLEFT,
        BOTTOM = L.THREAT_POSITION_BOTTOM,
        BOTTOMRIGHT = L.THREAT_POSITION_BOTTOMRIGHT,
    }
    UIDropDownMenu_SetText(
        controls.threatPosition,
        threatPositionText[self.db.threatPosition] or L.THREAT_POSITION_TOP
    )

    controls.showMinimapButton:SetChecked(self.db.showMinimapButton)

    refreshing = false
    self:UpdateOptionsPreviews()
end

function addon:CreateOptions()
    if self.optionsWindow then
        return
    end

    local window = CreateWindow()
    self.optionsWindow = window
    local panels = CreateTabSystem(window)
    local generalPanel = panels.GENERAL
    local levelPanel = panels.LEVEL
    local threatPanel = panels.THREAT
    local changelogPanel = panels.CHANGELOG

    controls.enabled = CreateCheckBox(
        generalPanel,
        "BetterNameplatesEnabledCheck",
        L.ENABLE_ADDON,
        6,
        -16,
        function(value)
            self.db.enabled = value
            self:SyncBetterBlizzPlatesTextScales(true)
            self:ApplyNameplateScale()
            self:ApplyAll()
            self:UpdateOptionsPreviews()
        end
    )

    controls.scaleEnabled = CreateCheckBox(
        generalPanel,
        "BetterNameplatesScaleEnabledCheck",
        L.ENABLE_NAMEPLATE_SCALE,
        6,
        -52,
        function(value)
            self.db.scaleEnabled = value
            self:ApplyNameplateScale()
            self:ApplyAll()
            self:UpdateOptionsPreviews()
        end
    )

    controls.showMinimapButton = CreateCheckBox(
        generalPanel,
        "BetterNameplatesMinimapCheck",
        L.SHOW_MINIMAP_BUTTON,
        6,
        -88,
        function(value)
            self.db.showMinimapButton = value
            if self.UpdateMinimapButton then
                self:UpdateMinimapButton()
            end
        end
    )

    CreateSectionTitle(generalPanel, L.SECTION_SCALE, 10, -135)
    controls.scale = CreateSlider(
        generalPanel,
        "BetterNameplatesScaleSlider",
        L.SCALE_LABEL,
        0.5,
        2.0,
        0.1,
        22,
        -183,
        190,
        0.8,
        function(value)
            self.db.nameplateScale = value
            self:ApplyNameplateScale()
            self:ApplyAll()
            self:UpdateOptionsPreviews()
        end
    )

    local scaleHint = generalPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    scaleHint:SetPoint("TOPLEFT", generalPanel, "TOPLEFT", 22, -238)
    scaleHint:SetWidth(438)
    scaleHint:SetJustifyH("LEFT")
    scaleHint:SetText(L.SCALE_HINT)

    controls.nameScale = CreateSlider(
        generalPanel,
        "BetterNameplatesNameScaleSlider",
        L.NAME_SCALE,
        0.5,
        2.0,
        0.1,
        270,
        -183,
        190,
        1.0,
        function(value)
            self.db.nameScale = value
            self:SyncBetterBlizzPlatesTextScales(true)
            self:ApplyAll()
            self:UpdateOptionsPreviews()
        end
    )

    controls.levelScale = CreateSlider(
        generalPanel,
        "BetterNameplatesLevelScaleSlider",
        L.LEVEL_SCALE,
        0.5,
        2.0,
        0.1,
        22,
        -285,
        190,
        1.0,
        function(value)
            self.db.levelScale = value
            self:ApplyAll()
            self:UpdateOptionsPreviews()
        end
    )

    controls.healthNumberScale = CreateSlider(
        generalPanel,
        "BetterNameplatesHealthNumberScaleSlider",
        L.HEALTH_NUMBER_SCALE,
        0.5,
        2.0,
        0.1,
        270,
        -285,
        190,
        1.0,
        function(value)
            self.db.healthNumberScale = value
            self:SyncBetterBlizzPlatesTextScales(true)
            self:ApplyAll()
            self:UpdateOptionsPreviews()
        end
    )

    CreateNameplatePreview(generalPanel)

    CreateSectionTitle(levelPanel, L.SECTION_LEVEL, 10, -10)
    controls.showLevel = CreateCheckBox(
        levelPanel,
        "BetterNameplatesShowLevelCheck",
        L.SHOW_LEVEL,
        6,
        -50,
        function(value)
            self.db.showLevel = value
            self:ApplyAll()
            self:UpdateOptionsPreviews()
        end
    )
    controls.showEnemyLevel = CreateCheckBox(
        levelPanel,
        "BetterNameplatesEnemyLevelCheck",
        L.SHOW_ENEMY_LEVEL,
        26,
        -88,
        function(value)
            self.db.showEnemyLevel = value
            self:ApplyAll()
            self:UpdateOptionsPreviews()
        end
    )
    controls.showFriendlyLevel = CreateCheckBox(
        levelPanel,
        "BetterNameplatesFriendlyLevelCheck",
        L.SHOW_FRIENDLY_LEVEL,
        26,
        -124,
        function(value)
            self.db.showFriendlyLevel = value
            self:ApplyAll()
            self:UpdateOptionsPreviews()
        end
    )

    local friendlyHint = levelPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    friendlyHint:SetPoint("TOPLEFT", levelPanel, "TOPLEFT", 34, -158)
    friendlyHint:SetWidth(430)
    friendlyHint:SetJustifyH("LEFT")
    friendlyHint:SetText(L.FRIENDLY_RESTRICTION)

    controls.levelColor = CreateCheckBox(
        levelPanel,
        "BetterNameplatesLevelColorCheck",
        L.COLOR_DIFFICULTY,
        26,
        -202,
        function(value)
            self.db.levelColorByDifficulty = value
            self:ApplyAll()
            self:UpdateOptionsPreviews()
        end
    )
    controls.levelSide = CreateSideDropdown(levelPanel, 16, -277)
    controls.levelFormat = CreateFormatDropdown(levelPanel, 255, -277)

    CreateChangelogPanel(changelogPanel)

    CreateSectionTitle(threatPanel, L.SECTION_THREAT, 10, -10)
    controls.showThreat = CreateCheckBox(
        threatPanel,
        "BetterNameplatesShowThreatCheck",
        L.SHOW_THREAT,
        6,
        -50,
        function(value)
            self.db.showThreat = value
            self:UpdateThreatDisplays()
            self:UpdateOptionsPreviews()
        end
    )

    controls.threatMode = CreateThreatModeDropdown(threatPanel, 16, -126)
    controls.threatPosition = CreateThreatPositionDropdown(threatPanel, 270, -126)

    controls.dynamicThreatSize = CreateCheckBox(
        threatPanel,
        "BetterNameplatesDynamicThreatSizeCheck",
        L.DYNAMIC_THREAT_SIZE,
        250,
        -217,
        function(value)
            self.db.dynamicThreatSize = value
            self:UpdateThreatDisplays()
            self:UpdateOptionsPreviews()
        end
    )

    controls.threatCombatOnly = CreateCheckBox(
        threatPanel,
        "BetterNameplatesThreatCombatOnlyCheck",
        L.THREAT_COMBAT_ONLY,
        250,
        -185,
        function(value)
            self.db.threatCombatOnly = value
            self:UpdateThreatDisplays()
            self:UpdateOptionsPreviews()
        end
    )

    controls.colorizeThreatText = CreateCheckBox(
        threatPanel,
        "BetterNameplatesColorizeThreatTextCheck",
        L.COLORIZE_THREAT_TEXT,
        6,
        -217,
        function(value)
            self.db.colorizeThreatText = value
            self:UpdateThreatDisplays()
            self:UpdateOptionsPreviews()
        end
    )

    controls.threatSize = CreateSlider(
        threatPanel,
        "BetterNameplatesThreatSizeSlider",
        L.THREAT_SIZE,
        0.5,
        2.0,
        0.1,
        22,
        -270,
        190,
        1.0,
        function(value)
            self.db.threatSize = value
            self:UpdateThreatDisplays()
            self:UpdateOptionsPreviews()
        end
    )

    controls.dynamicThreatMaxSize = CreateSlider(
        threatPanel,
        "BetterNameplatesDynamicThreatMaxSizeSlider",
        L.DYNAMIC_THREAT_MAX_SIZE,
        1.0,
        3.0,
        0.1,
        270,
        -270,
        190,
        1.8,
        function(value)
            self.db.dynamicThreatMaxSize = value
            self:UpdateThreatDisplays()
            self:UpdateOptionsPreviews()
        end
    )

    controls.threatOpacity = CreateSlider(
        threatPanel,
        "BetterNameplatesThreatOpacitySlider",
        L.THREAT_OPACITY,
        0,
        1,
        0.1,
        22,
        -330,
        190,
        0.5,
        function(value)
            self.db.threatBackgroundOpacity = value
            self:UpdateThreatDisplays()
            self:UpdateOptionsPreviews()
        end
    )

    controls.threatOffset = CreateSlider(
        threatPanel,
        "BetterNameplatesThreatOffsetSlider",
        L.THREAT_OFFSET,
        -40,
        40,
        1,
        270,
        -330,
        190,
        2,
        function(value)
            self.db.threatOffset = value
            self:UpdateThreatDisplays()
            self:UpdateOptionsPreviews()
        end
    )

    CreateThreatPreview(threatPanel)

    local reset = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    reset:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -152, 15)
    reset:SetSize(120, 24)
    reset:SetText(L.RESET)
    reset:SetScript("OnClick", function()
        self:RequestReset()
    end)

    local closeButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    closeButton:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    closeButton:SetSize(120, 24)
    closeButton:SetText(L.CLOSE)
    closeButton:SetScript("OnClick", function()
        window:Hide()
    end)

    local commandHint = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    commandHint:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 21, 21)
    commandHint:SetText(L.OPEN_HINT)

    window:SetScript("OnShow", function()
        if window.UpdateResizeBounds then
            window:UpdateResizeBounds()
        end
        self:RefreshOptions()
    end)
    window:SetScript("OnUpdate", function(_, elapsed)
        if not threatPanel:IsShown()
            or not controls.threatLivePreview
            or not controls.threatLivePreview:GetChecked()
        then
            return
        end

        previewState.threatElapsed = previewState.threatElapsed + elapsed
        if previewState.threatElapsed < 0.05 then
            return
        end

        previewState.threatPercentage =
            (previewState.threatPercentage + (previewState.threatElapsed * 25)) % 101
        previewState.threatElapsed = 0
        UpdateThreatPreview()
    end)

    local settingsPanel = CreateFrame("Frame")
    settingsPanel.name = "BNP"
    self.settingsPanel = settingsPanel

    local settingsTitle = settingsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    settingsTitle:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 20, -20)
    settingsTitle:SetText("|cff40c7ebBNP|r - BetterNameplates")

    local settingsText = settingsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    settingsText:SetPoint("TOPLEFT", settingsTitle, "BOTTOMLEFT", 0, -14)
    settingsText:SetWidth(540)
    settingsText:SetJustifyH("LEFT")
    settingsText:SetText(L.SETTINGS_PAGE_TEXT)

    local openButton = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    openButton:SetPoint("TOPLEFT", settingsText, "BOTTOMLEFT", 0, -20)
    openButton:SetSize(190, 28)
    openButton:SetText(L.OPEN_INTERFACE)
    openButton:SetScript("OnClick", function()
        self:OpenOptions()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        self.settingsCategory = Settings.RegisterCanvasLayoutCategory(
            settingsPanel,
            settingsPanel.name,
            settingsPanel.name
        )
        Settings.RegisterAddOnCategory(self.settingsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(settingsPanel)
    end

    self:RefreshOptions()
end

function addon:OpenOptions()
    if not self.optionsWindow then
        return
    end

    self.optionsWindow:Show()
    self.optionsWindow:Raise()
    self:RefreshOptions()
end

function addon:ToggleOptions()
    if not self.optionsWindow then
        return
    end

    if self.optionsWindow:IsShown() then
        self.optionsWindow:Hide()
    else
        self:OpenOptions()
    end
end
