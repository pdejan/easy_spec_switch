local _, ESS = ...
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
-- A build load stages changes before its commit cast; track them so a failed commit can undo them.
local committing, rollbackID
local commitSpellID = Constants and Constants.TraitConsts and
    Constants.TraitConsts.COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID
local frame = CreateFrame("Frame")

function ESS:Print(message)
    print("|cff9bd56dEasy Spec Switch:|r " .. message)
end

function ESS:Specs()
    local specs = {}
    for index = 1, GetNumSpecializations() do
        local id, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(index)
        if id and id > 0 then specs[#specs + 1] = { id = id, name = name, icon = icon, index = index } end
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
    for _, configID in ipairs(C_ClassTalents.GetConfigIDsBySpecID(specID) or {}) do
        if configID == id then return C_Traits.GetConfigInfo(id) ~= nil end
    end
    return false
end

local function stop(message)
    pending = nil
    if message then ESS:Print(message) end
end

-- Discard changes left staged by the addon's own failed load, after combat if needed.
local function rollback(configID)
    rollbackID = configID or rollbackID
    if not rollbackID or InCombatLockdown() then return end
    if C_Traits.ConfigHasStagedChanges(rollbackID) then C_Traits.RollbackConfig(rollbackID) end
    rollbackID = nil
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
    request.activeID = activeID
    committing = request -- Set first: loading can fire commit events synchronously.
    local result, loadError = C_ClassTalents.LoadConfig(request.configID, true)
    if pending ~= request then return end
    if result == Enum.LoadConfigResult.Error then
        committing = nil
        loadError = loadError and loadError ~= "" and loadError or "Unable to load this build."
        request.loadFailures = (request.loadFailures or 0) + 1
        -- Retry a rejected cross-spec load only if it left no staged changes.
        if request.crossSpec and request.loadFailures < 4 and
            not C_Traits.ConfigHasStagedChanges(activeID) then
            request.phase = "spec"
            retryBuild(request, loadError)
        else
            rollback(activeID)
            stop(loadError)
        end
    elseif result == Enum.LoadConfigResult.NoChangesNecessary then
        committing = nil
        completeLoadout()
    elseif result == Enum.LoadConfigResult.Ready and not C_ClassTalents.CommitConfig(request.configID) then
        committing = nil
        rollback(activeID)
        stop("Could not apply the build. Check your talents.")
    end
end

function ESS:Switch(specID, slot)
    if pending then self:Print("A switch is already in progress."); return end
    local reason = blocked()
    if reason then self:Print(reason); return end
    local selected
    for _, spec in ipairs(self:Specs()) do
        if spec.id == specID then selected = spec; break end
    end
    if not selected then self:Print("Specialization unavailable."); return end
    local configID = slot and self.db.builds[specID] and self.db.builds[specID][slot]
    if slot and (not configID or not self:HasLoadout(specID, configID)) then
        self:Print("Assign this build in /ess first."); return
    end
    local current = self:CurrentSpec()
    if current == specID and not slot then return end
    local request = { specID = specID, configID = configID, phase = "spec",
        crossSpec = current ~= specID,
        sourceActiveID = C_ClassTalents.GetActiveConfigID() }
    pending = request
    C_Timer.After(15, function()
        if pending == request then
            stop("Switch did not complete. " .. (request.lastError or "Try the command again."))
        end
        -- By now the commit has finished or failed; clear anything it left staged.
        if committing == request then
            committing = nil
            rollback(request.activeID)
        end
    end)
    if not request.crossSpec then
        loadBuild()
    elseif not C_SpecializationInfo.SetSpecialization(selected.index) then
        stop("Cannot switch specialization right now.")
    else
        retryBuild(request, "Waiting for the specialization change.")
    end
end

function ESS:SlashCommands()
    local commands = {}
    for key, value in pairs(_G) do
        if type(key) == "string" and type(value) == "string" and key:match("^SLASH_.-%d+$") then
            commands[value:lower()] = true
        end
    end
    return commands
end

function ESS:RegisterAlias(alias, specID, slot, taken)
    local command = "/" .. alias
    taken = taken or self:SlashCommands()
    if taken[command] then
        self:Print(command .. " is already in use; use /ess " .. alias .. ".")
        return
    end
    taken[command] = true
    local key = "EASYSPECSWITCH_" .. specID .. "_" .. (slot or 0)
    _G["SLASH_" .. key .. "1"] = command
    SlashCmdList[key] = function() ESS:Switch(specID, slot) end
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
    local used = { ess = true }
    local function claim(command)
        if used[command] then return false end
        used[command] = true
        return true
    end
    for _, spec in ipairs(self:Specs()) do
        local alias = aliases[spec.id]
        if alias and alias ~= "" and not alias:match("^[a-z0-9]+$") then
            return false, "Use letters and numbers for commands."
        end
        local numbers = drafts[spec.id]
        if not numbers then
            numbers = {}
            for slot = 1, self.slotCount do numbers[slot] = self:BuildNumber(spec.id, slot) end
        end
        local valid, reason = self:ValidateNumbers(numbers)
        if not valid then return false, reason end
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
    EasySpecSwitchDB = EasySpecSwitchDB or {}
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
    self.commands = {}
    local taken = self:SlashCommands()
    for _, spec in ipairs(self:Specs()) do
        local alias = self.db.aliases[spec.id]
        if alias and alias:match("^[a-z0-9]+$") and alias ~= "ess" then
            self.commands[alias] = { spec.id }
            self:RegisterAlias(alias, spec.id, nil, taken)
            for slot = 1, self.slotCount do
                local numbered = alias .. self:BuildNumber(spec.id, slot)
                self.commands[numbered] = { spec.id, slot }
                self:RegisterAlias(numbered, spec.id, slot, taken)
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
        frame:UnregisterEvent("PLAYER_LOGIN")
        if not (C_SpecializationInfo and C_SpecializationInfo.SetSpecialization and
            C_ClassTalents and C_Traits) then return end
        ESS:Initialize()
        for _, name in ipairs({ "TRAIT_CONFIG_UPDATED", "CONFIG_COMMIT_FAILED",
            "SPECIALIZATION_CHANGE_CAST_FAILED", "PLAYER_REGEN_DISABLED",
            "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do frame:RegisterEvent(name) end
        for _, name in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "UNIT_SPELLCAST_FAILED",
            "UNIT_SPELLCAST_INTERRUPTED" }) do frame:RegisterUnitEvent(name, "player") end
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        rollback()
        return
    end
    if committing then
        if event == "CONFIG_COMMIT_FAILED" or ((event == "UNIT_SPELLCAST_FAILED" or
            event == "UNIT_SPELLCAST_INTERRUPTED") and commitSpellID and spellID == commitSpellID) then
            local configID = committing.activeID
            committing = nil
            rollback(configID)
            if pending and pending.phase == "load" then
                stop("Build switch interrupted. Talent changes were undone; try again.")
            end
            return
        elseif event == "TRAIT_CONFIG_UPDATED" and arg == committing.activeID and
            not C_Traits.ConfigHasStagedChanges(arg) then
            committing = nil
        end
    end
    if pending then
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_ENTERING_WORLD" then
            stop("Switch cancelled.")
        elseif event == "SPECIALIZATION_CHANGE_CAST_FAILED" then
            stop("Specialization switch interrupted.")
        elseif (event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED") and
            spellID and IsSpecializationActivateSpell(spellID) then
            stop("Specialization switch interrupted.")
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
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
