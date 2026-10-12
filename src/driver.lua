--[[=============================================================================
    DirectorLink · Android TV Notifications for Control4 - DriverWorks driver
    https://directorlink.io/drivers/android-tv

    Shows notifications as a pop-up, with a picture (who is at the door or
    the gate), on a TV that runs Google TV, Android TV or Fire TV, on the
    home network only. One driver per TV. The TV runs one of two free apps
    that take pop-ups over the network (tvapp.lua): "Notifications for
    Android TV" (Google Play, Amazon Appstore) or PiPup.

      - What it shows: DirectorLink's notifications (the DirectorLink
        notification agreement, version 1: DIRECTORLINK_NOTIFY), the Show
        Notification command, and the Test Notification action
        (notify.lua): only the kinds switched on, nothing during Quiet Hours,
        at most one pop-up every 5 seconds, a doorbell or the alarm first.
      - The picture: the notification's PICTURE (or Show Notification's
        Picture URL), fetched by the TV from its address, when Pictures is On.
      - Off, or no answer within 3 seconds: the pop-up is dropped with one log
        line. The driver never turns the TV on.
      - Finding TVs: an SSDP search for casting devices (ssdp.lua), each asked
        whether the app answers; or the TV's IP address typed in.

    DirectorLink notification agreement v1: variables DIRECTORLINK_NOTIFY = "1"
    and DIRECTORLINK_NOTIFY_KINDS (the kinds switched on, from doorbell,
    camera, door, alarm, other), written at every start and the kinds again at
    every change; the command DIRECTORLINK_NOTIFY (VERSION, ID, KIND, TITLE,
    MESSAGE, PICTURE), by ExecuteCommand or ReceivedFromProxy.

    Copyright 2026 DirectorLink
    SPDX-License-Identifier: Apache-2.0
    DirectorLink is an independent project, not affiliated with Control4 or Snap One.
    Not affiliated with or endorsed by Google, Amazon or the makers of the TV apps it works with.
    Android TV, Google TV and Fire TV are trademarks of their owners.
===============================================================================]]

LOG_PREFIX = "Android TV"
AGREEMENT_VERSION = 1
TEST_TEXT = { title = "Control4", message = "Test: pop-ups from Control4 work on this TV." }
FIND_PROBE_S = 2

gState = { savedVars = {}, quietOk = true, foundAt = nil, found = {}, savedHost = nil, savedApp = nil }

--[[=============================================================================
    Saved state
    DL_TV: the address and app the rest applies to, whether the app answered
    there, and what PiPup said about the TV. DL_VARS: LAST_NOTIFICATION.
===============================================================================]]
function SaveState()
	StoreSet("DL_TV", JsonObject({
		host = gTv.host, app = gTv.app, seen = gTv.seenHere and gTv.host or nil,
		info = JsonObject({ name = gTv.info.name, model = gTv.info.model, maker = gTv.info.maker, android = gTv.info.android }),
	}))
end

local function LoadState()
	local s = StoreGet("DL_TV")
	if type(s) ~= "table" then return end
	local host, app = JsonField(s, "host"), JsonField(s, "app")
	gState.savedHost = type(host) == "string" and host or ""
	gState.savedApp = TV_APPS[app] and app or nil
	gState.seenHost = JsonField(s, "seen")
	local info = JsonField(s, "info")
	if type(info) == "table" then
		gState.savedInfo = {}
		for _, k in ipairs({ "name", "model", "maker", "android" }) do
			local v = JsonField(info, k)
			if type(v) == "string" then gState.savedInfo[k] = v end
		end
	end
end

local function SaveVars()
	StoreSet("DL_VARS", JsonObject({ LAST_NOTIFICATION = GetVar("LAST_NOTIFICATION") or "" }))
end

local function LoadVars()
	local v = StoreGet("DL_VARS")
	if type(v) == "table" then gState.savedVars = v end
end

--[[=============================================================================
    Status and properties
===============================================================================]]
local function SetLogPrefix()
	local name
	pcall(function() name = C4:GetDeviceDisplayName(MyDeviceId()) end)
	LOG_PREFIX = "Android TV" .. ((type(name) == "string" and name ~= "") and (" '" .. name .. "'") or "")
end

local function AppFromProperty()
	return TV_APP_BY_NAME[Properties["TV App"] or ""] or "nfa"
end

function StatusText()
	local text
	local app = TvApp()
	local s = gTv.state
	if not ValidAddress(gTv.host) then
		text = "Enter the TV's IP address, or pick it in TVs Found"
	elseif s == "ready" then
		text = "Ready"
	elseif s == "off" then
		text = "Off"
	elseif s == "nooverlay" then
		text = "PiPup may not show pop-ups: allow it to display over other apps (or run its install script again)"
	elseif s == "noapp" then
		text = gTv.app == "pipup" and "The TV answers, but PiPup does not: install it with its script"
			or ("The TV answers, but " .. app.name .. " does not: install it and open it once on the TV")
	elseif s == "unreachable" then
		text = gTv.seenHere and "Off" or "Not reachable"
	else
		text = "Checking..."
	end
	if not gState.quietOk then text = text .. " - Quiet Hours not understood: write it as 22:00-07:00" end
	return text
end

-- "Living Room TV · Sony BRAVIA 4K GB · Android 12 · PiPup 0.26.1" (PiPup says it), else the app
function TvText()
	local parts = {}
	local i = gTv.info
	if i.name and i.name ~= "" then parts[#parts + 1] = i.name end
	local device = trim((i.maker or "") .. " " .. (i.model or ""))
	if device ~= "" then parts[#parts + 1] = device end
	if i.android then parts[#parts + 1] = "Android " .. i.android end
	parts[#parts + 1] = TvApp().name .. (i.version and (" " .. i.version) or "")
	return table.concat(parts, " · ")
end

function UpdateStatus()
	local status = StatusText()
	if status ~= Properties["Status"] then LogDebug("Status: %s", status) end
	UpdateProperty("Status", status)
	UpdateProperty("TV", ValidAddress(gTv.host) and TvText() or "")
end

-- From tvapp.lua: the state of the TV or what it said about itself changed
function TvChanged()
	local seen = gTv.seenHere and gTv.host or nil
	local key = tostring(gTv.info.name) .. "|" .. tostring(gTv.info.model) .. "|" .. tostring(gTv.info.android)
	if seen ~= gState.seenHost or key ~= gState.savedInfoKey then
		gState.seenHost, gState.savedInfoKey = seen, key
		SaveState()
	end
	UpdateStatus()
end

function NotifyChanged()
	SaveVars()
end

local function SetKindsVariable()
	SetVar("DIRECTORLINK_NOTIFY_KINDS", KindsText())
end

local function CheckQuietHours()
	local text = Properties["Quiet Hours"] or ""
	local from, to = ParseQuietHours(text)
	gState.quietOk = from ~= false
	if from == false then
		LogWarn("Quiet Hours '%s' not understood: write it as from-to, for example 22:00-07:00 (none until then)", text)
	elseif from then
		local normal = MinutesText(from) .. "-" .. MinutesText(to)
		if normal ~= text then UpdateProperty("Quiet Hours", normal) end
	end
	UpdateStatus()
end

--[[=============================================================================
    The TV's address and app
===============================================================================]]
local function ApplyTv(reason)
	local host = trim(Properties["TV IP Address"])
	if host ~= "" and not ValidAddress(host) then
		LogWarn("TV IP Address '%s' is not an address", host)
		host = ""
	end
	local app = AppFromProperty()
	if host == gTv.host and app == gTv.app and gTv.state ~= "idle" then return end
	NotifyFlush("the TV's address or app changed")
	local sameTv = host == gState.savedHost
	gState.savedHost, gState.savedApp = host, app
	if host ~= "" then
		LogInfo("TV %s with %s%s", host, TV_APPS[app].name, reason and (" (" .. reason .. ")") or "")
	end
	TvConfigure(host, app, sameTv)
	SaveState()
	UpdateStatus()
end

--[[=============================================================================
    Finding TVs: the casting devices on the network, each asked whether the app answers
===============================================================================]]
local function FoundItem(dev)
	local name = dev.name or trim((dev.maker or "") .. " " .. (dev.model or ""))
	if name == "" then name = "TV" end
	return name .. " (" .. dev.ip .. ")" .. (dev.app and (" - " .. TvApp().name .. " answers") or "")
end

local function ProbeApp(dev, done)
	local app = TV_APPS[AppFromProperty()]
	local url = "http://" .. dev.ip .. ":" .. app.port .. (app.key == "pipup" and "/state" or "/")
	local over = false
	local function finish(answers)
		if over then return end
		over = true
		dev.app = answers
		done()
	end
	SetTimer("FIND_PROBE_" .. dev.ip, (FIND_PROBE_S + 3) * 1000, function() finish(false) end)
	local ok = pcall(function()
		local x = C4:url()
		x:SetOptions({ fail_on_error = false, timeout = FIND_PROBE_S, connect_timeout = FIND_PROBE_S })
		x:OnDone(function(_, responses, errCode)
			KillTimer("FIND_PROBE_" .. dev.ip)
			finish((errCode == nil or errCode == 0) and responses ~= nil and responses[#responses] ~= nil)
		end)
		x:Get(url, {})
	end)
	if not ok then finish(false) end
end

local function FindTVs()
	LogInfo("Looking for TVs on the network...")
	SsdpSearch(function(found, err)
		if err then return end
		local left = #found
		local function list()
			table.sort(found, function(a, b)
				if (a.app and true or false) ~= (b.app and true or false) then return a.app == true end
				return a.ip < b.ip
			end)
			gState.found, gState.foundAt = found, NowMs()
			local items = { "-" }
			for _, dev in ipairs(found) do items[#items + 1] = FoundItem(dev) end
			UpdatePropertyList("TVs Found", items, "-")
			if #found == 0 then
				LogInfo("Find TVs: no TV answered. A TV answers while it is on; or type its IP address in TV IP Address")
			else
				local names = {}
				for i = 2, #items do names[#names + 1] = items[i] end
				LogInfo("Find TVs: %s. Pick the TV in TVs Found", table.concat(names, ", "))
			end
		end
		if left == 0 then return list() end
		for _, dev in ipairs(found) do
			ProbeApp(dev, function()
				left = left - 1
				if left == 0 then list() end
			end)
		end
	end)
end

local function PickFound()
	local v = Properties["TVs Found"] or "-"
	local ip = string.match(v, "%((%d+%.%d+%.%d+%.%d+)%)")
	if not ip then return end
	if ip ~= trim(Properties["TV IP Address"]) then
		UpdateProperty("TV IP Address", ip)
		ApplyTv("picked in TVs Found")
	end
end

--[[=============================================================================
    Notifications in
===============================================================================]]
-- A parameter whatever the case of its name; nil when missing
local function Param(t, name)
	if type(t) ~= "table" then return nil end
	local v = t[name]
	if v == nil then
		local lname = string.lower(name)
		for k, x in pairs(t) do
			if string.lower(tostring(k)) == lname then v = x break end
		end
	end
	if v == nil then return nil end
	return tostring(v)
end

-- DIRECTORLINK_NOTIFY (the DirectorLink notification agreement, version 1)
function DirectorLinkNotify(tParams, via)
	local version = Param(tParams, "VERSION")
	local v = tonumber(version or "1")
	if not v or v < 1 then
		LogWarn("DIRECTORLINK_NOTIFY with VERSION '%s' (this driver reads version 1): ignored", tostring(version))
		return
	end
	local kind = string.lower(trim(Param(tParams, "KIND") or ""))
	if not KIND_PROPERTY[kind] then
		LogDebug("DIRECTORLINK_NOTIFY with KIND '%s': taken as other", kind)
		kind = "other"
	end
	local id = Param(tParams, "ID")
	LogDebug("DIRECTORLINK_NOTIFY (%s): version %s, id %s, kind %s%s", via, tostring(version or "1"), tostring(id), kind,
		Param(tParams, "PICTURE") and ", with a picture" or "")
	NotifyAccept({
		source = "DirectorLink", id = id, kind = kind,
		title = Param(tParams, "TITLE"), message = Param(tParams, "MESSAGE"), picture = Param(tParams, "PICTURE"),
	})
end

local function ShowNotification(tParams)
	NotifyAccept({
		source = "programming", title = Param(tParams, "Title"), message = Param(tParams, "Message"),
		picture = Param(tParams, "Picture URL"),
	})
end

--[[=============================================================================
    Actions
===============================================================================]]
local function TestNotification()
	if not ValidAddress(gTv.host) then
		LogWarn("Test Notification: enter the TV's IP address first")
		return
	end
	LogInfo("Test Notification: sending a pop-up to the TV")
	NotifyAccept({ source = "test", title = TEST_TEXT.title, message = TEST_TEXT.message })
end

local function PrintDiagnostics()
	local v = ControllerVersion()
	local build = ""
	pcall(function() build = tostring(C4:GetDriverConfigInfo("version") or "") end)
	local quiet = trim(Properties["Quiet Hours"])
	local lines = {
		"===== DirectorLink · Android TV Notifications - diagnostics =====",
		"Driver        : " .. DRIVER_SEMVER .. (build ~= "" and (" (" .. build .. ")") or "") .. " on Control4 OS " .. (v and v.text or "?")
			.. ", device " .. tostring(MyDeviceId()) .. ", controller " .. tostring(ControllerAddress()),
		"Status        : " .. tostring(Properties["Status"]),
		"TV            : " .. (gTv.host ~= "" and (gTv.host .. ":" .. TvApp().port) or "(no address)") .. " - " .. TvText(),
		"App           : " .. TvApp().name .. ", " .. TvStateText()
			.. (gTv.app == "pipup" and (", screen " .. (gTv.screenOn == nil and "?" or (gTv.screenOn and "on" or "off"))
				.. ", may draw over other apps: " .. (gTv.overlay == nil and "?" or (gTv.overlay and "yes" or "NO"))) or ""),
		"Checks        : " .. gTv.checks .. (gTv.lastOkAt and (", last answer " .. ClockText(gTv.lastOkAt)) or ", no answer yet")
			.. (gTv.nextCheckAt and (", next " .. ClockText(gTv.nextCheckAt)) or ""),
		"Last error    : " .. (gTv.lastError and (gTv.lastError .. " at " .. ClockText(gTv.lastErrorAt)) or "none"),
		"Pop-ups       : " .. tostring(Properties["Position"]) .. ", " .. tostring(Properties["Seconds On Screen"]) .. " s, pictures "
			.. tostring(Properties["Pictures"]),
		"Kinds on      : " .. (KindsText() ~= "" and KindsText() or "none"),
		"Quiet Hours   : " .. (quiet ~= "" and (quiet .. (gState.quietOk and (InQuietHours() and " (now)" or " (not now)") or " (NOT UNDERSTOOD)")) or "none")
			.. ", local time " .. os.date("%H:%M"),
		"DirectorLink  : DIRECTORLINK_NOTIFY = " .. tostring(GetVar("DIRECTORLINK_NOTIFY")) .. ", DIRECTORLINK_NOTIFY_KINDS = " .. tostring(GetVar("DIRECTORLINK_NOTIFY_KINDS")),
		"Notifications : " .. gNotify.counts.shown .. " shown, " .. gNotify.counts.failed .. " not shown, " .. gNotify.counts.skipped .. " skipped"
			.. (#gNotify.queue > 0 and (", " .. #gNotify.queue .. " waiting") or "") .. (gNotify.busy and ", one on its way" or ""),
	}
	lines[#lines + 1] = "Last ones     :" .. (#gNotify.history == 0 and " none" or "")
	for _, h in ipairs(gNotify.history) do
		local text = string.gsub(h.text or "", "[\r\n]+", " ")
		if #text > 70 then text = string.sub(text, 1, 70) .. "..." end
		lines[#lines + 1] = "   " .. ClockText(h.at) .. " " .. (h.kind or h.source) .. " '" .. text .. "' - " .. h.result .. (h.why and (" (" .. h.why .. ")") or "")
			.. (h.picture and ", with a picture" or "") .. (h.id and (", id " .. h.id) or "") .. (h.source ~= "DirectorLink" and (", from " .. h.source) or "")
	end
	if gState.foundAt then
		local found = {}
		for _, dev in ipairs(gState.found or {}) do found[#found + 1] = FoundItem(dev) end
		lines[#lines + 1] = "TVs found     : " .. (#found > 0 and table.concat(found, ", ") or "none") .. " (Find TVs at " .. ClockText(gState.foundAt) .. ")"
	end
	lines[#lines + 1] = "Variables     : LAST_NOTIFICATION = '" .. tostring(GetVar("LAST_NOTIFICATION") or "") .. "'"
	lines[#lines + 1] = "================================================================"
	PrintReport(lines)
end

ACTIONS = {
	FindTVs = FindTVs,
	TestNotification = TestNotification,
	PrintDiagnostics = PrintDiagnostics,
}

COMMANDS = {
	SHOW_NOTIFICATION = ShowNotification,
	DIRECTORLINK_NOTIFY = function(tParams) DirectorLinkNotify(tParams, "ExecuteCommand") end,
}

--[[=============================================================================
    DriverWorks entry points
===============================================================================]]
-- Never reorder: Director numbers variables in this order, and DirectorLink reads them.
-- New ones go at the end.
local VARIABLES = {
	{ "LAST_NOTIFICATION", "", "STRING" },
	{ "DIRECTORLINK_NOTIFY", "1", "STRING" },
	{ "DIRECTORLINK_NOTIFY_KINDS", "", "STRING" },
}

function OnDriverInit()
	math.randomseed(os.time())
	LoadState()
	LoadVars()
	local saved = JsonField(gState.savedVars, "LAST_NOTIFICATION")
	for _, v in ipairs(VARIABLES) do
		if v[1] == "LAST_NOTIFICATION" and type(saved) == "string" then v[2] = saved end
		if v[1] == "DIRECTORLINK_NOTIFY_KINDS" then v[2] = KindsText() end
	end
	AddVariables(VARIABLES)
end

function OnDriverLateInit(dit)
	ApplyLogSettings()
	SetLogPrefix()
	-- The agreement: written at every start, so they are right after a driver update too
	SetVar("DIRECTORLINK_NOTIFY", tostring(AGREEMENT_VERSION), true)
	SetVar("DIRECTORLINK_NOTIFY_KINDS", KindsText(), true)
	local host = trim(Properties["TV IP Address"])
	if host ~= "" and not ValidAddress(host) then host = "" end
	local app = AppFromProperty()
	local sameTv = host ~= "" and host == gState.savedHost and gState.seenHost == host
	gTv.host, gTv.app = host, app
	gTv.seenHere = sameTv
	if sameTv and gState.savedInfo then gTv.info = gState.savedInfo end
	gState.savedHost, gState.savedApp = host, app
	local from = ParseQuietHours(Properties["Quiet Hours"])
	gState.quietOk = from ~= false
	UpdatePropertyList("TVs Found", { "-" }, "-")
	UpdateStatus()
	if ValidAddress(host) then
		SetTimer("START", 2000, function() TvCheck() end)
	else
		-- No address yet: look for TVs, so TVs Found is filled when the installer opens the properties
		SetTimer("START", 3000, FindTVs)
	end
end

function OnDriverDestroyed()
	TvStop()
	KillAllTimers()
end

KIND_PROPERTY_NAMES = {}
for _, k in ipairs(NOTIFY_KINDS) do KIND_PROPERTY_NAMES[KIND_PROPERTY[k]] = k end

function OnPropertyChanged(name)
	LogDebug("Property changed: %s = %s", name, tostring(Properties[name]))
	if name == "Log Level" then
		ApplyLogSettings()
	elseif name == "TV IP Address" then
		-- Applied once the installer is done typing
		SetTimer("ADDRESS_APPLY", 1500, function() ApplyTv() end)
	elseif name == "TV App" then
		ApplyTv("the app changed")
	elseif name == "TVs Found" then
		PickFound()
	elseif name == "Quiet Hours" then
		CheckQuietHours()
	elseif KIND_PROPERTY_NAMES[name] then
		SetKindsVariable()
	end
end

-- DirectorLink's C4:SendToDevice reaches a driver here or in ExecuteCommand, depending on the device it names
function ReceivedFromProxy(idBinding, strCommand, tParams)
	if strCommand == "DIRECTORLINK_NOTIFY" then
		local ok, err = pcall(DirectorLinkNotify, tParams or {}, "ReceivedFromProxy")
		if not ok then LogError("DIRECTORLINK_NOTIFY failed: %s", err) end
	end
end

function ExecuteCommand(strCommand, tParams)
	tParams = tParams or {}
	if strCommand == "LUA_ACTION" then
		local action = ACTIONS[tParams.ACTION]
		if action then
			LogDebug("Action %s", tostring(tParams.ACTION))
			local ok, err = pcall(action)
			if not ok then LogError("Action %s failed: %s", tostring(tParams.ACTION), err) end
		end
		return
	end
	local cmd = COMMANDS[strCommand]
	if cmd then
		local ok, err = pcall(cmd, tParams)
		if not ok then LogError("Command %s failed: %s", strCommand, err) end
	end
end

function OnConnectionStatusChanged(idBinding, nPort, strStatus)
	SsdpStatus(idBinding, strStatus)
end

function ReceivedFromNetwork(idBinding, nPort, strData)
	SsdpData(idBinding, strData)
end
