----------------------------------------------
-- ParryDeezNuts - Parry Haste Tracker
-- Version: 1.2.0
-- Detects when a boss parries a NON-TANK raid
-- member's attack (causing parry haste on the
-- tank) and announces the offender.
----------------------------------------------

-- Addon namespace
ParryDeezNuts = ParryDeezNuts or {}

-- Saved variables - do NOT init here, let WoW load them first

-- Local references for performance
local _G = _G or getfenv(0)
local getn = table.getn
local floor = math.floor
local format = string.format
local S_FIND = string.find or strfind
local S_GSUB = string.gsub or gsub
local S_SUB = string.sub or strsub
local S_LOWER = string.lower or strlower
local S_UPPER = string.upper or strupper
local S_LEN = string.len or strlen

-- Constants
local ADDON_NAME = "ParryDeezNuts"
local ADDON_VERSION = "1.2.0"
local ADDON_COLOR = "|cffff4444"
local ADDON_PREFIX = ADDON_COLOR .. "ParryDeezNuts|r: "

----------------------------------------------
-- Insult Pool
-- %s = offender's name
----------------------------------------------

local INSULT_POOL = {
    "%s you stupid fuck! Don't stand in front of the goddamn boss!",
    "%s is apparently too fucking stupid to attack from behind!",
    "%s: PARRY HASTE! Get behind it, jackass!",
    "%s you absolute donkey! PARRY HASTE!",
    "%s YOU IDIOT, WE DO THIS EVERY FUCKIN' WEEK!",
    "%s JUST FUCKING LEAVE YOU PARRY HASTING TWAT!",
    "%s this is why we will never do K40. You are bad and should feel bad.",
    "%s I swear to god if you parry haste one more time I'm replacing you with a fucking pug",
    "%s you're the reason I have to pop cooldowns early you useless sack of shit",
    "%s BEHIND THE BOSS. HOW HARD IS THAT TO UNDERSTAND?!",
    "%s I've explained this fight six times and you're STILL in front of the boss. Unfuckingreal.",
}

-- Return a random insult with player name inserted
local function GetRandomInsult(playerName)
    local idx = math.random(1, getn(INSULT_POOL))
    return format(INSULT_POOL[idx], tostring(playerName))
end

----------------------------------------------
-- Default Settings
----------------------------------------------

local defaults = {
    enabled = true,
    onlyInRaid = true,
    onlyInCombat = true,
    onlyBosses = false,
    throttleSeconds = 3,
    message = "%p parry hasted me! Fuck that guy!",
    -- Tank exclusion
    excludeSelf = true,
    excludeTargetTarget = true,
    tankExcludeList = {},
    -- Output channels
    outputLocal = true,
    outputYell = false,
    outputRaid = false,
    outputRaidWarning = false,
    outputWhisper = false,
    -- Random insults per channel
    insultLocal = false,
    insultYell = false,
    insultRaid = false,
    insultRaidWarning = false,
    insultWhisper = false,
    -- Minimap
    minimapAngle = 195,
    showMinimap = true,
    -- Stats tracking
    trackStats = true,
    -- Window
    showOnScreen = true,
    onScreenDuration = 3,
}

----------------------------------------------
-- Internal State
----------------------------------------------

local throttleTable = {}
local parryStats = {}
local sessionTotal = 0
local initialized = false

----------------------------------------------
-- Utility Functions
----------------------------------------------

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. tostring(msg))
end

local function Debug(msg)
    if ParryDeezNutsDB.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[PDN Debug]|r " .. tostring(msg))
    end
end

local function IsInRaid()
    return GetNumRaidMembers() > 0
end

local function IsInGroup()
    return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
end

----------------------------------------------
-- Tank Detection
----------------------------------------------

local function IsCurrentTank(name)
    if not name then return false end

    -- Method 1: Exclude self (addon user IS the tank)
    if ParryDeezNutsDB.excludeSelf then
        if name == UnitName("player") then
            return true
        end
    end

    -- Method 2: Check targettarget
    if ParryDeezNutsDB.excludeTargetTarget then
        if UnitExists("target") and UnitCanAttack("player", "target") then
            local tankName = UnitName("targettarget")
            if tankName and tankName == name then
                Debug("Excluded (targettarget): " .. tostring(name))
                return true
            end
        end

        -- Scan raid targets for boss and check its target
        local numRaid = GetNumRaidMembers()
        if numRaid > 0 then
            for i = 1, numRaid do
                local raidUnit = "raid" .. tostring(i) .. "target"
                if UnitExists(raidUnit) then
                    local level = UnitLevel(raidUnit)
                    local classification = UnitClassification(raidUnit)
                    if level == -1 or classification == "worldboss" or classification == "raidboss" then
                        local bossTargetUnit = raidUnit .. "target"
                        if UnitExists(bossTargetUnit) then
                            local bossTargetName = UnitName(bossTargetUnit)
                            if bossTargetName and bossTargetName == name then
                                Debug("Excluded (raid scan tank): " .. tostring(name))
                                return true
                            end
                        end
                        break
                    end
                end
            end
        end
    end

    -- Method 3: Manual exclude list
    if ParryDeezNutsDB.tankExcludeList then
        for _, excludeName in ipairs(ParryDeezNutsDB.tankExcludeList) do
            if S_LOWER(excludeName) == S_LOWER(name) then
                Debug("Excluded (manual): " .. tostring(name))
                return true
            end
        end
    end

    return false
end

local function IsMobBoss(mobName)
    -- Check player's target first
    if UnitExists("target") and UnitName("target") == mobName then
        local level = UnitLevel("target")
        if level == -1 then return true end
        local classification = UnitClassification("target")
        if classification == "worldboss" or classification == "raidboss" then
            return true
        end
        return false
    end
    -- Scan raid targets to find the mob by name
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            local unit = "raid" .. tostring(i) .. "target"
            if UnitExists(unit) and UnitName(unit) == mobName then
                local level = UnitLevel(unit)
                if level == -1 then return true end
                local classification = UnitClassification(unit)
                if classification == "worldboss" or classification == "raidboss" then
                    return true
                end
                return false
            end
        end
    end
    -- Can't find the mob, default to allowing it
    return true
end

local function IsRaidMember(name)
    if not name then return false end
    if name == UnitName("player") then return true end
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            if UnitName("raid" .. tostring(i)) == name then return true end
        end
    end
    local numParty = GetNumPartyMembers()
    if numParty > 0 then
        for i = 1, numParty do
            if UnitName("party" .. tostring(i)) == name then return true end
        end
    end
    return false
end

----------------------------------------------
-- Message Formatting
----------------------------------------------

local function FormatMessage(playerName)
    local msg = ParryDeezNutsDB.message or defaults.message
    msg = S_GSUB(msg, "%%p", tostring(playerName))
    return msg
end

-- Get the message for a specific channel
-- If random insults are enabled for that channel, use an insult
-- Otherwise use the custom message template
local function GetChannelMessage(playerName, channelKey)
    if ParryDeezNutsDB[channelKey] then
        return GetRandomInsult(playerName)
    else
        return FormatMessage(playerName)
    end
end

----------------------------------------------
-- On-Screen Warning Frame
----------------------------------------------

local warningFrame = CreateFrame("Frame", "ParryDeezNutsWarningFrame", UIParent)
warningFrame:SetWidth(500)
warningFrame:SetHeight(60)
warningFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
warningFrame:SetFrameStrata("HIGH")
warningFrame:Hide()

local warningText = warningFrame:CreateFontString(nil, "OVERLAY")
warningText:SetPoint("CENTER", warningFrame, "CENTER", 0, 0)
warningText:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
warningText:SetTextColor(1, 0.3, 0.3, 1)
warningText:SetShadowOffset(2, -2)
warningText:SetShadowColor(0, 0, 0, 0.8)
warningFrame.text = warningText

local warningFadeTime = 0

warningFrame:SetScript("OnUpdate", function()
    if warningFadeTime > 0 then
        warningFadeTime = warningFadeTime - arg1
        if warningFadeTime <= 0 then
            warningFrame:Hide()
        elseif warningFadeTime < 1 then
            warningFrame:SetAlpha(warningFadeTime)
        end
    end
end)

local function ShowOnScreenWarning(msg)
    if not ParryDeezNutsDB.showOnScreen then return end
    warningText:SetText(msg)
    warningFrame:SetAlpha(1)
    warningFrame:Show()
    warningFadeTime = ParryDeezNutsDB.onScreenDuration or 3
end

----------------------------------------------
-- Announcement System
----------------------------------------------

local function AnnounceParryHaste(playerName)
    local db = ParryDeezNutsDB

    -- Local chat frame
    if db.outputLocal then
        local localMsg
        if db.insultLocal then
            localMsg = GetRandomInsult(playerName)
        else
            localMsg = tostring(playerName) .. " caused parry haste!"
        end
        DEFAULT_CHAT_FRAME:AddMessage(
            ADDON_COLOR .. "[ParryDeezNuts]|r " ..
            "|cffff4444" .. tostring(localMsg) .. "|r " ..
            "|cffaaaaaa(" .. tostring(parryStats[playerName] or 1) .. " this fight)|r"
        )
    end

    -- On-screen warning
    if db.insultLocal then
        ShowOnScreenWarning(GetRandomInsult(playerName))
    else
        ShowOnScreenWarning(tostring(playerName) .. " PARRY HASTED!")
    end

    -- Yell
    if db.outputYell then
        local msg = GetChannelMessage(playerName, "insultYell")
        SendChatMessage(msg, "YELL")
    end

    -- Raid chat
    if db.outputRaid and IsInRaid() then
        local msg = GetChannelMessage(playerName, "insultRaid")
        SendChatMessage(msg, "RAID")
    end

    -- Raid warning
    if db.outputRaidWarning and IsInRaid() then
        local msg = GetChannelMessage(playerName, "insultRaidWarning")
        if IsRaidLeader() or IsRaidOfficer() then
            SendChatMessage(msg, "RAID_WARNING")
        else
            SendChatMessage("{rt7} " .. msg .. " {rt7}", "RAID")
        end
    end

    -- Whisper the offender
    if db.outputWhisper and playerName ~= UnitName("player") then
        local msg
        if db.insultWhisper then
            msg = "[ParryDeezNuts] " .. GetRandomInsult(playerName)
        else
            msg = "[ParryDeezNuts] You just caused parry haste on the tank! Attack from behind!"
        end
        SendChatMessage(msg, "WHISPER", nil, tostring(playerName))
    end
end

----------------------------------------------
-- Parry Detection Engine
----------------------------------------------
-- Vanilla 1.12.1 GlobalStrings for parry:
--   VSPARRYSELFOTHER = "You attack. %s parries."
--   VSPARRYOTHEROTHER = "%s attacks. %s parries."
--   SPELLPARRIEDSELFOTHER = "Your %s was parried by %s."
--   SPELLPARRIEDOTHEROTHER = "%s's %s was parried by %s."
--   VSPARRYOTHERSELF = "%s attacks. You parry."
--   SPELLPARRIEDOTHERSELF = "%s's %s was parried."
----------------------------------------------

local function ParseParryMessage(msg)
    if not msg then return nil, nil end
    if not S_FIND(S_LOWER(msg), "parr") then
        return nil, nil
    end

    -- Pattern 1: "PlayerName attacks. MobName parries."
    local _, _, name1, name2 = S_FIND(msg, "(.+) attacks%. (.+) parries%.")
    if name1 and name2 then return name1, name2 end

    -- Pattern 2: "You attack. MobName parries."
    local _, _, mobName = S_FIND(msg, "You attack%. (.+) parries%.")
    if mobName then return UnitName("player"), mobName end

    -- Pattern 3: "PlayerName's AbilityName was parried by MobName."
    local _, _, pName, _, mName = S_FIND(msg, "(.+)'s (.+) was parried by (.+)%.")
    if pName and mName then return pName, mName end

    -- Pattern 4: "Your AbilityName was parried by MobName."
    local _, _, _, tName = S_FIND(msg, "Your (.+) was parried by (.+)%.")
    if tName then return UnitName("player"), tName end

    -- Pattern 5: "Your AbilityName was parried."
    local _, _, sName2 = S_FIND(msg, "Your (.+) was parried%.")
    if sName2 then return UnitName("player"), "Unknown" end

    return nil, nil
end

local function HandleParryEvent()
    local msg = arg1
    if not msg then return end
    if not ParryDeezNutsDB.enabled then return end

    local attacker, parriedBy = ParseParryMessage(msg)
    if not attacker then return end

    Debug("Parry: " .. tostring(attacker) .. " -> " .. tostring(parriedBy))

    -- Filters
    if ParryDeezNutsDB.onlyInRaid and not IsInGroup() then return end
    if ParryDeezNutsDB.onlyInCombat and not UnitAffectingCombat("player") then return end
    if ParryDeezNutsDB.onlyBosses and not IsMobBoss(parriedBy) then return end
    if attacker ~= UnitName("player") and not IsRaidMember(attacker) then return end

    -- CRITICAL: Exclude tanks
    if IsCurrentTank(attacker) then
        Debug("Skipped (tank): " .. tostring(attacker))
        return
    end

    -- Stats (always count, even if throttled)
    parryStats[attacker] = (parryStats[attacker] or 0) + 1
    sessionTotal = sessionTotal + 1

    if ParryDeezNutsDB.trackStats then
        if not ParryDeezNutsDB.stats then ParryDeezNutsDB.stats = {} end
        ParryDeezNutsDB.stats[attacker] = (ParryDeezNutsDB.stats[attacker] or 0) + 1
    end

    -- Throttle (only limits announcements, not counting)
    local now = GetTime()
    local throttle = ParryDeezNutsDB.throttleSeconds or 3
    if throttleTable[attacker] and (now - throttleTable[attacker]) < throttle then
        return
    end
    throttleTable[attacker] = now

    -- Announce
    AnnounceParryHaste(attacker)
end

----------------------------------------------
-- Event Registration
----------------------------------------------

local eventFrame = CreateFrame("Frame", "ParryDeezNutsEventFrame")

local combatEvents = {
    "CHAT_MSG_COMBAT_SELF_MISSES",
    "CHAT_MSG_COMBAT_PARTY_MISSES",
    "CHAT_MSG_COMBAT_FRIENDLYPLAYER_MISSES",
    "CHAT_MSG_SPELL_SELF_DAMAGE",
    "CHAT_MSG_SPELL_PARTY_DAMAGE",
    "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
}

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

local combatEventsRegistered = false

local function RegisterCombatEvents()
    if combatEventsRegistered then return end
    for _, evt in ipairs(combatEvents) do
        eventFrame:RegisterEvent(evt)
    end
    combatEventsRegistered = true
end

local function UnregisterCombatEvents()
    if not combatEventsRegistered then return end
    for _, evt in ipairs(combatEvents) do
        eventFrame:UnregisterEvent(evt)
    end
    combatEventsRegistered = false
end

----------------------------------------------
-- Initialization
----------------------------------------------

local function EnsureDB()
    if not ParryDeezNutsDB or type(ParryDeezNutsDB) ~= "table" then
        ParryDeezNutsDB = {}
    end
    if not ParryDeezNutsCharDB or type(ParryDeezNutsCharDB) ~= "table" then
        ParryDeezNutsCharDB = {}
    end
    for key, value in pairs(defaults) do
        if ParryDeezNutsDB[key] == nil then
            ParryDeezNutsDB[key] = value
        end
    end
    if not ParryDeezNutsDB.stats or type(ParryDeezNutsDB.stats) ~= "table" then
        ParryDeezNutsDB.stats = {}
    end
    if not ParryDeezNutsDB.tankExcludeList or type(ParryDeezNutsDB.tankExcludeList) ~= "table" then
        ParryDeezNutsDB.tankExcludeList = {}
    end
end

local function OnPlayerLogin()
    EnsureDB()
    parryStats = {}
    sessionTotal = 0
    throttleTable = {}
    if ParryDeezNutsDB.enabled then RegisterCombatEvents() end
    initialized = true
    CreateMinimapButton()
    if ParryDeezNutsDB.enabled then
        Print("|cff00ff00v" .. ADDON_VERSION .. " loaded!|r Type |cff00ccff/pdn|r for options.")
    end
end

----------------------------------------------
-- Combat End Summary
----------------------------------------------

local function OnCombatEnd()
    if sessionTotal > 0 and ParryDeezNutsDB.outputLocal then
        local msg = ADDON_COLOR .. "[ParryDeezNuts]|r Combat ended. "
        msg = msg .. "|cffffd700" .. tostring(sessionTotal) .. "|r parry-haste(s) from non-tanks."

        local offenders = {}
        for name, count in pairs(parryStats) do
            table.insert(offenders, { name = name, count = count })
        end
        for i = 1, getn(offenders) do
            for j = i + 1, getn(offenders) do
                if offenders[j].count > offenders[i].count then
                    local tmp = offenders[i]
                    offenders[i] = offenders[j]
                    offenders[j] = tmp
                end
            end
        end
        if getn(offenders) > 0 then
            msg = msg .. " Offenders: "
            for i = 1, math.min(getn(offenders), 5) do
                local o = offenders[i]
                if i > 1 then msg = msg .. ", " end
                msg = msg .. "|cffff4444" .. tostring(o.name) .. "|r(" .. tostring(o.count) .. ")"
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end

    parryStats = {}
    sessionTotal = 0
    throttleTable = {}
end

----------------------------------------------
-- Event Handler
----------------------------------------------

eventFrame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" then
        OnPlayerLogin()
    elseif event == "PLAYER_LOGOUT" then
        -- noop
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    else
        HandleParryEvent()
    end
end)

----------------------------------------------
-- Minimap Button
----------------------------------------------

local function CreateMinimapButton()
    local button = CreateFrame("Button", "ParryDeezNutsMinimapButton", Minimap)
    button:SetWidth(31)
    button:SetHeight(31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetTexture("Interface\\Icons\\Ability_Parry")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.icon = icon

    local function UpdatePosition()
        local angle = ParryDeezNutsDB.minimapAngle or 195
        local rad = math.rad(angle)
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", 52 * math.cos(rad), 52 * math.sin(rad))
    end
    UpdatePosition()

    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function() this.dragging = true end)
    button:SetScript("OnDragStop", function() this.dragging = false end)
    button:SetScript("OnUpdate", function()
        if this.dragging then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local a = math.deg(math.atan2(cy - my, cx - mx))
            ParryDeezNutsDB.minimapAngle = a
            local rad = math.rad(a)
            this:ClearAllPoints()
            this:SetPoint("CENTER", Minimap, "CENTER", 52 * math.cos(rad), 52 * math.sin(rad))
        end
    end)

    button:SetScript("OnClick", function()
        if ParryDeezNuts.ToggleOptions then ParryDeezNuts.ToggleOptions() end
    end)

    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffff4444Parry|cffffffffDeez|cffff4444Nuts|r", 1, 1, 1)
        GameTooltip:AddLine("Parry Haste Tracker v" .. ADDON_VERSION, 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ")
        if ParryDeezNutsDB.enabled then
            GameTooltip:AddLine("|cff00ff00Enabled|r - Tracking non-tank parry haste", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("|cffff0000Disabled|r", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: Open settings", 0.5, 0.8, 1)
        GameTooltip:AddLine("Drag: Move button", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if not ParryDeezNutsDB.showMinimap then button:Hide() end
    ParryDeezNuts.minimapButton = button
    return button
end

----------------------------------------------
-- Slash Commands
----------------------------------------------

local function HandleSlashCommand(msg)
    if not ParryDeezNutsDB then
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_COLOR .. "ParryDeezNuts|r: Not loaded yet. Wait for login to complete.")
        return
    end
    local cmd = S_LOWER(msg or "")

    if cmd == "" or cmd == "help" then
        Print("|cffffd700ParryDeezNuts Commands:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/pdn|r - Open settings panel")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/pdn toggle|r - Enable/disable")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/pdn stats|r - Show all-time stats")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/pdn reset|r - Reset stats")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/pdn test|r - Fire a test event")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/pdn insult|r - Preview a random insult")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/pdn tank add|remove|list [name]|r - Tank exclude list")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/pdn minimap|r - Toggle minimap button")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ccff/pdn debug|r - Toggle debug mode")
    elseif cmd == "toggle" then
        ParryDeezNutsDB.enabled = not ParryDeezNutsDB.enabled
        if ParryDeezNutsDB.enabled then
            RegisterCombatEvents()
            Print("|cff00ff00Enabled|r")
        else
            UnregisterCombatEvents()
            Print("|cffff0000Disabled|r")
        end
    elseif cmd == "stats" then
        if not ParryDeezNutsDB.stats or not next(ParryDeezNutsDB.stats) then
            Print("No stats yet.")
            return
        end
        Print("|cffffd700All-Time Parry Haste Stats:|r")
        local list = {}
        for name, count in pairs(ParryDeezNutsDB.stats) do
            table.insert(list, { name = name, count = count })
        end
        for i = 1, getn(list) do
            for j = i + 1, getn(list) do
                if list[j].count > list[i].count then
                    local tmp = list[i]; list[i] = list[j]; list[j] = tmp
                end
            end
        end
        for i = 1, math.min(getn(list), 15) do
            local e = list[i]
            DEFAULT_CHAT_FRAME:AddMessage("  |cffff4444" .. tostring(i) .. ".|r " .. tostring(e.name) .. " - |cffffd700" .. tostring(e.count) .. "|r")
        end
    elseif cmd == "reset" then
        ParryDeezNutsDB.stats = {}
        parryStats = {}
        sessionTotal = 0
        Print("Stats reset.")
    elseif cmd == "test" then
        Print("Test parry event...")
        local testName = "TestDPS"
        parryStats[testName] = (parryStats[testName] or 0) + 1
        sessionTotal = sessionTotal + 1
        AnnounceParryHaste(testName)
    elseif cmd == "insult" then
        local testName = UnitName("player") or "SomeDPS"
        Print("|cffff8800Random insult preview:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  " .. GetRandomInsult(testName))
        DEFAULT_CHAT_FRAME:AddMessage("  " .. GetRandomInsult(testName))
        DEFAULT_CHAT_FRAME:AddMessage("  " .. GetRandomInsult(testName))
    elseif cmd == "minimap" then
        ParryDeezNutsDB.showMinimap = not ParryDeezNutsDB.showMinimap
        if ParryDeezNuts.minimapButton then
            if ParryDeezNutsDB.showMinimap then
                ParryDeezNuts.minimapButton:Show()
            else
                ParryDeezNuts.minimapButton:Hide()
            end
        end
        Print("Minimap button " .. (ParryDeezNutsDB.showMinimap and "shown" or "hidden"))
    elseif S_FIND(cmd, "^tank ") then
        local subCmd = S_SUB(cmd, 6)
        if S_FIND(subCmd, "^add ") then
            local tankName = S_SUB(subCmd, 5)
            if tankName and tankName ~= "" then
                local found = false
                for _, existing in ipairs(ParryDeezNutsDB.tankExcludeList) do
                    if S_LOWER(existing) == S_LOWER(tankName) then found = true; break end
                end
                if not found then
                    table.insert(ParryDeezNutsDB.tankExcludeList, tankName)
                    Print("Added |cff00ff00" .. tostring(tankName) .. "|r to tank list.")
                else
                    Print(tostring(tankName) .. " already in list.")
                end
            end
        elseif S_FIND(subCmd, "^remove ") then
            local tankName = S_SUB(subCmd, 8)
            if tankName and tankName ~= "" then
                local newList = {}
                local removed = false
                for _, existing in ipairs(ParryDeezNutsDB.tankExcludeList) do
                    if S_LOWER(existing) == S_LOWER(tankName) then
                        removed = true
                    else
                        table.insert(newList, existing)
                    end
                end
                ParryDeezNutsDB.tankExcludeList = newList
                Print(removed and ("Removed " .. tostring(tankName)) or (tostring(tankName) .. " not found"))
            end
        elseif subCmd == "list" then
            if getn(ParryDeezNutsDB.tankExcludeList) == 0 then
                Print("Tank list empty. (Self + targettarget auto-excluded)")
            else
                Print("|cffffd700Tank Exclude List:|r")
                for i, name in ipairs(ParryDeezNutsDB.tankExcludeList) do
                    DEFAULT_CHAT_FRAME:AddMessage("  " .. tostring(i) .. ". " .. tostring(name))
                end
            end
        end
    elseif cmd == "debug" then
        ParryDeezNutsDB.debug = not ParryDeezNutsDB.debug
        Print("Debug: " .. (ParryDeezNutsDB.debug and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    else
        if ParryDeezNuts.ToggleOptions then ParryDeezNuts.ToggleOptions() end
    end
end

SLASH_PARRYDEEZ1 = "/pdn"
SLASH_PARRYDEEZ2 = "/parrydeez"
SLASH_PARRYDEEZ3 = "/parrydeznuts"
SlashCmdList["PARRYDEEZ"] = HandleSlashCommand

-- Minimap button created in OnPlayerLogin after EnsureDB

----------------------------------------------
-- Public API
----------------------------------------------

function ParryDeezNuts.IsEnabled() return ParryDeezNutsDB and ParryDeezNutsDB.enabled end
function ParryDeezNuts.GetVersion() return ADDON_VERSION end
function ParryDeezNuts.GetSessionStats() return parryStats, sessionTotal end
function ParryDeezNuts.Enable() ParryDeezNutsDB.enabled = true RegisterCombatEvents() end
function ParryDeezNuts.Disable() ParryDeezNutsDB.enabled = false UnregisterCombatEvents() end
function ParryDeezNuts.GetRandomInsult(name) return GetRandomInsult(name) end
