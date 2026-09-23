local addonName, ESS = ...
ESS.defaults = {
    HUNTER = { [253] = "bm", [254] = "mm", [255] = "sv" },
    DEATHKNIGHT = { [250] = "blood", [251] = "frost", [252] = "uh" },
    DEMONHUNTER = { [577] = "havoc", [581] = "veng", [1480] = "devo" },
    DRUID = { [102] = "balance", [103] = "feral", [104] = "guard", [105] = "resto" },
    EVOKER = { [1467] = "dev", [1468] = "pres", [1473] = "aug" },
    MAGE = { [62] = "arcane", [63] = "fire", [64] = "frost" },
    MONK = { [268] = "bm", [270] = "mw", [269] = "ww" },
    PALADIN = { [65] = "holy", [66] = "prot", [70] = "ret" },
    PRIEST = { [256] = "disc", [257] = "holy", [258] = "sd" },
    ROGUE = { [259] = "assa", [260] = "ol", [261] = "sub" },
    SHAMAN = { [262] = "ele", [263] = "enh", [264] = "resto" },
    WARLOCK = { [265] = "aff", [266] = "demo", [267] = "destro" },
    WARRIOR = { [71] = "arms", [72] = "fury", [73] = "prot" },
}
ESS.slotCount = 5
local pending
local frame = CreateFrame("Frame")
ESS.frame = frame

function ESS:Print(message)
    print("|cff9bd56dEasy Spec Switch:|r " .. message)
end

function ESS:Specs()
    local specs = {}
    for index = 1, GetNumSpecializations() do
        local id, name = C_SpecializationInfo.GetSpecializationInfo(index)
        if id and id > 0 then specs[#specs + 1] = { id = id, name = name, index = index } end
    end
    return specs
end

function ESS:CurrentSpec()
    local index = C_SpecializationInfo.GetSpecialization()
    if index and index > 0 then return C_SpecializationInfo.GetSpecializationInfo(index) end
end

function ESS:Loadouts(specID)
    local result = {}
    for _, id in ipairs(C_ClassTalents.GetConfigIDsBySpecID(specID) or {}) do
        local info = C_Traits.GetConfigInfo(id)
        if info then result[#result + 1] = { id = id, name = info.name } end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

function ESS:HasLoadout(specID, id)
    for _, item in ipairs(self:Loadouts(specID)) do
        if item.id == id then return true end
    end
    return false
end

local function stop(message)
    pending = nil
    if message then ESS:Print(message) end
end

local function blocked()
    if InCombatLockdown() then return "Cannot switch in combat." end
    if UnitIsDeadOrGhost("player") then return "Cannot switch while dead." end
    local id = C_ClassTalents.GetActiveConfigID()
    if id and C_Traits.ConfigHasStagedChanges(id) then
        return "Apply or undo your pending talent changes first."
    end
end

local function completeLoadout()
    local request = pending
    pending = nil -- Updating the selection can synchronously fire events.
    C_ClassTalents.UpdateLastSelectedSavedConfigID(request.specID, request.configID)
    if C_ClassTalents.GetStarterBuildActive() then
        C_ClassTalents.SetStarterBuildActive(false)
    end
end

local loadBuild
local function retryBuild(request, reason)
    request.lastError = reason
    if not request.crossSpec then stop(reason); return end
    if request.retryScheduled then return end
    request.retryScheduled = true
    C_Timer.After(0.25, function()
        request.retryScheduled = nil
        if pending == request and request.phase == "spec" then loadBuild() end
    end)
end

loadBuild = function()
    local request = pending
    if not request or request.phase ~= "spec" then return end
    if ESS:CurrentSpec() ~= request.specID then
        retryBuild(request, "Waiting for the specialization change."); return
    end
    request.reachedSpec = true
    if not request.configID then stop(); return end
    -- The specialization can change before its active trait configuration does.
    local activeID = C_ClassTalents.GetActiveConfigID()
    if not activeID or (request.crossSpec and activeID == request.sourceActiveID) then
        retryBuild(request, "The new specialization's talents are not ready yet."); return
    end
    local reason = blocked()
    if reason then stop(reason); return end
    if not ESS:HasLoadout(request.specID, request.configID) then
        retryBuild(request, "Build is unavailable. Reassign it in /ess."); return
    end
    if C_ClassTalents.IsConfigPopulated and not C_ClassTalents.IsConfigPopulated(request.configID) then
        retryBuild(request, "The saved build is not ready yet."); return
    end
    local canEdit, errorText = C_ClassTalents.CanEditTalents()
    if not canEdit then
        retryBuild(request, errorText and errorText ~= "" and errorText or "Cannot change talents here."); return
    end
    request.phase = "load"
    request.activeID = C_ClassTalents.GetActiveConfigID()
    local result, loadError = C_ClassTalents.LoadConfig(request.configID, true)
    if pending ~= request then return end
    if result == Enum.LoadConfigResult.Error then
        request.loadFailures = (request.loadFailures or 0) + 1
        -- Retry a rejected cross-spec load only if it left no staged changes.
        if request.crossSpec and request.loadFailures < 4 and
            not C_Traits.ConfigHasStagedChanges(request.activeID) then
            request.phase = "spec"
            retryBuild(request, loadError or "Unable to load this build.")
        else
            stop(loadError or "Unable to load this build.")
        end
    elseif result == Enum.LoadConfigResult.NoChangesNecessary then
        completeLoadout()
    elseif result == Enum.LoadConfigResult.Ready then
        if not C_ClassTalents.CommitConfig(request.configID) then
            stop("Could not apply the build. Check your talents.")
        end
    end
end

function ESS:Switch(specID, slot)
    if pending then self:Print("A switch is already in progress."); return end
    local reason = blocked()
    if reason then self:Print(reason); return end
    local selected
    for _, spec in ipairs(self:Specs()) do if spec.id == specID then selected = spec end end
    if not selected then self:Print("Specialization unavailable."); return end
    local configID = slot and self.db.builds[specID] and self.db.builds[specID][slot]
    if slot and (not configID or not self:HasLoadout(specID, configID)) then
        self:Print("Assign this build in /ess first."); return
    end
    if self:CurrentSpec() == specID and not slot then return end
    local request = { specID = specID, configID = configID, phase = "spec",
        crossSpec = self:CurrentSpec() ~= specID,
        sourceActiveID = C_ClassTalents.GetActiveConfigID() }
    pending = request
    C_Timer.After(15, function()
        if pending == request then
            stop("Switch did not complete. " .. (request.lastError or "Try the command again."))
        end
    end)
    if self:CurrentSpec() == specID then
        loadBuild()
    elseif not C_SpecializationInfo.SetSpecialization(selected.index) then
        stop("Cannot switch specialization right now.")
    else
        retryBuild(request, "Waiting for the specialization change.")
    end
end

function ESS:RegisterAlias(alias, specID, slot)
    local command = "/" .. alias
    for key, value in pairs(_G) do
        if type(key) == "string" and key:match("^SLASH_") and
            type(value) == "string" and value:lower() == command then
            self:Print(command .. " is already in use; use /ess " .. alias .. ".")
            return
        end
    end
    local key = "EASYSPECSWITCH_" .. specID .. "_" .. (slot or 0)
    _G["SLASH_" .. key .. "1"] = command
    SlashCmdList[key] = function() ESS:Switch(specID, slot) end
end

function ESS:ValidateAliases(aliases)
    local used = { ess = true }
    for _, spec in ipairs(self:Specs()) do
        local alias = aliases[spec.id]
        if alias and alias ~= "" then
            if not alias:match("^[a-z0-9]+$") then
                return false, "Use letters and numbers for commands."
            end
            if used[alias] then return false, "Each command must be unique." end
            used[alias] = true
        end
    end
    return true
end

function ESS:BuildNumber(specID, slot)
    local numbers = self.db.numbers[specID]
    return numbers and numbers[slot] or tostring(slot)
end

function ESS:ValidateNumbers(numbers)
    local seen = {}
    for slot = 1, self.slotCount do
        local value = numbers[slot]
        if type(value) ~= "string" or not value:match("^[a-z0-9]+$") then
            return false, "Use letters and numbers for each build shortcut."
        end
        if seen[value] then return false, "Each build shortcut must be unique within its specialization." end
        seen[value] = true
    end
    return true
end

function ESS:ValidateCommands(aliases, drafts)
    local valid, reason = self:ValidateAliases(aliases)
    if not valid then return false, reason end
    local used = { ess = true }
    local function claim(command)
        if used[command] then return false end
        used[command] = true
        return true
    end
    for _, spec in ipairs(self:Specs()) do
        local numbers = drafts[spec.id] or self.db.numbers[spec.id] or {"1", "2", "3", "4", "5"}
        valid, reason = self:ValidateNumbers(numbers)
        if not valid then return false, reason end
        local alias = aliases[spec.id]
        if alias and alias ~= "" then
            if not claim(alias) then return false, "Duplicate command: /" .. alias end
            for slot = 1, self.slotCount do
                local command = alias .. numbers[slot]
                if not claim(command) then return false, "Duplicate command: /" .. command end
            end
        end
    end
    return true
end

function ESS:Initialize()
    EasySpecSwitchDB = EasySpecSwitchDB or { aliases = {}, builds = {} }
    self.db = EasySpecSwitchDB
    self.db.aliases = self.db.aliases or {}
    self.db.builds = self.db.builds or {}
    self.db.numbers = self.db.numbers or {}
    local _, class = UnitClass("player")
    -- Fill missing entries on upgrades; an explicit blank still disables a command.
    local used = {}
    for _, alias in pairs(self.db.aliases) do used[alias] = true end
    for id, alias in pairs(self.defaults[class] or {}) do
        if self.db.aliases[id] == nil and not used[alias] then
            self.db.aliases[id] = alias
            used[alias] = true
        end
    end
    self.db.initialized = true
    self.commands = {}
    for _, spec in ipairs(self:Specs()) do
        local alias = self.db.aliases[spec.id]
        if alias and alias:match("^[a-z0-9]+$") and alias ~= "ess" then
            self.commands[alias] = { spec.id }
            self:RegisterAlias(alias, spec.id)
            for slot = 1, self.slotCount do
                local numbered = alias .. self:BuildNumber(spec.id, slot)
                self.commands[numbered] = { spec.id, slot }
                self:RegisterAlias(numbered, spec.id, slot)
            end
        end
    end
end

SLASH_EASYSPECSWITCH1 = "/ess"
SlashCmdList.EASYSPECSWITCH = function(text)
    if not ESS.db then ESS:Print("Requires modern WoW Retail."); return end
    text = text:lower():match("^%s*(.-)%s*$")
    if text == "" then ESS:ShowConfig(); return end
    local command = ESS.commands[text]
    if command then ESS:Switch(command[1], command[2])
    else ESS:Print("Use /ess to configure commands and builds.") end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg, _, spellID)
    if event == "PLAYER_LOGIN" then
        if not (C_SpecializationInfo and C_SpecializationInfo.SetSpecialization and
            C_ClassTalents and C_Traits) then return end
        ESS:Initialize()
        for _, name in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED",
            "CONFIG_COMMIT_FAILED", "SPECIALIZATION_CHANGE_CAST_FAILED",
            "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD", "UNIT_SPELLCAST_FAILED",
            "UNIT_SPELLCAST_INTERRUPTED" }) do frame:RegisterEvent(name) end
    elseif pending then
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_ENTERING_WORLD" then
            stop("Switch cancelled.")
        elseif event == "SPECIALIZATION_CHANGE_CAST_FAILED" then
            stop("Specialization switch interrupted.")
        elseif (event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED") and
            arg == "player" and spellID and IsSpecializationActivateSpell(spellID) then
            stop("Specialization switch interrupted.")
        elseif event == "CONFIG_COMMIT_FAILED" and pending.phase == "load" then
            stop("Build switch failed. Try again when you can change talents.")
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" and arg == "player" then
            if pending.reachedSpec and ESS:CurrentSpec() ~= pending.specID then stop("Switch cancelled.")
            elseif pending.phase == "spec" then
                retryBuild(pending, "Waiting for the new specialization's talents.")
            end
        elseif event == "TRAIT_CONFIG_UPDATED" and pending.phase == "load" and
            arg == pending.activeID and ESS:CurrentSpec() == pending.specID and
            not C_Traits.ConfigHasStagedChanges(arg) then
            completeLoadout()
        end
    end
end)
