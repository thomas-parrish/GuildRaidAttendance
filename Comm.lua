local GRA, gra = unpack(select(2, ...))
local L = select(2, ...).L

local Serializer = LibStub:GetLibrary("AceSerializer-3.0")
local Comm = LibStub:GetLibrary("AceComm-3.0")
local Compresser = LibStub:GetLibrary("LibCompress")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local LibSerialize = LibStub("LibSerialize")
local configForLS = {
    errorOnUnserializableType =  false
  }
local configForDeflate = {level = 9} -- the biggest bottleneck by far is in transmission and printing; so use maximal compression

-- from WeakAuras
local compressedTablesCache = {}

function TableToString(inTable)
    local serialized = LibSerialize:SerializeEx(configForLS, inTable)
    local compressed
    
    -- get from / add to cache
    if compressedTablesCache[serialized] then
      compressed = compressedTablesCache[serialized].compressed
      compressedTablesCache[serialized].lastAccess = time()
    else
      compressed = LibDeflate:CompressDeflate(serialized, configForDeflate)
      compressedTablesCache[serialized] = {
        compressed = compressed,
        lastAccess = time(),
      }
    end
    
    -- remove cache items after 5 minutes
    for k, v in pairs(compressedTablesCache) do
      if v.lastAccess < (time() - 300) then
        compressedTablesCache[k] = nil
      end
    end

    local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
    print(encoded)
    return encoded
  end

function StringToTable(inString)
    decoded = LibDeflate:DecodeForWoWAddonChannel(inString)
    if not decoded then
      return "Error decoding."
    end
  
    local decompressed, errorMsg = nil, "unknown compression method"
    decompressed = LibDeflate:DecompressDeflate(decoded)
    if not(decompressed) then
      return "Error decompressing: " .. errorMsg
    end

    local success, deserialized
    success, deserialized = LibSerialize:Deserialize(decompressed)
    if not(success) then
      return "Error deserializing "..deserialized
    end

    return deserialized
  end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

local sendChannel
local function UpdateSendChannel()
    if IsInRaid() then
        sendChannel = "RAID"
    else
        sendChannel = "PARTY"
    end
end

-----------------------------------------
-- send roster
-----------------------------------------
local receiveRosterPopup, sendRosterPopup, rosterAccepted, rosterReceived, receivedRoster
local function OnRosterReceived()
    if rosterAccepted and rosterReceived and receivedRoster then
        _G[GRA_R_Roster] = receivedRoster[1]
        _G[GRA_R_Config]["raidInfo"] = receivedRoster[2]

        GRA:FireEvent("GRA_R_DONE")
        wipe(receivedRoster)
    end
end

-- send roster data and raidInfo to raid members
function GRA:SendRosterToRaid()
    UpdateSendChannel()
    Comm:SendCommMessage("GRA_R_ASK", " ", sendChannel, nil, "ALERT")
    sendRosterPopup = nil
    gra.sending = true

    local encoded = TableToString({_G[GRA_R_Roster], _G[GRA_R_Config]["raidInfo"]})
    
    -- send roster
    Comm:SendCommMessage("GRA_R_SEND", encoded, sendChannel, nil, "BULK", function(arg, done, total)
        if not sendRosterPopup then
            sendRosterPopup = GRA:CreateDataTransferPopup(gra.colors.chartreuse.s..L["Sending roster data"], total, function()
                gra.sending = false
            end)
        end
        sendRosterPopup:SetValue(done)
        -- send progress
        Comm:SendCommMessage("GRA_R_PROG", done.."|"..total, sendChannel, nil, "ALERT")
    end)
end

-- whether to revieve
Comm:RegisterComm("GRA_R_ASK", function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end

    rosterAccepted = false
    rosterReceived = false

    GRA:CreateStaticPopup(L["Receive Raid Roster"], L["Receive roster data from %s?"]:format(GRA:GetClassColoredName(sender, select(2, UnitClass(sender)))),
    function()
        rosterAccepted = true
        OnRosterReceived() -- maybe already received

        -- if receving then hide it immediately
        if receiveRosterPopup then receiveRosterPopup:Hide() end
        -- init
        receiveRosterPopup = nil
    end, function()
        rosterAccepted = false
    end)
end)

-- recieve roster finished
Comm:RegisterComm("GRA_R_SEND", function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end
    
    receivedRoster = StringToTable(message)
    rosterReceived = true
    OnRosterReceived()
end)

-- recieve roster progress
Comm:RegisterComm("GRA_R_PROG", function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end
    
    if not rosterAccepted then return end

    local done, total = strsplit("|", message)
    done, total = tonumber(done), tonumber(total)
    if not receiveRosterPopup then
        receiveRosterPopup = GRA:CreateDataTransferPopup(L["Receiving roster data from %s"]:format(GRA:GetClassColoredName(sender, select(2, UnitClass(sender)))), total)
    end
    -- progress bar
    receiveRosterPopup:SetValue(done)
end)

-----------------------------------------
-- send logs
-----------------------------------------
local receiveLogsPopup, sendLogsPopup, logsAccepted, logsReceived, receivedLogs
local dates
local function OnLogsReceived()
    -- TODO: version mismatch warning
    if logsAccepted and logsReceived and receivedLogs then
        for d, tbl in pairs(receivedLogs[1]) do
            _G[GRA_R_RaidLogs][d] = tbl
        end
        -- TODO: send AR only, not all _G[GRA_R_Roster]
        _G[GRA_R_Roster] = receivedLogs[2]
        -- tell addon to show logs
        GRA:FireEvent("GRA_LOGS_DONE", GRA:Getn(receivedLogs[1]), dates)
        wipe(receivedLogs)
    end
end

function GRA:SendLogsToRaid(selectedDates)
    dates = selectedDates
    local encoded = TableToString(selectedDates)
    UpdateSendChannel()
    Comm:SendCommMessage("GRA_LOGS_ASK", encoded, sendChannel, nil, "ALERT")
    sendLogsPopup = nil
    gra.sending = true

    local t = {}
    for _, d in pairs(selectedDates) do
        t[d] = _G[GRA_R_RaidLogs][d]
    end
    -- TODO: send AR only, not all _G[GRA_R_Roster]
    encoded = TableToString({t, _G[GRA_R_Roster]})
    
    -- send logs
    Comm:SendCommMessage("GRA_LOGS_SEND", encoded, sendChannel, nil, "BULK", function(arg, done, total)
        if not sendLogsPopup then
            sendLogsPopup = GRA:CreateDataTransferPopup(gra.colors.chartreuse.s..L["Sending raid logs data"], total, function()
                gra.sending = false
            end)
        end
        sendLogsPopup:SetValue(done)
        -- send progress
        Comm:SendCommMessage("GRA_LOGS_PROG", done.."|"..total, sendChannel, nil, "ALERT")
    end)
end

-- whether to revieve
Comm:RegisterComm("GRA_LOGS_ASK", function(prefix, message, channel, sender)
    if sender == UnitName("player") or GRA_Variables["minimalMode"] then return end

    logsAccepted = false
    logsReceived = false

    dates = StringToTable(message)
    GRA:CreateStaticPopup(L["Receive Raid Logs"], L["Receive raid logs data from %s?"]:format(GRA:GetClassColoredName(sender, select(2, UnitClass(sender)))) .. "\n" ..
    GRA:TableToString(dates), -- TODO: text format
    function()
        logsAccepted = true
        OnLogsReceived()

        -- if receving then hide it immediately
        if receiveLogsPopup then receiveLogsPopup:Hide() end
        -- init
        receiveLogsPopup = nil
    end, function()
        logsAccepted = false
    end)
end)

-- "recieve logs data" finished
Comm:RegisterComm("GRA_LOGS_SEND", function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end

    receivedLogs = StringToTable(message)
    logsReceived = true
    OnLogsReceived()
end)

-- "recieve logs data" progress
Comm:RegisterComm("GRA_LOGS_PROG", function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end

    if not logsAccepted then return end

    local done, total = strsplit("|", message)
    done, total = tonumber(done), tonumber(total)
    if not receiveLogsPopup then
        -- UnitClass(name) is available for raid/party members
        receiveLogsPopup = GRA:CreateDataTransferPopup(L["Receiving raid logs data from %s"]:format(GRA:GetClassColoredName(sender, select(2, UnitClass(sender)))), total)
    end
    -- progress bar
    receiveLogsPopup:SetValue(done)
end)

-----------------------------------------
-- hide data transfer popup when leave group
-----------------------------------------
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
function eventFrame:GROUP_ROSTER_UPDATE()
    if not IsInGroup("LE_PARTY_CATEGORY_HOME") then
        if receiveRosterPopup then receiveRosterPopup.fadeOut:Play() end
        if receiveLogsPopup then receiveLogsPopup.fadeOut:Play() end
    end
end

-----------------------------------------
-- Check Version
-----------------------------------------
local versionChecked = false
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
function eventFrame:PLAYER_ENTERING_WORLD()
    eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if IsInGuild() then
        Comm:SendCommMessage("GRA_VERSION", gra.version, "GUILD", nil, "BULK")
    end
end

Comm:RegisterComm("GRA_VERSION", function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end
    if not versionChecked and gra.version < message then
        versionChecked = true
        GRA:Print(L["New version found (%s). Please visit %s to get the latest version."]:format(message, gra.colors.skyblue.s .. "https://www.curseforge.com/wow/addons/guild-raid-attendance|r"))
    end
end)

-----------------------------------------
-- popup message
-----------------------------------------
function GRA:SendEntryMsg(msgType, name, value, reason)
    if UnitIsConnected(GRA:GetShortName(name)) then
        Comm:SendCommMessage("GRA_MSG", "|cff80FF00" .. msgType .. ":|r " .. value
        .. "  |cff80FF00" .. L["Reason"] .. ":|r " .. reason, "WHISPER", name, "ALERT")
    end
end

Comm:RegisterComm("GRA_MSG", function(prefix, message, channel, sender)
    GRA:CreatePopup(message)
end)