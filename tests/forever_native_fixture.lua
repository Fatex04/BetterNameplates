-- Deliberately strict native-UI model for the 1.60.1.70790 frame shapes.
-- No legacy player/target globals, aura headers, or generic method fallbacks.
frames, queued, messages, reportedErrors, requestedTemplates = {}, {}, {}, {}, {}
-- WoW extends Lua 5.1 xpcall with callback arguments (used by AceAddon).
local lua51xpcall = xpcall
xpcall = function(callback, handler, ...)
    local arguments, count = {...}, select('#', ...)
    return lua51xpcall(function() return callback(unpack(arguments, 1, count)) end, handler)
end
loggedIn, combat = false, false
STANDARD_TEXT_FONT = 'Fonts\\FRIZQT__.TTF'
UISpecialFrames, SlashCmdList, hash_SlashCmdList = {}, {}, {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 1, 2
GetLocale = function() return TEST_LOCALE or 'enUS' end
GetBuildInfo = function() return '1.60.1', '70790', 'Nov 3 2026', 16001, '', ' ' end
IsLoggedIn = function() return loggedIn end
InCombatLockdown = function() return combat end
issecretvalue = function(value) return type(value) == 'table' and rawget(value, 'secret') == true end
debugstack = function() return 'Interface/AddOns/BetterNameplates/test callback' end
local errorHandler = function(message) reportedErrors[#reportedErrors + 1] = tostring(message) end
geterrorhandler = function() return errorHandler end
seterrorhandler = function(callback) errorHandler = callback end
wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end
securecallfunction = function(callback, ...) return callback(...) end
DEFAULT_CHAT_FRAME = {AddMessage = function(_, message) messages[#messages + 1] = message end}
C_AddOns = {
    GetAddOnMetadata = function(_, key) return key == 'Version' and '1.6.0' or nil end,
    LoadAddOn = function() error('Unexpected load-on-demand gameplay dependency') end,
}
C_EditMode = {
    SaveLayouts = function() error('Must not rewrite native layouts') end,
    SetActiveLayout = function() error('Must not select/reset native layouts') end,
}
C_Timer = {After = function(_, callback) queued[#queued + 1] = callback end}
function flushTimers()
    local count = 0
    while #queued > 0 do
        count = count + 1
        assert(count < 100, 'refresh loop')
        table.remove(queued, 1)()
    end
end
function hooksecurefunc(object, key, callback)
    if type(object) == 'string' then callback, key, object = key, object, _G end
    local original = assert(object[key], 'Cannot hook missing method: ' .. tostring(key))
    object[key] = function(...)
        local results = {original(...)}
        callback(...)
        return unpack(results)
    end
end

-- Opaque values may pass to native widgets; formatting/math is forbidden.
local secretMT = {}
for _,method in ipairs({'__tostring','__concat','__add','__sub','__mul','__div','__lt','__le'}) do
    secretMT[method]=function() error('Evaluated a secret value in Lua') end
end
function opaque(label) return setmetatable({secret=true,label=label},secretMT) end

local Region = {}
Region.__index = Region
local function region(kind)
    return setmetatable({kind = kind, alpha = 0.8, font = {'NativeFont', 10, 'OUTLINE'},
        texture = 'native-texture', atlas = 'native-atlas', coords = {0.1, 0.9, 0.2, 0.8},
        shown = true, points = {}, width = 30, height = 30, writes = 0,
        vertexColor = {1, 1, 1, 1}, desaturated = false}, Region)
end
function Region:GetObjectType() return self.kind end
function Region:IsForbidden() return self.forbidden == true end
function Region:SetPoint(...) self.points[#self.points + 1] = {...} end
function Region:ClearAllPoints() self.points = {} end
function Region:SetSize(width, height) self.width, self.height = width, height end
function Region:SetAllPoints(owner) self.points = {{'TOPLEFT', owner, 'TOPLEFT'}, {'BOTTOMRIGHT', owner, 'BOTTOMRIGHT'}} end
function Region:GetWidth() return self.width end
function Region:GetHeight() return self.height end
function Region:GetNumPoints() return #self.points end
function Region:GetPoint(index) return unpack(self.points[index]) end
function Region:GetParent() return self.owner end
function Region:SetShadowColor(...) self.shadowColor={...} end
function Region:GetShadowColor() return unpack(self.shadowColor or {0,0,0,0}) end
function Region:SetShadowOffset(...) self.shadowOffset={...} end
function Region:GetShadowOffset() return unpack(self.shadowOffset or {0,0}) end
function Region:SetTextColor(...) self.textColor={...} end
function Region:AddMaskTexture(mask) self.masks=self.masks or {}; table.insert(self.masks,mask) end
function Region:SetWidth(width) self.width = width end
function Region:SetHeight(height) self.height = height end
function Region:GetAlpha() return self.alpha end
function Region:SetAlpha(alpha) self.alpha = alpha; self.writes = self.writes + 1 end
function Region:SetTexture(texture) self.texture, self.atlas = texture, nil; self.writes = self.writes + 1 end
function Region:GetTexture() assert(not self.privateContent, 'Read native spell icon'); return self.texture end
function Region:SetAtlas(atlas) self.atlas = atlas end
function Region:GetAtlas() return self.atlas end
function Region:GetTexCoord() return unpack(self.coords) end
function Region:SetTexCoord(...) self.coords = {...} end
function Region:SetColorTexture(...) self.color = {...} end
function Region:GetVertexColor() return unpack(self.vertexColor) end
function Region:SetVertexColor(...) self.vertexColor = {...} end
function Region:IsDesaturated() return self.desaturated end
function Region:SetDesaturated(value) self.desaturated = value end
function Region:GetFont() return unpack(self.font) end
function Region:SetFont(file, size, flags)
    assert(type(file) == 'string' and type(size) == 'number' and size > 0, 'Font not set')
    self.font = {file, size, flags}; self.writes = self.writes + 1
end
function Region:SetText(text) assert(not self.privateContent, 'Reimplemented native unit/aura text'); self.text = text end
function Region:GetText() return self.text end
function Region:SetJustifyH() end
function Region:SetWordWrap() end
function Region:SetMaxLines() end
function Region:Hide() self.shown = false end
function Region:Show() self.shown = true end
function Region:SetShown(shown) self.shown = shown end

local Frame = {}
Frame.__index = Frame
local function geometryAllowed(self)
    assert(not self.gameplay, 'Modified protected gameplay geometry or lifetime: ' .. tostring(self.name))
end
local function newFrame(kind, name, parent)
    local frame = setmetatable({kind = kind, name = name, parent = parent, children = {},
        events = {}, scripts = {}, scriptHooks = {}, points = {}, width = 200, height = 50,
        scale = 1, alpha = 1, shown = true}, Frame)
    if parent then parent.children[#parent.children + 1] = frame end
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
function Frame:GetName() return self.name end
function Frame:GetObjectType() return self.kind end
function Frame:IsForbidden() return self.forbidden == true end
function Frame:SetPoint(...) geometryAllowed(self); self.points[#self.points + 1] = {...} end
function Frame:ClearAllPoints() geometryAllowed(self); self.points = {} end
function Frame:GetPoint() return unpack(self.points[1] or {'CENTER', UIParent, 'CENTER', 0, 0}) end
function Frame:SetSize(width, height) geometryAllowed(self); self.width, self.height = width, height end
function Frame:SetWidth(width) geometryAllowed(self); self.width = width end
function Frame:SetHeight(height)
    geometryAllowed(self)
    local changed = self.height ~= height
    self.height = height
    if changed then
        if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, self.width, height) end
        for _, callback in ipairs(self.scriptHooks.OnSizeChanged or {}) do callback(self, self.width, height) end
    end
end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:SetScale(scale) geometryAllowed(self); self.scale = scale end
function Frame:GetScale() return self.scale end
function Frame:GetAlpha() return self.alpha end
function Frame:SetAlpha(alpha) self.alpha = alpha end
function Frame:SetFrameStrata() geometryAllowed(self) end
function Frame:SetToplevel() geometryAllowed(self) end
function Frame:SetClampedToScreen() geometryAllowed(self) end
function Frame:EnableMouse(enabled) geometryAllowed(self); self.mouseEnabled = enabled end
function Frame:IsMouseEnabled() return self.mouseEnabled == true end
function Frame:SetFrameLevel(level) geometryAllowed(self); self.frameLevel = level end
function Frame:SetAllPoints(owner) geometryAllowed(self); self.points = {{'TOPLEFT', owner, 'TOPLEFT'}, {'BOTTOMRIGHT', owner, 'BOTTOMRIGHT'}} end
function Frame:GetNumPoints() return #self.points end
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent)
    geometryAllowed(self)
    if self.parent then
        for index, child in ipairs(self.parent.children) do
            if child == self then table.remove(self.parent.children, index); break end
        end
    end
    self.parent = parent
    if parent then parent.children[#parent.children + 1] = self end
end
function Frame:SetMovable() geometryAllowed(self) end
function Frame:RegisterForDrag() geometryAllowed(self) end
function Frame:StartMoving() geometryAllowed(self) end
function Frame:StopMovingOrSizing() geometryAllowed(self) end
function Frame:SetBackdrop() geometryAllowed(self) end
function Frame:SetBackdropColor() geometryAllowed(self) end
function Frame:SetBackdropBorderColor() geometryAllowed(self) end
function Frame:CreateTexture() local r = region('Texture'); r.owner = self; return r end
function Frame:CreateMaskTexture() local r = region('MaskTexture'); r.owner = self; return r end
function Frame:CreateFontString() local r = region('FontString'); r.owner = self; return r end
function Frame:SetScript(event, callback) geometryAllowed(self); self.scripts[event] = callback end
function Frame:GetScript(event) return self.scripts[event] end
function Frame:HookScript(event, callback)
    geometryAllowed(self)
    self.scriptHooks[event] = self.scriptHooks[event] or {}
    table.insert(self.scriptHooks[event], callback)
end
function Frame:RegisterEvent(event) assert(not self.gameplay); self.events[event] = true end
function Frame:UnregisterEvent() error('Must not unregister native gameplay events') end
function Frame:UnregisterAllEvents() error('Must not unregister native gameplay events') end
function Frame:IsShown() return self.shown end
function Frame:Hide()
    geometryAllowed(self)
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
    if wasShown then for _, callback in ipairs(self.scriptHooks.OnHide or {}) do callback(self) end end
end
function Frame:Show()
    geometryAllowed(self); self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
    for _, callback in ipairs(self.scriptHooks.OnShow or {}) do callback(self) end
end
function Frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Frame:GetChildren() return unpack(self.children) end
function Frame:GetRegions() return unpack(self.regions or {}) end
function Frame:GetStatusBarTexture() return self.fill end
function Frame:SetStatusBarTexture(path) self.fill=self.fill or region('Texture'); self.fill:SetTexture(path) end
function Frame:GetStatusBarColor() return unpack(self.barColor or {1,1,1,1}) end
function Frame:SetStatusBarColor(...) self.barColor={...} end
function Frame:SetAlphaFromBoolean(value,on,off) self.alphaFromBoolean={value,on,off} end
function Frame:GetFrameLevel() return self.frameLevel or 1 end
function Frame:GetHighlightTexture() return self.highlight end
function Frame:GetDisabledTexture() return self.disabled end
function Frame:Click(button) if self.scripts.OnClick then return self.scripts.OnClick(self,button) end end
function Frame:GetValue() return self.value end
function Frame:GetMinMaxValues() return self.low, self.high end
function Frame:SetAttribute(key,value) assert(not self.gameplay and self.secureButton,'Must not replace secure native actions'); self.attributes=self.attributes or {}; self.attributes[key]=value end
function Frame:RegisterForClicks() end
function Frame:Disable() self.disabled=true end
function Frame:SetNormalTexture(path) self.normal = region('Texture'); self.normal:SetTexture(path) end
function Frame:GetNormalTexture() return self.normal end
function Frame:SetPushedTexture(path) self.pushed = region('Texture'); self.pushed:SetTexture(path) end
function Frame:GetPushedTexture() return self.pushed end
function Frame:SetCheckedTexture(path) self.checkedTexture = region('Texture'); self.checkedTexture:SetTexture(path) end
function Frame:GetCheckedTexture() return self.checkedTexture end
function Frame:SetChecked(checked) self.checked = checked end
function Frame:GetChecked() return self.checked end
function Frame:SetOrientation() end
function Frame:SetMinMaxValues(low, high) self.low, self.high = low, high end
function Frame:SetValueStep(step) self.step = step end
function Frame:SetObeyStepOnDrag() end
function Frame:SetThumbTexture() self.thumb = region('Texture') end
function Frame:GetThumbTexture() return self.thumb end
function Frame:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function Frame:GetText() return self.text end
function Frame:SetText(text) self.text = text end
function Frame:MarkDirty() self.dirty = true end

function CreateFrame(kind, name, parent, template)
    assert(not template or template == 'BackdropTemplate' or template == 'SecureActionButtonTemplate,BackdropTemplate', 'Unexpected UI template: ' .. tostring(template))
    if template then requestedTemplates[#requestedTemplates + 1] = template end
    local frame=newFrame(kind,name,parent)
    frame.secureButton=template=='SecureActionButtonTemplate,BackdropTemplate'
    return frame
end
UIParent = newFrame('Frame', 'UIParent')
UIParent.height = 1440; UIParent.width=3440
function ShowUIPanel(frame) frame:Show() end
function HideUIPanel(frame) if frame then frame:Hide() end end
function dispatch(event, ...)
    local listeners = {}
    for _, frame in ipairs(frames) do
        if frame.events[event] then listeners[#listeners + 1] = frame end
    end
    for _, frame in ipairs(listeners) do
        if frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
end

