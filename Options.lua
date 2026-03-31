----------------------------------------------
-- ParryDeezNuts - Options Panel
-- Glass-style UI with output channels,
-- per-channel random insult toggles,
-- tank exclusion, and stats display
----------------------------------------------

local _G = _G or getfenv(0)
local getn = table.getn
local floor = math.floor
local S_FIND = string.find or strfind
local S_GSUB = string.gsub or gsub
local S_LOWER = string.lower or strlower

local ADDON_COLOR = "|cffff4444"

----------------------------------------------
-- Backdrop Templates
----------------------------------------------

local glassBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local sectionBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 9,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

----------------------------------------------
-- Helpers
----------------------------------------------

local function CreateSectionHeader(parent, text, yOffset)
    local header = parent:CreateFontString(nil, "OVERLAY")
    header:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    header:SetTextColor(1, 0.82, 0, 1)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, yOffset)
    header:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(1, 0.82, 0, 0.3)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    line:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
    return header
end

local function CreateCB(name, parent, text, tooltip, onClick)
    local cb = CreateFrame("CheckButton", "PDN_CB_" .. name, parent, "UICheckButtonTemplate")
    cb:SetWidth(22)
    cb:SetHeight(22)
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    label:SetText(text)
    label:SetTextColor(0.9, 0.9, 0.9, 1)
    cb.label = label
    if tooltip then
        cb:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:AddLine(text, 1, 1, 1)
            GameTooltip:AddLine(tooltip, 0.7, 0.7, 0.7, 1)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    cb:SetScript("OnClick", function()
        if onClick then
            local checked = this:GetChecked()
            if checked then onClick(true) else onClick(false) end
        end
    end)
    return cb
end

local function CreateEB(name, parent, width)
    local container = CreateFrame("Frame", nil, parent)
    container:SetWidth(width + 10)
    container:SetHeight(30)
    local editbox = CreateFrame("EditBox", "PDN_EB_" .. name, container)
    editbox:SetWidth(width)
    editbox:SetHeight(20)
    editbox:SetPoint("TOPLEFT", container, "TOPLEFT", 2, 0)
    editbox:SetFontObject(GameFontHighlightSmall)
    editbox:SetAutoFocus(false)
    editbox:SetMaxLetters(256)
    local bg = CreateFrame("Frame", nil, editbox)
    bg:SetPoint("TOPLEFT", editbox, "TOPLEFT", -4, 2)
    bg:SetPoint("BOTTOMRIGHT", editbox, "BOTTOMRIGHT", 4, -2)
    bg:SetBackdrop(sectionBackdrop)
    bg:SetBackdropColor(0.05, 0.05, 0.1, 0.9)
    bg:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.8)
    bg:SetFrameLevel(editbox:GetFrameLevel() - 1)
    editbox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    editbox:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    container.editbox = editbox
    return container
end

----------------------------------------------
-- Channel Row Helper
-- Creates: [x] Channel Name    [x] Random Insults
----------------------------------------------

local function CreateChannelRow(parent, name, label, tooltip, yPos, outputKey, insultKey)
    local cbChannel = CreateCB(name, parent, label, tooltip,
        function(checked) ParryDeezNutsDB[outputKey] = checked end)
    cbChannel:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yPos)

    local cbInsult = CreateCB(name .. "Insult", parent,
        "|cffff8800Random Insults|r",
        "Use random R-rated insults instead of the custom message for this channel.",
        function(checked) ParryDeezNutsDB[insultKey] = checked end)
    cbInsult:SetPoint("TOPLEFT", parent, "TOPLEFT", 200, yPos)

    return cbChannel, cbInsult
end

----------------------------------------------
-- Main Options Frame
----------------------------------------------

local optionsFrame = nil

local function CreateOptionsFrame()
    if optionsFrame then return optionsFrame end

    local f = CreateFrame("Frame", "ParryDeezNutsOptionsFrame", UIParent)
    f:SetWidth(420)
    f:SetHeight(460)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetBackdrop(glassBackdrop)
    f:SetBackdropColor(0.05, 0.02, 0.08, 0.92)
    f:SetBackdropBorderColor(0.6, 0.2, 0.2, 0.9)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(32)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    titleBar:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", tile = true, tileSize = 16 })
    titleBar:SetBackdropColor(0.15, 0.02, 0.02, 0.8)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText("|cffff4444Parry|cffffffffDeez|cffff4444Nuts|r |cff888888v1.2.0|r")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    table.insert(UISpecialFrames, "ParryDeezNutsOptionsFrame")

    -- Scroll area
    local scrollFrame = CreateFrame("ScrollFrame", "PDN_OptScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -38)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 10)

    local content = CreateFrame("Frame", "PDN_OptContent", scrollFrame)
    content:SetWidth(370)
    content:SetHeight(1050)
    scrollFrame:SetScrollChild(content)

    -- Enable mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function()
        local current = scrollFrame:GetVerticalScroll()
        local maxScroll = content:GetHeight() - scrollFrame:GetHeight()
        local step = 40
        if arg1 > 0 then
            scrollFrame:SetVerticalScroll(math.max(0, current - step))
        else
            scrollFrame:SetVerticalScroll(math.min(maxScroll, current + step))
        end
    end)

    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function()
        local current = scrollFrame:GetVerticalScroll()
        local maxScroll = content:GetHeight() - scrollFrame:GetHeight()
        local step = 40
        if arg1 > 0 then
            scrollFrame:SetVerticalScroll(math.max(0, current - step))
        else
            scrollFrame:SetVerticalScroll(math.min(maxScroll, current + step))
        end
    end)

    -- Forward declarations for save function
    local cbMinimap, thrSlider

    local yPos = -6

    -- ============ GENERAL ============
    CreateSectionHeader(content, "General Settings", yPos)
    yPos = yPos - 22

    local cbEnabled = CreateCB("Enabled", content, "Enable Parry Haste Tracking",
        "Master toggle. Only tracks non-tank parries causing boss parry haste.",
        function(checked)
            ParryDeezNutsDB.enabled = checked
            if checked then ParryDeezNuts.Enable() else ParryDeezNuts.Disable() end
        end)
    cbEnabled:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yPos)
    yPos = yPos - 24

    local cbRaidOnly = CreateCB("RaidOnly", content, "Only track in raid/party",
        "Only detect when in a group.",
        function(checked) ParryDeezNutsDB.onlyInRaid = checked end)
    cbRaidOnly:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yPos)
    yPos = yPos - 24

    local cbCombatOnly = CreateCB("CombatOnly", content, "Only track in combat",
        "Only detect while in combat.",
        function(checked) ParryDeezNutsDB.onlyInCombat = checked end)
    cbCombatOnly:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yPos)
    yPos = yPos - 24

    local cbBossOnly = CreateCB("BossOnly", content, "Only track boss mobs (skull level)",
        "Ignore trash parries.",
        function(checked) ParryDeezNutsDB.onlyBosses = checked end)
    cbBossOnly:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yPos)
    yPos = yPos - 24

    local cbOnScreen = CreateCB("OnScreen", content, "Show on-screen warning",
        "Big center-screen text on parry haste.",
        function(checked) ParryDeezNutsDB.showOnScreen = checked end)
    cbOnScreen:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yPos)
    yPos = yPos - 24

    local cbStats = CreateCB("TrackStats", content, "Track all-time statistics",
        "Persistent offender leaderboard.",
        function(checked) ParryDeezNutsDB.trackStats = checked end)
    cbStats:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yPos)
    yPos = yPos - 32

    -- ============ TANK EXCLUSION ============
    CreateSectionHeader(content, "Tank Exclusion (Who NOT to report)", yPos)
    yPos = yPos - 18

    local tankNote = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tankNote:SetPoint("TOPLEFT", content, "TOPLEFT", 14, yPos)
    tankNote:SetWidth(340)
    tankNote:SetTextColor(0.6, 0.6, 0.6, 1)
    tankNote:SetText("Tanks attack from the front - their parries are expected and filtered out. Only DPS in front of the boss get reported.")
    yPos = yPos - 28

    local cbExSelf = CreateCB("ExSelf", content, "Exclude myself (I am the tank)",
        "Your own parries are expected and ignored.",
        function(checked) ParryDeezNutsDB.excludeSelf = checked end)
    cbExSelf:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yPos)
    yPos = yPos - 24

    local cbExTT = CreateCB("ExTT", content, "Auto-detect tank via targettarget",
        "Checks who the boss is targeting and excludes them. Handles tank swaps.",
        function(checked) ParryDeezNutsDB.excludeTargetTarget = checked end)
    cbExTT:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yPos)
    yPos = yPos - 26

    local tankListLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tankListLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 14, yPos)
    tankListLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    tankListLabel:SetText("Manual tank exclude list (off-tanks):")
    yPos = yPos - 16

    local tankListFrame = CreateFrame("Frame", "PDN_TankList", content)
    tankListFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    tankListFrame:SetWidth(340)
    tankListFrame:SetHeight(40)
    tankListFrame:SetBackdrop(sectionBackdrop)
    tankListFrame:SetBackdropColor(0.03, 0.03, 0.06, 0.85)
    tankListFrame:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.7)

    local tankListText = tankListFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tankListText:SetPoint("TOPLEFT", tankListFrame, "TOPLEFT", 6, -4)
    tankListText:SetWidth(326)
    tankListText:SetJustifyH("LEFT")
    tankListText:SetTextColor(0.7, 0.7, 0.7, 1)
    yPos = yPos - 46

    local tankInput = CreateEB("TankName", content, 180)
    tankInput:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yPos)

    local addTankBtn = CreateFrame("Button", "PDN_AddTank", content, "UIPanelButtonTemplate")
    addTankBtn:SetWidth(55)
    addTankBtn:SetHeight(22)
    addTankBtn:SetPoint("LEFT", tankInput, "RIGHT", 8, -2)
    addTankBtn:SetText("Add")

    local rmTankBtn = CreateFrame("Button", "PDN_RmTank", content, "UIPanelButtonTemplate")
    rmTankBtn:SetWidth(55)
    rmTankBtn:SetHeight(22)
    rmTankBtn:SetPoint("LEFT", addTankBtn, "RIGHT", 4, 0)
    rmTankBtn:SetText("Remove")

    local function RefreshTankList()
        if not ParryDeezNutsDB.tankExcludeList or getn(ParryDeezNutsDB.tankExcludeList) == 0 then
            tankListText:SetText("|cff666666(empty - self + targettarget auto-excluded)|r")
        else
            local names = ""
            for i, name in ipairs(ParryDeezNutsDB.tankExcludeList) do
                if i > 1 then names = names .. ", " end
                names = names .. "|cff00ff00" .. tostring(name) .. "|r"
            end
            tankListText:SetText(names)
        end
    end

    addTankBtn:SetScript("OnClick", function()
        local name = tankInput.editbox:GetText()
        if name and name ~= "" then
            if not ParryDeezNutsDB.tankExcludeList then ParryDeezNutsDB.tankExcludeList = {} end
            local found = false
            for _, e in ipairs(ParryDeezNutsDB.tankExcludeList) do
                if S_LOWER(e) == S_LOWER(name) then found = true break end
            end
            if not found then table.insert(ParryDeezNutsDB.tankExcludeList, name) end
            tankInput.editbox:SetText("")
            RefreshTankList()
        end
    end)

    rmTankBtn:SetScript("OnClick", function()
        local name = tankInput.editbox:GetText()
        if name and name ~= "" then
            local newList = {}
            for _, e in ipairs(ParryDeezNutsDB.tankExcludeList or {}) do
                if S_LOWER(e) ~= S_LOWER(name) then table.insert(newList, e) end
            end
            ParryDeezNutsDB.tankExcludeList = newList
            tankInput.editbox:SetText("")
            RefreshTankList()
        end
    end)

    yPos = yPos - 32

    -- ============ OUTPUT CHANNELS ============
    CreateSectionHeader(content, "Output Channels", yPos)
    yPos = yPos - 18

    -- Column headers
    local chLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 36, yPos)
    chLabel:SetText("|cffccccccChannel|r")
    chLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    local insLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    insLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 224, yPos)
    insLabel:SetText("|cffff8800Use Insults|r")
    insLabel:SetTextColor(0.7, 0.7, 0.7, 1)
    yPos = yPos - 18

    local cbLocal, cbInsLocal = CreateChannelRow(content, "Local",
        "Local chat frame",
        "Print to your chat frame (only you see this).",
        yPos, "outputLocal", "insultLocal")
    yPos = yPos - 24

    local cbYell, cbInsYell = CreateChannelRow(content, "Yell",
        "/yell - Yell it",
        "Yell the message so nearby players see it.",
        yPos, "outputYell", "insultYell")
    yPos = yPos - 24

    local cbRaid, cbInsRaid = CreateChannelRow(content, "Raid",
        "/raid - Raid chat",
        "Send to raid chat.",
        yPos, "outputRaid", "insultRaid")
    yPos = yPos - 24

    local cbRW, cbInsRW = CreateChannelRow(content, "RW",
        "/rw - Raid Warning",
        "Raid warning (requires leader/assist). Falls back to raid chat otherwise.",
        yPos, "outputRaidWarning", "insultRaidWarning")
    yPos = yPos - 24

    local cbWhisper, cbInsWhisper = CreateChannelRow(content, "Whisper",
        "/whisper the offender",
        "Auto-whisper the player who caused parry haste.",
        yPos, "outputWhisper", "insultWhisper")
    yPos = yPos - 32

    -- ============ CUSTOM MESSAGE ============
    CreateSectionHeader(content, "Custom Message (when insults disabled)", yPos)
    yPos = yPos - 18

    local msgHint = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    msgHint:SetPoint("TOPLEFT", content, "TOPLEFT", 14, yPos)
    msgHint:SetTextColor(0.6, 0.6, 0.6, 1)
    msgHint:SetText("Use %p for offender's name. Used when 'Random Insults' is unchecked.")
    yPos = yPos - 16

    local msgBox = CreateEB("Message", content, 330)
    msgBox:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yPos)
    yPos = yPos - 30

    local previewBtn = CreateFrame("Button", "PDN_Preview", content, "UIPanelButtonTemplate")
    previewBtn:SetWidth(80)
    previewBtn:SetHeight(22)
    previewBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 14, yPos)
    previewBtn:SetText("Preview")
    previewBtn:SetScript("OnClick", function()
        local msg = msgBox.editbox:GetText()
        if msg and msg ~= "" then ParryDeezNutsDB.message = msg end
        local preview = S_GSUB(ParryDeezNutsDB.message or "%p parry hasted me!", "%%p", UnitName("player") or "TestDPS")
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_COLOR .. "[Preview]|r " .. tostring(preview))
    end)

    local saveBtn = CreateFrame("Button", "PDN_Save", content, "UIPanelButtonTemplate")
    saveBtn:SetWidth(80)
    saveBtn:SetHeight(22)
    saveBtn:SetPoint("LEFT", previewBtn, "RIGHT", 6, 0)
    saveBtn:SetText("Save All")
    saveBtn:SetScript("OnClick", function()
        local db = ParryDeezNutsDB
        -- General
        db.enabled = cbEnabled:GetChecked() and true or false
        db.onlyInRaid = cbRaidOnly:GetChecked() and true or false
        db.onlyInCombat = cbCombatOnly:GetChecked() and true or false
        db.onlyBosses = cbBossOnly:GetChecked() and true or false
        db.showOnScreen = cbOnScreen:GetChecked() and true or false
        db.trackStats = cbStats:GetChecked() and true or false
        -- Tank exclusion
        db.excludeSelf = cbExSelf:GetChecked() and true or false
        db.excludeTargetTarget = cbExTT:GetChecked() and true or false
        -- Channels
        db.outputLocal = cbLocal:GetChecked() and true or false
        db.outputYell = cbYell:GetChecked() and true or false
        db.outputRaid = cbRaid:GetChecked() and true or false
        db.outputRaidWarning = cbRW:GetChecked() and true or false
        db.outputWhisper = cbWhisper:GetChecked() and true or false
        -- Insults
        db.insultLocal = cbInsLocal:GetChecked() and true or false
        db.insultYell = cbInsYell:GetChecked() and true or false
        db.insultRaid = cbInsRaid:GetChecked() and true or false
        db.insultRaidWarning = cbInsRW:GetChecked() and true or false
        db.insultWhisper = cbInsWhisper:GetChecked() and true or false
        -- Minimap
        db.showMinimap = cbMinimap:GetChecked() and true or false
        -- Message
        local msg = msgBox.editbox:GetText()
        if msg and msg ~= "" then db.message = msg end
        -- Throttle
        db.throttleSeconds = floor(thrSlider:GetValue() + 0.5)
        -- Apply enable/disable
        if db.enabled then ParryDeezNuts.Enable() else ParryDeezNuts.Disable() end
        if ParryDeezNuts.minimapButton then
            if db.showMinimap then ParryDeezNuts.minimapButton:Show()
            else ParryDeezNuts.minimapButton:Hide() end
        end
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_COLOR .. "[ParryDeezNuts]|r Settings saved!", 0.5, 1, 0.5)
    end)

    local defBtn = CreateFrame("Button", "PDN_Default", content, "UIPanelButtonTemplate")
    defBtn:SetWidth(80)
    defBtn:SetHeight(22)
    defBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
    defBtn:SetText("Default")
    defBtn:SetScript("OnClick", function()
        ParryDeezNutsDB.message = "%p parry hasted me! Fuck that guy!"
        msgBox.editbox:SetText(ParryDeezNutsDB.message)
    end)

    -- Preview insult button
    local insPreview = CreateFrame("Button", "PDN_InsPreview", content, "UIPanelButtonTemplate")
    insPreview:SetWidth(120)
    insPreview:SetHeight(22)
    insPreview:SetPoint("LEFT", defBtn, "RIGHT", 6, 0)
    insPreview:SetText("Test Insult")
    insPreview:SetScript("OnClick", function()
        local insult = ParryDeezNuts.GetRandomInsult(UnitName("player") or "TestDPS")
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_COLOR .. "[Insult Preview]|r " .. tostring(insult))
    end)

    yPos = yPos - 34

    -- ============ THROTTLE ============
    CreateSectionHeader(content, "Throttle", yPos)
    yPos = yPos - 22

    local thrLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thrLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 14, yPos)
    thrLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    thrLabel:SetText("Seconds between announcements per player:")
    yPos = yPos - 4

    thrSlider = CreateFrame("Slider", "PDN_ThrottleSlider", content, "OptionsSliderTemplate")
    thrSlider:SetWidth(200)
    thrSlider:SetHeight(17)
    thrSlider:SetPoint("TOPLEFT", content, "TOPLEFT", 14, yPos - 14)
    thrSlider:SetMinMaxValues(0, 15)
    thrSlider:SetValueStep(1)
    -- SetObeyStepOnDrag not available in 1.12.1
    _G["PDN_ThrottleSliderLow"]:SetText("0s")
    _G["PDN_ThrottleSliderHigh"]:SetText("15s")
    thrSlider:SetScript("OnValueChanged", function()
        local val = floor(this:GetValue() + 0.5)
        _G["PDN_ThrottleSliderText"]:SetText(tostring(val) .. "s")
        ParryDeezNutsDB.throttleSeconds = val
    end)
    yPos = yPos - 50

    -- ============ MINIMAP ============
    CreateSectionHeader(content, "Minimap", yPos)
    yPos = yPos - 22

    cbMinimap = CreateCB("Minimap", content, "Show minimap button",
        "Toggle minimap button visibility.",
        function(checked)
            ParryDeezNutsDB.showMinimap = checked
            if ParryDeezNuts.minimapButton then
                if checked then ParryDeezNuts.minimapButton:Show()
                else ParryDeezNuts.minimapButton:Hide() end
            end
        end)
    cbMinimap:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yPos)
    yPos = yPos - 32

    -- ============ STATS ============
    CreateSectionHeader(content, "All-Time Statistics (non-tanks only)", yPos)
    yPos = yPos - 20

    local statsFrame = CreateFrame("Frame", "PDN_StatsFrame", content)
    statsFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 10, yPos)
    statsFrame:SetWidth(348)
    statsFrame:SetHeight(140)
    statsFrame:SetBackdrop(sectionBackdrop)
    statsFrame:SetBackdropColor(0.03, 0.03, 0.06, 0.85)
    statsFrame:SetBackdropBorderColor(0.4, 0.15, 0.15, 0.7)

    local statsLines = {}
    for i = 1, 8 do
        local line = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        line:SetPoint("TOPLEFT", statsFrame, "TOPLEFT", 8, -6 - ((i - 1) * 16))
        line:SetWidth(330)
        line:SetJustifyH("LEFT")
        line:SetTextColor(0.8, 0.8, 0.8, 1)
        statsLines[i] = line
    end
    yPos = yPos - 150

    local function RefreshStats()
        for i = 1, 8 do statsLines[i]:SetText("") end
        if not ParryDeezNutsDB.stats or not next(ParryDeezNutsDB.stats) then
            statsLines[1]:SetText("|cff666666No data yet.|r")
            return
        end
        local list = {}
        for name, count in pairs(ParryDeezNutsDB.stats) do
            table.insert(list, { name = name, count = count })
        end
        for i = 1, getn(list) do
            for j = i + 1, getn(list) do
                if list[j].count > list[i].count then
                    local t = list[i]; list[i] = list[j]; list[j] = t
                end
            end
        end
        for i = 1, math.min(getn(list), 7) do
            local e = list[i]
            local bar = ""
            local pct = e.count / list[1].count
            for b = 1, floor(pct * 20) do bar = bar .. "|" end
            statsLines[i]:SetText("|cffffd700" .. tostring(i) .. ".|r |cffff6666" .. tostring(e.name) .. "|r  |cffaaaaaa" .. bar .. "|r  |cffffffff" .. tostring(e.count) .. "|r")
        end
        local total = 0
        for _, e in ipairs(list) do total = total + e.count end
        statsLines[8]:SetText("|cffffd700Total:|r |cffffffff" .. tostring(total) .. " parries|r from |cffffffff" .. tostring(getn(list)) .. " offenders|r")
    end

    local refreshBtn = CreateFrame("Button", "PDN_Refresh", content, "UIPanelButtonTemplate")
    refreshBtn:SetWidth(80)
    refreshBtn:SetHeight(22)
    refreshBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 14, yPos)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function() RefreshStats() end)

    local resetBtn = CreateFrame("Button", "PDN_ResetStats", content, "UIPanelButtonTemplate")
    resetBtn:SetWidth(80)
    resetBtn:SetHeight(22)
    resetBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 6, 0)
    resetBtn:SetText("Reset")
    resetBtn:SetScript("OnClick", function()
        ParryDeezNutsDB.stats = {}
        RefreshStats()
    end)

    yPos = yPos - 30

    local testBtn = CreateFrame("Button", "PDN_Test", content, "UIPanelButtonTemplate")
    testBtn:SetWidth(200)
    testBtn:SetHeight(26)
    testBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 85, yPos)
    testBtn:SetText("Fire Test Parry Event")
    testBtn:SetScript("OnClick", function()
        SlashCmdList["PARRYDEEZ"]("test")
    end)

    -- ============ LOAD SETTINGS ============

    local function LoadSettings()
        local db = ParryDeezNutsDB
        cbEnabled:SetChecked(db.enabled)
        cbRaidOnly:SetChecked(db.onlyInRaid)
        cbCombatOnly:SetChecked(db.onlyInCombat)
        cbBossOnly:SetChecked(db.onlyBosses)
        cbOnScreen:SetChecked(db.showOnScreen)
        cbStats:SetChecked(db.trackStats)
        cbExSelf:SetChecked(db.excludeSelf)
        cbExTT:SetChecked(db.excludeTargetTarget)
        -- Channels
        cbLocal:SetChecked(db.outputLocal)
        cbYell:SetChecked(db.outputYell)
        cbRaid:SetChecked(db.outputRaid)
        cbRW:SetChecked(db.outputRaidWarning)
        cbWhisper:SetChecked(db.outputWhisper)
        -- Insult toggles
        cbInsLocal:SetChecked(db.insultLocal)
        cbInsYell:SetChecked(db.insultYell)
        cbInsRaid:SetChecked(db.insultRaid)
        cbInsRW:SetChecked(db.insultRaidWarning)
        cbInsWhisper:SetChecked(db.insultWhisper)
        -- Other
        cbMinimap:SetChecked(db.showMinimap)
        msgBox.editbox:SetText(db.message or "%p parry hasted me! Fuck that guy!")
        thrSlider:SetValue(db.throttleSeconds or 3)
        _G["PDN_ThrottleSliderText"]:SetText(tostring(db.throttleSeconds or 3) .. "s")
        RefreshTankList()
        RefreshStats()
    end

    f:SetScript("OnShow", function() LoadSettings() end)
    f:Hide()
    optionsFrame = f
    return f
end

function ParryDeezNuts.ToggleOptions()
    local f = CreateOptionsFrame()
    if f:IsShown() then f:Hide() else f:Show() end
end
