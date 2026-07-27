local _, addon = ...
local L = addon.L

local ADDON_ICON = "Interface\\AddOns\\BetterNameplates\\assets\\bnp_logo.tga"
local DISCORD_ICON = "Interface\\AddOns\\BetterNameplates\\assets\\discord_icon.tga"
local DISCORD_URL = "https://discord.gg/ZfYDHV6Qgs"
local DISCORD_DIALOG_KEY = "BETTERNAMEPLATES_DISCORD_LINK"
local CHANGELOG_TEXT = [=[|cff9d8cffV1.0 - Initial Release|r

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
• Added a larger skull indicator for units at least 10 levels above the player.

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

local function CreateSlider(parent, name, label, minimum, maximum, step, x, y, width, onValueChanged)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetWidth(width)
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    _G[name .. "Low"]:SetText(tostring(minimum))
    _G[name .. "High"]:SetText(tostring(maximum))

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

local function CreateWindow()
    local window = CreateFrame("Frame", "BetterNameplatesWindow", UIParent, "BackdropTemplate")
    window:SetSize(720, 530)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
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

    local logo = window:CreateTexture(nil, "ARTWORK")
    logo:SetPoint("TOPLEFT", window, "TOPLEFT", 22, -15)
    logo:SetSize(46, 46)
    logo:SetTexture(ADDON_ICON)
    logo:SetTexCoord(0, 1, 0, 1)

    local title = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -5)
    title:SetText("BetterNameplates |cff9d8cffV1.0|r")

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
            icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
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

    content:SetHeight(math.max(1, body:GetStringHeight() + 18))
end

function addon:RefreshOptions()
    if not self.db or not self.optionsWindow then
        return
    end

    refreshing = true

    controls.enabled:SetChecked(self.db.enabled)
    controls.scale:SetValue(self.db.nameplateScale)
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
            self:ApplyAll()
        end
    )

    controls.showMinimapButton = CreateCheckBox(
        generalPanel,
        "BetterNameplatesMinimapCheck",
        L.SHOW_MINIMAP_BUTTON,
        6,
        -52,
        function(value)
            self.db.showMinimapButton = value
            if self.UpdateMinimapButton then
                self:UpdateMinimapButton()
            end
        end
    )

    CreateSectionTitle(generalPanel, L.SECTION_SCALE, 10, -105)
    controls.scale = CreateSlider(
        generalPanel,
        "BetterNameplatesScaleSlider",
        L.SCALE_LABEL,
        0.5,
        2.0,
        0.1,
        22,
        -153,
        310,
        function(value)
            self.db.nameplateScale = value
            self:ApplyNameplateScale()
            self:ApplyAll()
        end
    )

    local scaleHint = generalPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    scaleHint:SetPoint("TOPLEFT", generalPanel, "TOPLEFT", 22, -208)
    scaleHint:SetWidth(430)
    scaleHint:SetJustifyH("LEFT")
    scaleHint:SetText(L.SCALE_HINT)

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
        end
    )

    controls.threatMode = CreateThreatModeDropdown(threatPanel, 16, -126)
    controls.threatPosition = CreateThreatPositionDropdown(threatPanel, 270, -126)

    controls.dynamicThreatSize = CreateCheckBox(
        threatPanel,
        "BetterNameplatesDynamicThreatSizeCheck",
        L.DYNAMIC_THREAT_SIZE,
        6,
        -185,
        function(value)
            self.db.dynamicThreatSize = value
            self:UpdateThreatDisplays()
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
        function(value)
            self.db.threatSize = value
            self:UpdateThreatDisplays()
        end
    )

    controls.dynamicThreatMaxSize = CreateSlider(
        threatPanel,
        "BetterNameplatesDynamicThreatMaxSizeSlider",
        L.DYNAMIC_THREAT_MAX_SIZE,
        1.0,
        2.0,
        0.1,
        270,
        -270,
        190,
        function(value)
            self.db.dynamicThreatMaxSize = value
            self:UpdateThreatDisplays()
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
        function(value)
            self.db.threatBackgroundOpacity = value
            self:UpdateThreatDisplays()
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
        function(value)
            self.db.threatOffset = value
            self:UpdateThreatDisplays()
        end
    )

    local reset = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    reset:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -152, 15)
    reset:SetSize(120, 24)
    reset:SetText(L.RESET)
    reset:SetScript("OnClick", function()
        self:ResetDatabase()
        self:Print(L.SETTINGS_RESET)
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
        self:RefreshOptions()
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
