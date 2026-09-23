local _, ESS = ...
local function classAccent()
    local _, class = UnitClass("player")
    local color = C_ClassColor.GetClassColor(class)
    return color and {color.r, color.g, color.b, 1} or {0.7, 0.7, 0.7, 1}
end
local function linear(value)
    return value <= 0.04045 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
end
local accent = classAccent()
local luminance = 0.2126 * linear(accent[1]) + 0.7152 * linear(accent[2]) + 0.0722 * linear(accent[3])
local darkText = luminance > 0.179
local primaryText = darkText and {0, 0, 0, 1} or {1, 1, 1, 1}
local hoverAccent = {0, 0, 0, 1}
for i = 1, 3 do
    hoverAccent[i] = darkText and (accent[i] + (1 - accent[i]) * 0.12) or accent[i] * 0.88
end
local C = {
    bg = {0.065, 0.075, 0.085, 0.98}, panel = {0.105, 0.12, 0.135, 1},
    border = {0.21, 0.24, 0.27, 1}, accent = accent,
    text = {0.91, 0.93, 0.95, 1}, muted = {0.56, 0.61, 0.66, 1},
}
local backdrop = {bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1}
local activeBackdrop = {bgFile = backdrop.bgFile, edgeFile = backdrop.edgeFile, edgeSize = 2}
local function highlight(frame, active)
    frame.essActive = not not active
    frame:SetBackdrop(active and activeBackdrop or backdrop)
    frame:SetBackdropColor(unpack(C.panel))
    frame:SetBackdropBorderColor(unpack(active and C.accent or C.border))
end
local function skin(frame, color)
    frame:SetBackdrop(backdrop)
    frame:SetBackdropColor(unpack(color or C.panel))
    frame:SetBackdropBorderColor(unpack(C.border))
end
local function label(parent, text, x, y, font, color)
    local item = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    item:SetPoint("TOPLEFT", x, y)
    item:SetTextColor(unpack(color or C.text))
    item:SetText(text)
    return item
end
local function tooltip(control, text)
    control:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 0.91, 0.93, 0.95, 1, true)
        GameTooltip:Show()
    end)
    control:HookScript("OnLeave", function() GameTooltip:Hide() end)
end
local function button(parent, text, width, height, primary, dropdown)
    local b = CreateFrame(dropdown and "DropdownButton" or "Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height)
    skin(b, primary and C.accent or C.panel)
    b.caption = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.caption:SetPoint("LEFT", 12, 0)
    b.caption:SetPoint("RIGHT", -12, 0)
    b.caption:SetWordWrap(false)
    b.caption:SetTextColor(unpack(primary and primaryText or C.text))
    if primary then
        local font, size = b.caption:GetFont()
        b.caption:SetFont(font, size, "")
        b.caption:SetShadowOffset(0, 0)
        b.caption:SetShadowColor(0, 0, 0, 0)
    end
    function b:SetText(value) self.caption:SetText(value) end
    b:SetText(text)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(C.accent))
        if primary then self:SetBackdropColor(unpack(hoverAccent)) end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(self.essActive and C.accent or C.border))
        self:SetBackdropColor(unpack(primary and C.accent or C.panel))
    end)
    return b
end
function ESS:ShowConfig()
    if self.window then self.window:Show(); self.window:Refresh(); return end
    local specs = self:Specs()
    local buildTop = 166 + #specs * 42
    local window = CreateFrame("Frame", "EasySpecSwitchConfig", UIParent, "BackdropTemplate")
    self.window = window
    window:SetSize(504, buildTop + 88 + self.slotCount * 40 + 34)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    skin(window, C.bg)
    table.insert(UISpecialFrames, "EasySpecSwitchConfig")
    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(106)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() window:StartMoving() end)
    header:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
    local stripe = header:CreateTexture(nil, "BACKGROUND")
    stripe:SetColorTexture(unpack(C.accent))
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("TOPRIGHT")
    stripe:SetHeight(2)
    label(header, "Easy Spec Switch", 23, -24, "GameFontNormalLarge")
    local description = label(header,
        "Type / (slash) and your specialization shortcut in chat to switch specs. Follow it with your saved build shortcut to select a build (no spaces).",
        23, -54, "GameFontHighlightSmall", C.muted)
    description:SetWidth(456)
    description:SetJustifyH("LEFT")
    description:SetWordWrap(true)
    local close = button(header, "X", 28, 28)
    close:SetPoint("TOPRIGHT", -16, -18)
    close.caption:ClearAllPoints()
    close.caption:SetPoint("CENTER")
    close:SetScript("OnClick", function() window:Hide() end)
    tooltip(close, "Close")
    label(window, "SPECIALIZATIONS", 24, -120, "GameFontHighlightSmall", C.muted)
    label(window, "COMMAND", 318, -120, "GameFontHighlightSmall", C.muted)
    window.rows = {}
    for i, spec in ipairs(specs) do
        local row = CreateFrame("Frame", nil, window, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 24, -146 - (i - 1) * 42)
        row:SetSize(456, 36)
        skin(row)
        local _, _, _, icon = C_SpecializationInfo.GetSpecializationInfo(spec.index)
        local texture = row:CreateTexture(nil, "ARTWORK")
        texture:SetSize(24, 24)
        texture:SetPoint("LEFT", 7, 0)
        texture:SetTexture(icon)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local name = label(row, spec.name, 42, -11)
        name:SetWidth(219)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        local edit = CreateFrame("EditBox", nil, row, "BackdropTemplate")
        edit:SetSize(156, 28)
        edit:SetPoint("RIGHT", -4, 0)
        skin(edit, C.bg)
        edit:SetFontObject("GameFontHighlight")
        edit:SetTextInsets(22, 8, 0, 0)
        edit:SetAutoFocus(false)
        edit:SetText(self.db.aliases[spec.id] or "")
        label(edit, "/", 9, -7, "GameFontHighlight", C.muted)
        edit:SetScript("OnEscapePressed", edit.ClearFocus)
        edit:SetScript("OnEnterPressed", edit.ClearFocus)
        edit:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
        edit:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
        tooltip(edit, "Leave blank to disable this command.")
        window.rows[#window.rows + 1] = {spec = spec, edit = edit, frame = row}
    end
    label(window, "SAVED BUILDS", 24, -buildTop, "GameFontHighlightSmall", C.muted)
    window.specLabel = label(window, "", 24, -buildTop - 23, "GameFontHighlight", C.accent)
    window.buildRows = {}
    window.numberDrafts = {}
    function window:CaptureNumbers()
        if not self.displayedSpec then return end
        local numbers = {}
        for slot, row in ipairs(self.buildRows) do
            numbers[slot] = row.number:GetText():lower():match("^%s*(.-)%s*$")
        end
        self.numberDrafts[self.displayedSpec] = numbers
    end
    for slot = 1, self.slotCount do
        local y = -buildTop - 56 - (slot - 1) * 40
        local command = label(window, "", 24, y - 10, "GameFontHighlight", C.muted)
        command:SetWidth(64)
        command:SetJustifyH("LEFT")
        command:SetWordWrap(false)
        local number = CreateFrame("EditBox", nil, window, "BackdropTemplate")
        number:SetSize(120, 34)
        number:SetPoint("TOPLEFT", 96, y)
        skin(number, C.bg)
        number:SetFontObject("GameFontHighlight")
        number:SetTextInsets(8, 8, 0, 0)
        number:SetAutoFocus(false)
        number:SetScript("OnEscapePressed", number.ClearFocus)
        number:SetScript("OnEnterPressed", number.ClearFocus)
        number:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
        number:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
        tooltip(number, "Build shortcut. Save and reload to apply.")
        local b = button(window, "", 252, 34, false, true)
        b:SetPoint("TOPLEFT", 228, y)
        b.caption:SetJustifyH("LEFT")
        b.caption:SetPoint("RIGHT", -34, 0)
        label(b, "v", 230, -10, "GameFontHighlight", C.muted)
        b:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPLEFT", b, "BOTTOMLEFT", 0, -2))
        tooltip(b, "Select a saved build. Changes save immediately.")
        b:SetupMenu(function(_, root)
            local specID = ESS:CurrentSpec()
            if not specID then return end
            local builds = ESS.db.builds[specID] or {}
            local function selected(id) return builds[slot] == id end
            local function selectBuild(id)
                -- Ignore an old menu if the player changed spec while it was open.
                if ESS:CurrentSpec() ~= specID then return end
                if id and not ESS:HasLoadout(specID, id) then
                    ESS:Print("Build is unavailable. Choose another build."); return
                end
                ESS.db.builds[specID] = builds
                builds[slot] = id
                window:Refresh()
            end
            root:CreateRadio("Not assigned", selected, selectBuild, nil)
            local loadouts = ESS:Loadouts(specID)
            if #loadouts == 0 then root:CreateTitle("No saved builds") end
            for _, item in ipairs(loadouts) do
                root:CreateRadio(item.name, selected, selectBuild, item.id)
            end
            root:SetScrollMode(240)
        end)
        window.buildRows[slot] = {command = command, number = number, button = b}
    end
    local save = button(window, "Save and reload", 164, 36, true)
    window.saveButton = save
    save:SetPoint("BOTTOMRIGHT", -24, 22)
    save:SetScript("OnClick", function()
        if InCombatLockdown() then ESS:Print("Finish combat before saving and reloading."); return end
        local aliases = {}
        for _, row in ipairs(window.rows) do
            aliases[row.spec.id] = row.edit:GetText():lower():match("^%s*(.-)%s*$"):gsub("^/", "")
        end
        window:CaptureNumbers()
        local valid, reason = ESS:ValidateCommands(aliases, window.numberDrafts)
        if not valid then ESS:Print(reason); return end
        ESS.db.aliases = aliases
        for specID, numbers in pairs(window.numberDrafts) do ESS.db.numbers[specID] = numbers end
        ReloadUI()
    end)
    function window:Refresh()
        self:CaptureNumbers()
        local specID, name = ESS:CurrentSpec()
        if self.displayedSpec ~= specID then
            for _, row in ipairs(self.buildRows) do row.button:CloseMenu() end
        end
        self.displayedSpec = specID
        for _, row in ipairs(self.rows) do highlight(row.frame, row.spec.id == specID) end
        self.specLabel:SetText(name or "No specialization")
        local selectedBuild = specID and not C_ClassTalents.GetStarterBuildActive()
            and C_ClassTalents.GetLastSelectedSavedConfigID(specID)
        local alias = specID and ESS.db.aliases[specID]
        local builds = ESS.db.builds[specID] or {}
        for slot, row in ipairs(self.buildRows) do
            row.command:SetText(alias and alias ~= "" and ("/" .. alias) or "Build")
            local draft = specID and self.numberDrafts[specID]
            row.number:SetText(draft and draft[slot] or ESS:BuildNumber(specID, slot))
            local id = builds[slot]
            local info = id and C_Traits.GetConfigInfo(id)
            highlight(row.button, id and info and id == selectedBuild)
            row.button:SetText(id and (info and info.name or "Missing build - click to clear") or "Not assigned")
            row.button.caption:SetTextColor(unpack(info and C.text or C.muted))
        end
    end
    window:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    window:RegisterEvent("TRAIT_CONFIG_LIST_UPDATED")
    window:RegisterEvent("SELECTED_LOADOUT_CHANGED")
    window:RegisterEvent("TRAIT_CONFIG_UPDATED")
    window:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
    window:SetScript("OnEvent", function() if window:IsShown() then window:Refresh() end end)
    window:SetScript("OnHide", function(self)
        self:CaptureNumbers()
        for _, row in ipairs(self.buildRows) do row.button:CloseMenu() end
    end)
    window:Refresh()
end
