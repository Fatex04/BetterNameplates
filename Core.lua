local addonName, addon = ...
local L = addon.L

_G.BetterNameplates = addon

addon.defaults = {
    enabled = true,
    nameplateScale = 0.8,

    showLevel = true,
    showEnemyLevel = true,
    showFriendlyLevel = true,
    levelSide = "RIGHT",
    levelFormat = "BRACKETS",
    levelColorByDifficulty = true,

    showThreat = true,
    threatDisplayMode = "ALL",
    threatPosition = "TOP",
    threatSize = 1.0,
    threatOffset = 2,
    threatBackgroundOpacity = 0.45,
    dynamicThreatSize = true,
    dynamicThreatMaxSize = 1.4,
    threatCombatOnly = true,
    colorizeThreatText = false,

    showMinimapButton = true,
    minimapAngle = 225,
}

addon.activePlates = {}
addon.pendingScale = false

local eventFrame = CreateFrame("Frame")
addon.eventFrame = eventFrame

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff40c7ebBNP:|r " .. tostring(message))
end

addon.Print = Print

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then
        return minimum
    elseif value > maximum then
        return maximum
    end
    return value
end

addon.Clamp = Clamp

local function RoundToStep(value, step)
    return math.floor((value / step) + 0.5) * step
end

addon.RoundToStep = RoundToStep

local function CopyDefaults(source, destination)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(destination[key]) ~= "table" then
                destination[key] = {}
            end
            CopyDefaults(value, destination[key])
        elseif destination[key] == nil then
            destination[key] = value
        end
    end
end

local function CopyTable(source)
    local result = {}
    for key, value in pairs(source) do
        result[key] = type(value) == "table" and CopyTable(value) or value
    end
    return result
end

addon.CopyTable = CopyTable

function addon:ApplyNameplateScale()
    if not self.db then
        return
    end

    local scale = RoundToStep(Clamp(self.db.nameplateScale, 0.5, 2.0), 0.1)
    self.db.nameplateScale = scale

    if InCombatLockdown and InCombatLockdown() then
        self.pendingScale = true
        return
    end

    self.pendingScale = false

    local function SetScaleCVar(name, value)
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, name, value)
        elseif SetCVar then
            pcall(SetCVar, name, value)
        end
    end

    local value = string.format("%.1f", scale)
    local horizontalScale = 1
    if scale <= 0.6 then
        horizontalScale = 0.82
    elseif scale < 0.8 then
        horizontalScale = 0.82 + (((scale - 0.6) / 0.2) * 0.18)
    end

    SetScaleCVar("nameplateGlobalScale", "1")
    SetScaleCVar("nameplateMinScale", value)
    SetScaleCVar("nameplateMaxScale", value)
    SetScaleCVar("nameplateSelectedScale", value)
    SetScaleCVar("NamePlateClassificationScale", value)
    SetScaleCVar("nameplateLargerScale", value)
    SetScaleCVar("nameplateHorizontalScale", string.format("%.2f", horizontalScale))

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            addon:ApplyAll()
        end)
    end
end

local function GetUnitFrame(unit)
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
        return nil, nil
    end

    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then
        return plate, nil
    end
    if plate.IsForbidden and plate:IsForbidden() then
        return plate, nil
    end
    if not plate.UnitFrame or not plate.UnitFrame.healthBar then
        return plate, nil
    end

    return plate, plate.UnitFrame
end

local function GetPlateUnit(plate)
    if not plate then
        return nil
    end

    local unit = plate.namePlateUnitToken
    local unitFrame = plate.UnitFrame
    if not unit and unitFrame then
        unit = unitFrame.unit or unitFrame.displayedUnit
    end

    if unit and UnitExists(unit) then
        return unit
    end
    return nil
end

local function CreateOverlay(plate, unitFrame)
    if unitFrame.BetterNameplatesOverlay then
        return unitFrame.BetterNameplatesOverlay
    end

    local overlay = {}

    overlay.inlineName = unitFrame:CreateFontString(nil, "OVERLAY")
    overlay.inlineName:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    overlay.inlineName:SetShadowOffset(1, -1)
    overlay.inlineName:SetShadowColor(0, 0, 0, 1)
    overlay.inlineName:SetWordWrap(false)
    overlay.inlineName:SetMaxLines(1)
    overlay.inlineName:Hide()
    overlay.nameHidden = false

    overlay.threatFrame = CreateFrame("Frame", nil, plate, "BackdropTemplate")
    overlay.threatFrame:SetSize(48, 14)
    overlay.threatFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    overlay.threatFrame:SetBackdropColor(0.1, 0.75, 0.1, 0.9)
    overlay.threatFrame:SetBackdropBorderColor(0.02, 0.02, 0.02, 1)
    overlay.threatFrame:SetFrameLevel(unitFrame:GetFrameLevel() + 50)
    overlay.threatFrame:Hide()

    overlay.threatText = overlay.threatFrame:CreateFontString(nil, "OVERLAY")
    overlay.threatText:SetPoint("CENTER", overlay.threatFrame, "CENTER", 0, 0)
    overlay.threatText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    overlay.threatText:SetTextColor(1, 1, 1, 1)
    overlay.threatText:SetShadowOffset(1, -1)
    overlay.threatText:SetShadowColor(0, 0, 0, 1)

    unitFrame.BetterNameplatesOverlay = overlay
    plate.BetterNameplatesOverlay = overlay
    return overlay
end

local function ShouldShowLevel(unit)
    local db = addon.db
    if not db.enabled or not db.showLevel or not UnitExists(unit) then
        return false
    end

    if UnitCanAttack("player", unit) then
        return db.showEnemyLevel
    end

    return db.showFriendlyLevel
end

local function ToColorCode(r, g, b)
    r = math.floor(Clamp(r or 1, 0, 1) * 255 + 0.5)
    g = math.floor(Clamp(g or 1, 0, 1) * 255 + 0.5)
    b = math.floor(Clamp(b or 1, 0, 1) * 255 + 0.5)
    return string.format("|cff%02x%02x%02x", r, g, b)
end

local function RestoreBlizzardName(unitFrame, overlay)
    local nameText = unitFrame.name
    local forbidden = nameText and nameText.IsForbidden and nameText:IsForbidden()
    if nameText and overlay.nameHidden and not forbidden then
        nameText:SetAlpha(overlay.originalNameAlpha or 1)
    end
    overlay.nameHidden = false
    overlay.inlineName:Hide()
end

local function GetLevelDisplay(unit, level)
    local playerLevel = UnitLevel("player") or 1
    local classification = UnitClassification and UnitClassification(unit)
    local showSkull = level < 0
        or classification == "worldboss"
        or level >= playerLevel + 10

    local display
    if showSkull then
        display = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:17:17:0:-1|t"
    else
        display = tostring(level)
    end

    if addon.db.levelFormat == "BRACKETS" then
        display = "[" .. display .. "]"
    elseif addon.db.levelFormat == "PREFIX" then
        display = L.LEVEL_PREFIX .. " " .. display
    end

    if showSkull or not addon.db.levelColorByDifficulty then
        return display
    end

    local difference = level - playerLevel
    local r, g, b
    if difference <= -10 then
        r, g, b = 0.5, 0.5, 0.5
    elseif difference < 0 then
        r, g, b = 0.25, 0.85, 0.25
    elseif difference <= 2 then
        r, g, b = 1, 0.82, 0
    else
        r, g, b = 1, 0.15, 0.15
    end

    return ToColorCode(r, g, b) .. display .. "|r"
end

local function UpdateLevel(unit, unitFrame, overlay)
    local inlineName = overlay.inlineName
    local nameText = unitFrame.name

    if not ShouldShowLevel(unit) then
        RestoreBlizzardName(unitFrame, overlay)
        return
    end

    local level = UnitLevel(unit)
    if not level or level == 0 then
        RestoreBlizzardName(unitFrame, overlay)
        return
    end

    local unitName = UnitName(unit)
    if not unitName or unitName == "" then
        RestoreBlizzardName(unitFrame, overlay)
        return
    end

    local nameR, nameG, nameB = 1, 1, 1
    local nameForbidden = nameText and nameText.IsForbidden and nameText:IsForbidden()
    if nameText and not nameForbidden then
        local font, size = nameText:GetFont()
        if font and size then
            inlineName:SetFont(font, size, "OUTLINE")
        end
        nameR, nameG, nameB = nameText:GetTextColor()

        if not overlay.nameHidden then
            overlay.originalNameAlpha = nameText:GetAlpha()
            overlay.nameHidden = true
        end
        nameText:SetAlpha(0)
    end

    local levelDisplay = GetLevelDisplay(unit, level)
    local nameDisplay = ToColorCode(nameR, nameG, nameB) .. unitName .. "|r"
    local combined

    if nameForbidden then
        combined = levelDisplay
    elseif addon.db.levelSide == "LEFT" then
        combined = levelDisplay .. "  " .. nameDisplay
    else
        combined = nameDisplay .. "  " .. levelDisplay
    end

    local rightInset = unitFrame.healthNumbers and unitFrame.healthNumbers:IsShown() and 48 or 5
    inlineName:ClearAllPoints()
    inlineName:SetPoint("LEFT", unitFrame.healthBar, "LEFT", 5, 0)
    inlineName:SetPoint("RIGHT", unitFrame.healthBar, "RIGHT", -rightInset, 0)
    inlineName:SetJustifyH(addon.db.levelSide == "LEFT" and "LEFT" or "RIGHT")
    inlineName:SetText(combined)
    inlineName:Show()
end

local function IsEnemyUnit(unit)
    return UnitExists(unit)
        and not UnitIsDeadOrGhost(unit)
        and UnitCanAttack("player", unit)
end

local function GetThreatData(unit)
    if not IsEnemyUnit(unit) then
        return nil
    end

    local isTanking, status, _, rawPercentage = UnitDetailedThreatSituation("player", unit)
    local percentage = tonumber(rawPercentage) or 0

    if isTanking and UnitThreatPercentageOfLead then
        percentage = tonumber(UnitThreatPercentageOfLead("player", unit)) or percentage
    end

    percentage = Clamp(percentage, 0, 999)
    if addon.db.threatCombatOnly
        and (not UnitAffectingCombat("player") or percentage <= 0)
    then
        return nil
    end

    return percentage, status
end

local function InterpolateColor(fromR, fromG, fromB, toR, toG, toB, progress)
    return fromR + ((toR - fromR) * progress),
        fromG + ((toG - fromG) * progress),
        fromB + ((toB - fromB) * progress)
end

local function GetThreatColor(percentage)
    if percentage <= 20 then
        return 0.1, 0.85, 0.1
    elseif percentage <= 40 then
        return InterpolateColor(
            0.1, 0.85, 0.1,
            1, 0.85, 0,
            (percentage - 20) / 20
        )
    elseif percentage <= 70 then
        return InterpolateColor(
            1, 0.85, 0,
            1, 0.45, 0,
            (percentage - 40) / 30
        )
    elseif percentage < 100 then
        return InterpolateColor(
            1, 0.45, 0,
            1, 0.1, 0.1,
            (percentage - 70) / 30
        )
    end
    return 1, 0.1, 0.1
end

local function HideThreat(overlay)
    if overlay and overlay.threatFrame then
        overlay.threatFrame:Hide()
    end
end

local function SetThreatPosition(threatFrame, unitFrame, position, offset)
    threatFrame:ClearAllPoints()
    local anchor = unitFrame.healthBar

    if position == "TOPLEFT" then
        threatFrame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, offset)
    elseif position == "TOPRIGHT" then
        threatFrame:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, offset)
    elseif position == "BOTTOMLEFT" then
        threatFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offset)
    elseif position == "BOTTOM" then
        threatFrame:SetPoint("TOP", anchor, "BOTTOM", 0, offset)
    elseif position == "BOTTOMRIGHT" then
        threatFrame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, offset)
    else
        threatFrame:SetPoint("BOTTOM", anchor, "TOP", 0, offset)
    end
end

local function UpdateThreatOverlay(unit, unitFrame, overlay, shouldShow, percentage, status)
    if not shouldShow or percentage == nil then
        HideThreat(overlay)
        return
    end

    local size = RoundToStep(Clamp(addon.db.threatSize, 0.5, 2.0), 0.1)
    if addon.db.dynamicThreatSize then
        local maximum = RoundToStep(
            Clamp(addon.db.dynamicThreatMaxSize, 1.0, 2.0),
            0.1
        )
        maximum = math.max(size, maximum)
        local progress = Clamp(percentage / 100, 0, 1)
        size = size + ((maximum - size) * progress)
    end

    local offset = math.floor(Clamp(addon.db.threatOffset, -40, 40) + 0.5)
    local width = math.floor((48 * size) + 0.5)
    local height = math.floor((14 * size) + 0.5)
    local fontSize = math.max(7, math.floor((10 * size) + 0.5))
    local opacity = RoundToStep(
        Clamp(addon.db.threatBackgroundOpacity, 0, 1),
        0.1
    )
    local r, g, b = GetThreatColor(percentage)

    SetThreatPosition(
        overlay.threatFrame,
        unitFrame,
        addon.db.threatPosition,
        offset
    )
    overlay.threatFrame:SetSize(width, height)
    overlay.threatFrame:SetBackdropColor(r, g, b, opacity)
    overlay.threatFrame:SetBackdropBorderColor(
        0.02,
        0.02,
        0.02,
        opacity > 0 and math.min(1, opacity + 0.25) or 0
    )
    overlay.threatText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    if addon.db.colorizeThreatText then
        overlay.threatText:SetTextColor(r, g, b, 1)
    else
        overlay.threatText:SetTextColor(1, 1, 1, 1)
    end
    overlay.threatText:SetText(string.format("%d%%", math.floor(percentage + 0.5)))
    overlay.threatFrame:Show()
end

function addon:UpdateThreatDisplays()
    if not self.db then
        return
    end

    local candidates = {}
    local highest

    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local unit = GetPlateUnit(plate)
            if unit then
                self.activePlates[unit] = plate
            end
        end
    end

    for unit, plate in pairs(self.activePlates) do
        local unitFrame = plate and plate.UnitFrame
        local forbidden = plate and plate.IsForbidden and plate:IsForbidden()
        if UnitExists(unit)
            and unitFrame
            and unitFrame.healthBar
            and not forbidden
        then
            local overlay = CreateOverlay(plate, unitFrame)
            local percentage, status = GetThreatData(unit)
            local candidate = {
                unit = unit,
                unitFrame = unitFrame,
                overlay = overlay,
                percentage = percentage,
                status = status,
            }
            candidates[#candidates + 1] = candidate

            if percentage ~= nil
                and (not highest or percentage > highest.percentage)
            then
                highest = candidate
            end
        elseif not UnitExists(unit) then
            self.activePlates[unit] = nil
        end
    end

    for _, candidate in ipairs(candidates) do
        local shouldShow = self.db.enabled and self.db.showThreat
        if self.db.threatDisplayMode == "HIGHEST" then
            shouldShow = shouldShow and candidate == highest
        end
        UpdateThreatOverlay(
            candidate.unit,
            candidate.unitFrame,
            candidate.overlay,
            shouldShow,
            candidate.percentage,
            candidate.status
        )
    end
end

function addon:UpdatePlate(unit)
    if not self.db or not unit then
        return
    end

    local plate, unitFrame = GetUnitFrame(unit)
    if not plate or not unitFrame then
        return
    end

    self.activePlates[unit] = plate
    local overlay = CreateOverlay(plate, unitFrame)
    UpdateLevel(unit, unitFrame, overlay)
    if self.db.threatDisplayMode == "ALL" then
        local percentage, status = GetThreatData(unit)
        UpdateThreatOverlay(
            unit,
            unitFrame,
            overlay,
            self.db.enabled and self.db.showThreat,
            percentage,
            status
        )
    else
        self:UpdateThreatDisplays()
    end
end

function addon:HidePlate(unit)
    local plate = self.activePlates[unit]
    if plate and plate.BetterNameplatesOverlay then
        if plate.UnitFrame then
            RestoreBlizzardName(plate.UnitFrame, plate.BetterNameplatesOverlay)
        else
            plate.BetterNameplatesOverlay.inlineName:Hide()
        end
        HideThreat(plate.BetterNameplatesOverlay)
    end
    self.activePlates[unit] = nil
    self:UpdateThreatDisplays()
end

function addon:ApplyAll()
    if not self.db then
        return
    end

    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local unit = GetPlateUnit(plate)
            if unit then
                self:UpdatePlate(unit)
            end
        end
    end

    self:ApplyGroupPlates()
    self:UpdateThreatDisplays()
end

function addon:ApplyGroupPlates()
    if not IsInGroup or not IsInGroup() then
        return
    end

    local prefix
    local count
    if IsInRaid and IsInRaid() then
        prefix = "raid"
        count = GetNumGroupMembers and GetNumGroupMembers() or 0
    else
        prefix = "party"
        count = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
    end

    for index = 1, count do
        local unit = prefix .. index
        if UnitExists(unit) then
            self:UpdatePlate(unit)
        end
    end
end

function addon:ResetDatabase()
    BetterNameplatesDB = CopyTable(self.defaults)
    self.db = BetterNameplatesDB
    self:ApplyNameplateScale()
    self:ApplyAll()
    if self.UpdateMinimapButton then
        self:UpdateMinimapButton()
    end
    if self.RefreshOptions then
        self:RefreshOptions()
    end
end

local function InitializeDatabase()
    if type(BetterNameplatesDB) ~= "table" then
        BetterNameplatesDB = {}
    end

    local savedThreatPosition = BetterNameplatesDB.threatPosition
    CopyDefaults(addon.defaults, BetterNameplatesDB)

    BetterNameplatesDB.nameplateScale = RoundToStep(
        Clamp(BetterNameplatesDB.nameplateScale, 0.5, 2.0),
        0.1
    )
    if BetterNameplatesDB.levelFormat ~= "BRACKETS"
        and BetterNameplatesDB.levelFormat ~= "PREFIX"
        and BetterNameplatesDB.levelFormat ~= "PLAIN"
    then
        BetterNameplatesDB.levelFormat = "BRACKETS"
    end
    if BetterNameplatesDB.threatDisplayMode ~= "ALL"
        and BetterNameplatesDB.threatDisplayMode ~= "HIGHEST"
    then
        BetterNameplatesDB.threatDisplayMode = "ALL"
    end
    local validThreatPositions = {
        TOPLEFT = true,
        TOP = true,
        TOPRIGHT = true,
        BOTTOMLEFT = true,
        BOTTOM = true,
        BOTTOMRIGHT = true,
    }
    if savedThreatPosition == nil
        or BetterNameplatesDB.threatPosition == "CENTER"
    then
        BetterNameplatesDB.threatPosition = "TOP"
        if BetterNameplatesDB.threatOffset == 8
            or BetterNameplatesDB.threatOffset == 10
        then
            BetterNameplatesDB.threatOffset = 2
        end
    elseif not validThreatPositions[BetterNameplatesDB.threatPosition] then
        BetterNameplatesDB.threatPosition = "TOP"
    end
    BetterNameplatesDB.threatSize = RoundToStep(
        Clamp(BetterNameplatesDB.threatSize, 0.5, 2.0),
        0.1
    )
    BetterNameplatesDB.threatOffset = math.floor(
        Clamp(BetterNameplatesDB.threatOffset, -40, 40) + 0.5
    )
    BetterNameplatesDB.threatBackgroundOpacity = RoundToStep(
        Clamp(BetterNameplatesDB.threatBackgroundOpacity, 0, 1),
        0.1
    )
    BetterNameplatesDB.dynamicThreatMaxSize = RoundToStep(
        Clamp(BetterNameplatesDB.dynamicThreatMaxSize, 1.0, 2.0),
        0.1
    )
    BetterNameplatesDB.levelBrackets = nil
    BetterNameplatesDB.targetArrow = nil
    BetterNameplatesDB.targetArrowScale = nil
    BetterNameplatesDB.targetArrowOffset = nil
    BetterNameplatesDB.targetArrowColor = nil

    addon.db = BetterNameplatesDB
end

eventFrame:RegisterEvent("ADDON_LOADED")
local threatUpdateElapsed = 0
eventFrame:SetScript("OnUpdate", function(_, elapsed)
    if not addon.db
        or not addon.db.enabled
        or not addon.db.showThreat
        or not UnitAffectingCombat("player")
    then
        threatUpdateElapsed = 0
        return
    end

    threatUpdateElapsed = threatUpdateElapsed + elapsed
    if threatUpdateElapsed >= 0.2 then
        threatUpdateElapsed = 0
        addon:UpdateThreatDisplays()
    end
end)

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= addonName then
            return
        end

        InitializeDatabase()
        addon:ApplyNameplateScale()

        if addon.CreateOptions then
            addon:CreateOptions()
        end
        if addon.CreateMinimapButton then
            addon:CreateMinimapButton()
        end

        eventFrame:RegisterEvent("PLAYER_LOGIN")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        eventFrame:RegisterEvent("UNIT_LEVEL")
        eventFrame:RegisterEvent("UNIT_FACTION")
        eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
        eventFrame:RegisterEvent("UNIT_HEALTH")
        eventFrame:RegisterEvent("UNIT_MAXHEALTH")
        eventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
        eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
        eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        return
    end

    if event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        addon:UpdatePlate(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        addon:HidePlate(unit)
    elseif event == "PLAYER_TARGET_CHANGED"
        or event == "PLAYER_REGEN_DISABLED"
    then
        addon:ApplyAll()
    elseif event == "GROUP_ROSTER_UPDATE" then
        addon:ApplyGroupPlates()
    elseif event == "UNIT_LEVEL"
        or event == "UNIT_FACTION"
        or event == "UNIT_NAME_UPDATE"
        or event == "UNIT_HEALTH"
        or event == "UNIT_MAXHEALTH"
    then
        local unit = ...
        if unit and unit:match("^nameplate") then
            addon:UpdatePlate(unit)
        end
    elseif event == "UNIT_THREAT_LIST_UPDATE"
        or event == "UNIT_THREAT_SITUATION_UPDATE"
    then
        addon:UpdateThreatDisplays()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if addon.pendingScale then
            addon:ApplyNameplateScale()
        end
        addon:UpdateThreatDisplays()
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        addon:ApplyNameplateScale()
        C_Timer.After(0, function()
            addon:ApplyAll()
        end)
    end
end)

SLASH_BETTERNAMEPLATES1 = "/bnp"
SLASH_BETTERNAMEPLATES2 = "/betternameplates"
SlashCmdList.BETTERNAMEPLATES = function(message)
    local command, argument = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")

    if command == "" or command == "options" or command == "settings" then
        if addon.OpenOptions then
            addon:OpenOptions()
        end
    elseif command == "scale" then
        local value = tonumber(argument)
        if not value then
            Print(L.USAGE_SCALE)
            return
        end
        addon.db.nameplateScale = RoundToStep(Clamp(value, 0.5, 2.0), 0.1)
        addon:ApplyNameplateScale()
        addon:ApplyAll()
        if addon.RefreshOptions then
            addon:RefreshOptions()
        end
        Print(string.format(L.SCALE_SET, addon.db.nameplateScale))
    elseif command == "level" then
        argument = string.upper(argument or "")
        if argument == "LEFT" or argument == "LINKS" then
            addon.db.showLevel = true
            addon.db.levelSide = "LEFT"
        elseif argument == "RIGHT" or argument == "RECHTS" then
            addon.db.showLevel = true
            addon.db.levelSide = "RIGHT"
        elseif argument == "OFF" or argument == "AUS" then
            addon.db.showLevel = false
        else
            Print(L.USAGE_LEVEL)
            return
        end
        addon:ApplyAll()
        if addon.RefreshOptions then
            addon:RefreshOptions()
        end
    elseif command == "reset" then
        addon:ResetDatabase()
        Print(L.SETTINGS_RESET)
    else
        Print(L.HELP_OPEN)
        Print(L.HELP_SCALE)
        Print(L.HELP_LEVEL)
        Print(L.HELP_RESET)
    end
end
