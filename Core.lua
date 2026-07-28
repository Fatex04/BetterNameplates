local addonName, addon = ...
local L = addon.L

_G.BetterNameplates = addon

addon.defaults = {
    enabled = true,
    scaleEnabled = true,
    nameplateScale = 0.8,
    nameScale = 1.0,
    healthNumberScale = 1.0,

    showLevel = true,
    showEnemyLevel = true,
    showFriendlyLevel = true,
    levelSide = "RIGHT",
    levelFormat = "BRACKETS",
    levelScale = 1.0,
    levelColorByDifficulty = true,

    showThreat = true,
    threatDisplayMode = "ALL",
    threatPosition = "TOP",
    threatSize = 1.0,
    threatOffset = 2,
    threatBackgroundOpacity = 0.5,
    dynamicThreatSize = true,
    dynamicThreatMaxSize = 1.8,
    threatCombatOnly = true,
    colorizeThreatText = false,

    showMinimapButton = true,
    minimapAngle = 225,
    optionsWindowWidth = 720,
    optionsWindowHeight = 650,
}

addon.activePlates = {}
addon.threatCache = {}
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

local function GetNameplateHorizontalScale(scale)
    scale = Clamp(scale, 0.5, 2.0)
    if scale <= 0.6 then
        return 0.82
    elseif scale < 0.8 then
        return 0.82 + (((scale - 0.6) / 0.2) * 0.18)
    end
    return 1
end

addon.GetNameplateHorizontalScale = GetNameplateHorizontalScale

function addon:ApplyNameplateScale()
    if not self.db then
        return
    end

    local configuredScale = RoundToStep(Clamp(self.db.nameplateScale, 0.5, 2.0), 0.1)
    self.db.nameplateScale = configuredScale
    local scale = self.db.enabled and self.db.scaleEnabled and configuredScale or 1.0

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
    local horizontalScale = GetNameplateHorizontalScale(scale)

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

    overlay.inlineLevel = unitFrame:CreateFontString(nil, "OVERLAY")
    overlay.inlineLevel:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    overlay.inlineLevel:SetShadowOffset(1, -1)
    overlay.inlineLevel:SetShadowColor(0, 0, 0, 1)
    overlay.inlineLevel:SetWordWrap(false)
    overlay.inlineLevel:SetMaxLines(1)
    overlay.inlineLevel:Hide()
    overlay.nameHidden = false
    overlay.originalNameScale = unitFrame.name
        and unitFrame.name.GetScale
        and unitFrame.name:GetScale()
        or 1
    if unitFrame.name and unitFrame.name.GetFont then
        overlay.originalNameFont,
        overlay.originalNameFontSize,
        overlay.originalNameFontFlags = unitFrame.name:GetFont()
    end
    overlay.healthNumberFontBases = setmetatable({}, { __mode = "k" })

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
    overlay.threatText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
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
    overlay.inlineLevel:Hide()
end

local function IsFontString(region)
    return region
        and region.GetObjectType
        and region:GetObjectType() == "FontString"
end

local function GetVisibleNumericText(region)
    if not IsFontString(region)
        or (region.IsForbidden and region:IsForbidden())
        or not region.GetText
    then
        return nil
    end

    if region.IsShown and not region:IsShown() then
        return nil
    end

    local ok, text = pcall(region.GetText, region)
    if not ok or type(text) ~= "string" or not text:find("%d") then
        return nil
    end
    return text
end

local function FindHealthNumbers(unitFrame, overlay)
    local bestRegion
    local bestScore = -1
    local visited = {}
    local currentHealth = UnitHealth
        and unitFrame.unit
        and tostring(UnitHealth(unitFrame.unit) or "")
        or ""

    local function Consider(region, bonus)
        if not region
            or visited[region]
            or region == unitFrame.name
            or region == overlay.inlineName
            or region == overlay.inlineLevel
            or region == overlay.threatText
        then
            return
        end
        visited[region] = true

        local text = GetVisibleNumericText(region)
        if not text then
            return
        end

        local score = (bonus or 0) + #text
        local digits = text:gsub("[^%d]", "")
        local looksLikeHealth = false
        if currentHealth ~= ""
            and (text:find(currentHealth, 1, true)
                or digits == currentHealth)
        then
            score = score + 500
            looksLikeHealth = true
        end
        if text:find("/", 1, true) then
            score = score + 30
            looksLikeHealth = true
        elseif text:find("%%") then
            score = score + 15
            looksLikeHealth = true
        end
        if region.GetName then
            local name = region:GetName()
            if name and string.lower(name):find("health", 1, true) then
                score = score + 100
                looksLikeHealth = true
            end
        end
        if (bonus or 0) < 100 and not looksLikeHealth then
            return
        end

        if score > bestScore then
            bestRegion = region
            bestScore = score
        end
    end

    local healthBar = unitFrame.healthBar
    local explicitCandidates = {
        unitFrame.healthNumbers,
        unitFrame.healthText,
        unitFrame.HealthText,
        unitFrame.healthValue,
        unitFrame.HealthValue,
        healthBar and healthBar.healthNumbers,
        healthBar and healthBar.healthText,
        healthBar and healthBar.HealthText,
        healthBar and healthBar.TextString,
        healthBar and healthBar.text,
    }
    for _, region in pairs(explicitCandidates) do
        Consider(region, 1000)
    end

    local function ScanFrame(frame, depth, bonus)
        if not frame or depth < 0 or visited[frame] then
            return
        end
        visited[frame] = true

        if frame.GetRegions then
            for _, region in ipairs({ frame:GetRegions() }) do
                Consider(region, bonus)
            end
        end
        if depth > 0 and frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do
                ScanFrame(child, depth - 1, bonus - 5)
            end
        end
    end

    ScanFrame(healthBar, 2, 200)
    ScanFrame(unitFrame.HealthBarsContainer, 2, 150)
    ScanFrame(unitFrame, 2, 10)
    if bestRegion then
        overlay.healthNumbersRegion = bestRegion
    end
    return bestRegion or overlay.healthNumbersRegion
end

local function ApplyHealthNumberFontScale(healthNumbers, overlay)
    if not healthNumbers
        or not healthNumbers.GetFont
        or not healthNumbers.SetFont
        or (healthNumbers.IsForbidden and healthNumbers:IsForbidden())
    then
        return
    end

    local base = overlay.healthNumberFontBases[healthNumbers]
    if not base then
        local font, size, flags = healthNumbers:GetFont()
        if not font or not size then
            return
        end
        base = {
            font = font,
            size = size,
            flags = flags,
            scale = healthNumbers.GetScale and healthNumbers:GetScale() or 1,
        }
        overlay.healthNumberFontBases[healthNumbers] = base
    end

    local scale = addon.db.enabled
        and Clamp(addon.db.healthNumberScale, 0.5, 2.0)
        or 1
    if healthNumbers.SetScale then
        healthNumbers:SetScale(addon.db.enabled and 1 or base.scale)
    end
    healthNumbers:SetFont(
        base.font,
        math.max(6, base.size * scale),
        base.flags or ""
    )
end

local function ApplyTextScales(unitFrame, overlay)
    local nameText = unitFrame.name
    local nameForbidden = nameText
        and nameText.IsForbidden
        and nameText:IsForbidden()
    if nameText and not nameForbidden then
        local scale = addon.db.enabled
            and Clamp(addon.db.nameScale, 0.5, 2.0)
            or 1
        if nameText.SetScale then
            nameText:SetScale(overlay.originalNameScale)
        end
        if nameText.SetFont
            and overlay.originalNameFont
            and overlay.originalNameFontSize
        then
            nameText:SetFont(
                overlay.originalNameFont,
                math.max(7, overlay.originalNameFontSize * scale),
                overlay.originalNameFontFlags or ""
            )
        end
    end

    local healthNumbers = FindHealthNumbers(unitFrame, overlay)
    ApplyHealthNumberFontScale(healthNumbers, overlay)
end

local function GetHealthNumbersInset(unitFrame, overlay, barWidth)
    local healthNumbers = FindHealthNumbers(unitFrame, overlay)
    if not healthNumbers
        or (healthNumbers.IsForbidden and healthNumbers:IsForbidden())
        or not healthNumbers.IsShown
        or not healthNumbers:IsShown()
    then
        return 5
    end

    if healthNumbers.GetText then
        local ok, text = pcall(healthNumbers.GetText, healthNumbers)
        if ok and (not text or text == "") then
            return 5
        end
    end

    local textWidth = 0
    if healthNumbers.GetStringWidth then
        local ok, width = pcall(healthNumbers.GetStringWidth, healthNumbers)
        if ok then
            textWidth = tonumber(width) or 0
        end
    end

    local visualScale = 1
    if healthNumbers.GetEffectiveScale
        and unitFrame.healthBar.GetEffectiveScale
    then
        local numberOK, numberScale = pcall(
            healthNumbers.GetEffectiveScale,
            healthNumbers
        )
        local barOK, barScale = pcall(
            unitFrame.healthBar.GetEffectiveScale,
            unitFrame.healthBar
        )
        if numberOK
            and barOK
            and numberScale
            and barScale
            and barScale > 0
        then
            visualScale = numberScale / barScale
        end
    end

    local measuredInset = math.ceil((textWidth * visualScale) + 12)
    local safeInset = math.ceil(
        (48 * Clamp(addon.db.healthNumberScale, 0.5, 2.0)) + 6
    )
    return math.min(barWidth * 0.55, math.max(measuredInset, safeInset))
end

local function GetLevelDisplay(unit, level)
    local playerLevel = UnitLevel("player") or 1
    local classification = UnitClassification and UnitClassification(unit)
    local isAttackable = UnitCanAttack and UnitCanAttack("player", unit)

    -- Blizzard can conceal an enemy's level as -1. Friendly units should keep
    -- their numeric level whenever the client exposes an effective level.
    if not isAttackable and level < 0 and UnitEffectiveLevel then
        local effectiveLevel = UnitEffectiveLevel(unit)
        if effectiveLevel and effectiveLevel > 0 then
            level = effectiveLevel
        end
    end

    local showSkull = isAttackable
        and (level < 0 or classification == "worldboss")

    local display
    if showSkull then
        local skullSize = math.max(
            8,
            math.floor(17 * Clamp(addon.db.levelScale, 0.5, 2.0) + 0.5)
        )
        display = string.format(
            "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:%d:%d:0:-1|t",
            skullSize,
            skullSize
        )
    elseif level and level > 0 then
        display = tostring(level)
    else
        display = "??"
    end

    if addon.db.levelFormat == "BRACKETS" then
        display = "[" .. display .. "]"
    elseif addon.db.levelFormat == "PREFIX" then
        display = L.LEVEL_PREFIX .. " " .. display
    end

    if showSkull or not addon.db.levelColorByDifficulty then
        return display
    end

    local r, g, b
    if not isAttackable then
        local color = UNIT_LEVEL_NON_ATTACKABLE or NORMAL_FONT_COLOR
        r = color and color.r or 1
        g = color and color.g or 1
        b = color and color.b or 1
    else
        local color
        if GetRelativeDifficultyColor then
            color = GetRelativeDifficultyColor(playerLevel, level)
        elseif GetCreatureDifficultyColor then
            color = GetCreatureDifficultyColor(level)
        end

        if color then
            r, g, b = color.r, color.g, color.b
        else
            -- Compatibility fallback for clients without Blizzard's helpers.
            local difference = level - playerLevel
            local grayLevel
            if playerLevel <= 5 then
                grayLevel = 0
            elseif playerLevel <= 39 then
                grayLevel = playerLevel - math.floor(playerLevel / 10) - 5
            elseif playerLevel <= 59 then
                grayLevel = playerLevel - 1 - math.floor(playerLevel / 5)
            else
                grayLevel = playerLevel - 9
            end

            if level <= grayLevel then
                r, g, b = 0.5, 0.5, 0.5
            elseif difference <= -3 then
                r, g, b = 0.25, 0.75, 0.25
            elseif difference <= 2 then
                r, g, b = 1, 0.82, 0
            elseif difference <= 4 then
                r, g, b = 1, 0.5, 0.25
            else
                r, g, b = 1, 0.1, 0.1
            end
        end
    end

    return ToColorCode(r, g, b) .. display .. "|r"
end

local function UTF8Length(text)
    local count = 0
    for index = 1, #text do
        local byte = string.byte(text, index)
        if byte < 128 or byte >= 192 then
            count = count + 1
        end
    end
    return count
end

local function UTF8Sub(text, characterCount)
    if characterCount <= 0 then
        return ""
    end

    local count = 0
    for index = 1, #text do
        local byte = string.byte(text, index)
        if byte < 128 or byte >= 192 then
            count = count + 1
            if count > characterCount then
                return string.sub(text, 1, index - 1)
            end
        end
    end
    return text
end

local function TruncateToWidth(fontString, text, maximumWidth)
    maximumWidth = math.max(0, tonumber(maximumWidth) or 0)
    fontString:SetWidth(0)
    fontString:SetText(text)
    if fontString:GetStringWidth() <= maximumWidth then
        return text
    end

    local suffix = "..."
    fontString:SetText(suffix)
    if fontString:GetStringWidth() > maximumWidth then
        return ""
    end

    local low = 0
    local high = UTF8Length(text)
    local best = ""
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local candidate = UTF8Sub(text, middle) .. suffix
        fontString:SetText(candidate)
        if fontString:GetStringWidth() <= maximumWidth then
            best = candidate
            low = middle + 1
        else
            high = middle - 1
        end
    end
    return best
end

addon.TruncateToWidth = TruncateToWidth

local function UpdateLevel(unit, unitFrame, overlay)
    local inlineName = overlay.inlineName
    local inlineLevel = overlay.inlineLevel
    local nameText = unitFrame.name

    ApplyTextScales(unitFrame, overlay)

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
    local nameFont = overlay.originalNameFont or STANDARD_TEXT_FONT
    local nameSize = overlay.originalNameFontSize or 11
    local nameForbidden = nameText and nameText.IsForbidden and nameText:IsForbidden()
    if nameText and not nameForbidden then
        nameR, nameG, nameB = nameText:GetTextColor()

        if not overlay.nameHidden then
            overlay.originalNameAlpha = nameText:GetAlpha()
            overlay.nameHidden = true
        end
        nameText:SetAlpha(0)
    end

    inlineName:SetFont(
        nameFont,
        math.max(7, nameSize * Clamp(addon.db.nameScale, 0.5, 2.0)),
        "OUTLINE"
    )
    inlineName:SetTextColor(nameR, nameG, nameB, 1)
    inlineLevel:SetFont(
        nameFont,
        math.max(7, nameSize * Clamp(addon.db.levelScale, 0.5, 2.0)),
        "OUTLINE"
    )

    local levelDisplay = GetLevelDisplay(unit, level)
    inlineName:ClearAllPoints()
    inlineLevel:ClearAllPoints()
    inlineLevel:SetWidth(0)
    inlineLevel:SetText(levelDisplay)

    local barWidth = unitFrame.healthBar:GetWidth()
    if not barWidth or barWidth <= 0 then
        barWidth = 120
    end
    local rightInset = GetHealthNumbersInset(unitFrame, overlay, barWidth)
    local levelWidth = math.ceil(inlineLevel:GetStringWidth())
    local gap = 4
    local nameWidth = math.max(0, barWidth - 5 - rightInset - levelWidth - gap)

    local truncatedName
    if not nameForbidden then
        truncatedName = TruncateToWidth(inlineName, unitName, nameWidth)
    end

    if nameForbidden then
        inlineName:Hide()
        if addon.db.levelSide == "LEFT" then
            inlineLevel:SetPoint("LEFT", unitFrame.healthBar, "LEFT", 5, 0)
        else
            inlineLevel:SetPoint("RIGHT", unitFrame.healthBar, "RIGHT", -rightInset, 0)
        end
    elseif addon.db.levelSide == "LEFT" then
        inlineLevel:SetPoint("LEFT", unitFrame.healthBar, "LEFT", 5, 0)
        inlineName:SetPoint("LEFT", inlineLevel, "RIGHT", gap, 0)
        inlineName:SetPoint("RIGHT", unitFrame.healthBar, "RIGHT", -rightInset, 0)
        inlineName:SetJustifyH("LEFT")
    else
        inlineLevel:SetPoint("RIGHT", unitFrame.healthBar, "RIGHT", -rightInset, 0)
        inlineName:SetPoint("LEFT", unitFrame.healthBar, "LEFT", 5, 0)
        inlineName:SetPoint("RIGHT", inlineLevel, "LEFT", -gap, 0)
        inlineName:SetJustifyH("LEFT")
    end

    if not nameForbidden then
        inlineName:SetText(truncatedName)
        inlineName:Show()
    end
    inlineLevel:Show()
end

local function IsEnemyUnit(unit)
    return UnitExists(unit)
        and not UnitIsDeadOrGhost(unit)
        and UnitCanAttack("player", unit)
end

local THREAT_CACHE_GRACE = 0.11

local function GetThreatData(unit)
    if not IsEnemyUnit(unit) then
        return nil
    end

    local inCombat = UnitAffectingCombat("player")
    local guid = UnitGUID(unit)
    local now = GetTime and GetTime() or 0
    local _, status, scaledPercentage, rawPercentage =
        UnitDetailedThreatSituation("player", unit)
    local percentage = tonumber(scaledPercentage) or tonumber(rawPercentage)
    local cached = guid and addon.threatCache[guid]

    if status == nil and UnitThreatSituation then
        status = UnitThreatSituation("player", unit)
    end

    if percentage == nil then
        if status ~= nil then
            -- A current status is authoritative. Never keep an old 100% after
            -- aggro has already dropped below the tanking states.
            percentage = status >= 2 and 100 or 0
        elseif inCombat
            and cached
            and cached.percentage < 100
            and now - cached.updatedAt <= THREAT_CACHE_GRACE
        then
            -- Bridge only one genuinely missing API sample. Explicit zeroes
            -- and stale tanking values are never replaced by cached data.
            percentage = cached.percentage
            status = cached.status
        else
            percentage = 0
        end
    end

    percentage = Clamp(percentage, 0, 100)
    if guid then
        if percentage > 0 then
            addon.threatCache[guid] = {
                percentage = percentage,
                status = status,
                updatedAt = now,
            }
        else
            addon.threatCache[guid] = nil
        end
    end

    if addon.db.threatCombatOnly
        and (not inCombat or percentage <= 0)
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

addon.GetThreatColor = GetThreatColor

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

addon.SetThreatPosition = SetThreatPosition

local function GetThreatVisualSize(percentage)
    local size = RoundToStep(Clamp(addon.db.threatSize, 0.5, 2.0), 0.1)
    if addon.db.dynamicThreatSize then
        local maximum = RoundToStep(
            Clamp(addon.db.dynamicThreatMaxSize, 1.0, 3.0),
            0.1
        )
        if size >= maximum then
            size = math.max(0.5, maximum - 0.5)
        end
        local progress = Clamp(percentage / 100, 0, 1)
        size = size + ((maximum - size) * progress)
    end
    return size
end

addon.GetThreatVisualSize = GetThreatVisualSize

local function ApplyThreatAppearance(threatFrame, threatText, percentage)
    local size = GetThreatVisualSize(percentage)
    local opacity = RoundToStep(
        Clamp(addon.db.threatBackgroundOpacity, 0, 1),
        0.1
    )
    local r, g, b = GetThreatColor(percentage)

    threatFrame:SetSize(48, 14)
    threatFrame:SetScale(size)
    threatFrame:SetBackdropColor(r, g, b, opacity)
    threatFrame:SetBackdropBorderColor(
        0.02,
        0.02,
        0.02,
        opacity > 0 and math.min(1, opacity + 0.25) or 0
    )
    threatText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    if addon.db.colorizeThreatText then
        threatText:SetTextColor(r, g, b, 1)
    else
        threatText:SetTextColor(1, 1, 1, 1)
    end
    threatText:SetText(string.format("%d%%", math.floor(percentage + 0.5)))
end

addon.ApplyThreatAppearance = ApplyThreatAppearance

local function UpdateThreatOverlay(unit, unitFrame, overlay, shouldShow, percentage, status)
    if not shouldShow or percentage == nil then
        HideThreat(overlay)
        return
    end

    local offset = math.floor(Clamp(addon.db.threatOffset, -40, 40) + 0.5)

    SetThreatPosition(
        overlay.threatFrame,
        unitFrame,
        addon.db.threatPosition,
        offset
    )
    ApplyThreatAppearance(overlay.threatFrame, overlay.threatText, percentage)
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
        local shouldShow = self.db.showThreat
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
            self.db.showThreat,
            percentage,
            status
        )
    else
        self:UpdateThreatDisplays()
    end
end

function addon:RefreshCompatibleUnitFrame(unitFrame)
    if not self.db
        or not unitFrame
        or not unitFrame.unit
        or not unitFrame.healthBar
    then
        return
    end

    local plate = C_NamePlate
        and C_NamePlate.GetNamePlateForUnit
        and C_NamePlate.GetNamePlateForUnit(unitFrame.unit)
    local forbidden = plate and plate.IsForbidden and plate:IsForbidden()
    if not plate or forbidden then
        return
    end

    self.activePlates[unitFrame.unit] = plate
    local overlay = CreateOverlay(plate, unitFrame)
    UpdateLevel(unitFrame.unit, unitFrame, overlay)
end

function addon:InstallCompatibilityHooks()
    if self.betterBlizzPlatesHooksInstalled
        or not hooksecurefunc
        or type(BBP) ~= "table"
    then
        return
    end

    local installed = false
    local function HookBetterBlizzPlatesFunction(functionName)
        if type(BBP[functionName]) ~= "function" then
            return
        end

        hooksecurefunc(BBP, functionName, function(unitFrame)
            addon:RefreshCompatibleUnitFrame(unitFrame)
        end)
        installed = true
    end

    -- BetterBlizzPlates reapplies both values during its own updates. Running
    -- after those functions keeps BNP's name and HP sliders authoritative.
    HookBetterBlizzPlatesFunction("HealthNumbers")
    HookBetterBlizzPlatesFunction("ClassColorAndScaleNames")
    self.betterBlizzPlatesHooksInstalled = installed
end

function addon:SyncBetterBlizzPlatesTextScales(refreshNameplates)
    if not self.db or type(BetterBlizzPlatesDB) ~= "table" then
        return
    end

    if not self.betterBlizzPlatesOriginalTextScales then
        self.betterBlizzPlatesOriginalTextScales = {
            healthNumbersScale = BetterBlizzPlatesDB.healthNumbersScale or 1,
            enemyNameScale = BetterBlizzPlatesDB.enemyNameScale or 1,
            friendlyNameScale = BetterBlizzPlatesDB.friendlyNameScale or 1,
        }
    end

    local nameScale
    local healthNumberScale
    if self.db.enabled then
        nameScale = Clamp(self.db.nameScale, 0.5, 2.0)
        healthNumberScale = Clamp(self.db.healthNumberScale, 0.5, 2.0)
    else
        nameScale = self.betterBlizzPlatesOriginalTextScales.enemyNameScale
        healthNumberScale =
            self.betterBlizzPlatesOriginalTextScales.healthNumbersScale
    end

    local friendlyNameScale = self.db.enabled
        and nameScale
        or self.betterBlizzPlatesOriginalTextScales.friendlyNameScale
    local changed =
        BetterBlizzPlatesDB.healthNumbersScale ~= healthNumberScale
        or BetterBlizzPlatesDB.enemyNameScale ~= nameScale
        or BetterBlizzPlatesDB.friendlyNameScale ~= friendlyNameScale

    BetterBlizzPlatesDB.healthNumbersScale = healthNumberScale
    BetterBlizzPlatesDB.enemyNameScale = nameScale
    BetterBlizzPlatesDB.friendlyNameScale = friendlyNameScale

    if changed and type(BBP) == "table" then
        BBP.needsUpdate = true
        if refreshNameplates
            and not self.syncingBetterBlizzPlates
            and type(BBP.RefreshAllNameplates) == "function"
        then
            self.syncingBetterBlizzPlates = true
            pcall(BBP.RefreshAllNameplates)
            self.syncingBetterBlizzPlates = false
        end
    end
end

function addon:HidePlate(unit)
    local plate = self.activePlates[unit]
    local guid = UnitGUID(unit)
    if guid then
        self.threatCache[guid] = nil
    end
    if plate and plate.BetterNameplatesOverlay then
        if plate.UnitFrame then
            RestoreBlizzardName(plate.UnitFrame, plate.BetterNameplatesOverlay)
        else
            plate.BetterNameplatesOverlay.inlineName:Hide()
            plate.BetterNameplatesOverlay.inlineLevel:Hide()
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

    self:SyncBetterBlizzPlatesTextScales(false)

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
    wipe(self.threatCache)
    BetterNameplatesDB = CopyTable(self.defaults)
    self.db = BetterNameplatesDB
    if self.ResetOptionsWindowLayout then
        self:ResetOptionsWindowLayout()
    end
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
    BetterNameplatesDB.nameScale = RoundToStep(
        Clamp(BetterNameplatesDB.nameScale, 0.5, 2.0),
        0.1
    )
    BetterNameplatesDB.healthNumberScale = RoundToStep(
        Clamp(BetterNameplatesDB.healthNumberScale, 0.5, 2.0),
        0.1
    )
    BetterNameplatesDB.levelScale = RoundToStep(
        Clamp(BetterNameplatesDB.levelScale, 0.5, 2.0),
        0.1
    )
    BetterNameplatesDB.optionsWindowWidth = math.floor(
        Clamp(BetterNameplatesDB.optionsWindowWidth, 720, 3840) + 0.5
    )
    BetterNameplatesDB.optionsWindowHeight = math.floor(
        Clamp(BetterNameplatesDB.optionsWindowHeight, 650, 2160) + 0.5
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
        Clamp(BetterNameplatesDB.dynamicThreatMaxSize, 1.0, 3.0),
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
        or not addon.db.showThreat
        or not UnitAffectingCombat("player")
    then
        threatUpdateElapsed = 0
        return
    end

    threatUpdateElapsed = threatUpdateElapsed + elapsed
    if threatUpdateElapsed >= 0.1 then
        threatUpdateElapsed = threatUpdateElapsed - 0.1
        addon:UpdateThreatDisplays()
    end
end)

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == "BetterBlizzPlates" and addon.db then
            addon:InstallCompatibilityHooks()
            addon:SyncBetterBlizzPlatesTextScales(true)
            addon:ApplyAll()
            return
        end
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
        addon:InstallCompatibilityHooks()
        addon:SyncBetterBlizzPlatesTextScales(true)

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
        wipe(addon.threatCache)
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
        if addon.RequestReset then
            addon:RequestReset()
        end
    elseif command == "debug" then
        Print(string.format(
            "nameScale=%.1f, healthNumberScale=%.1f",
            addon.db.nameScale,
            addon.db.healthNumberScale
        ))
        local detected = 0
        if C_NamePlate and C_NamePlate.GetNamePlates then
            for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
                local unitFrame = plate.UnitFrame
                local unit = GetPlateUnit(plate)
                if unitFrame and unitFrame.healthBar and unit then
                    local overlay = CreateOverlay(plate, unitFrame)
                    local healthNumbers = FindHealthNumbers(unitFrame, overlay)
                    if healthNumbers then
                        local text = healthNumbers.GetText
                            and healthNumbers:GetText()
                            or "?"
                        local size = 0
                        if healthNumbers.GetFont then
                            local _, fontSize = healthNumbers:GetFont()
                            size = tonumber(fontSize) or 0
                        end
                        detected = detected + 1
                        Print(string.format(
                            "%s: HP='%s', font=%.1f",
                            unit,
                            tostring(text),
                            size
                        ))
                    end
                end
            end
        end
        Print("Detected HP texts: " .. detected)
    else
        Print(L.HELP_OPEN)
        Print(L.HELP_SCALE)
        Print(L.HELP_LEVEL)
        Print(L.HELP_RESET)
    end
end
