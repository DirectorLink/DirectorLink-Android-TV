--[[=============================================================================
    DirectorLink · Android TV Notifications for Control4 - DriverWorks driver
    https://directorlink.io/drivers/android-tv

    Shows notifications as a pop-up, with a picture (who is at the door or
    the gate), on every TV in its list that runs Google TV or Android TV, on
    the home network only. Each TV runs PiPup - TV Notifications by
    Alexander Savin (Google Play: nyc.savin.pipup), a free app that takes
    pop-ups over the network (tvapp.lua).

      - What it shows: DirectorLink's notifications (the DirectorLink
        notification agreement, version 1: DIRECTORLINK_NOTIFY), the Show
        Notification command, and the Test Notification action
        (notify.lua): only the kinds switched on, nothing during Quiet Hours,
        at most one pop-up every 5 seconds, a doorbell or the alarm first.
      - Every TV in TV IP Addresses at once; the notification is shown when at
        least one TV showed it.
      - The picture: the notification's PICTURE (or Show Notification's
        Picture URL), fetched by the driver and carried inline, when Pictures
        is On.
      - A TV that is off, or does not answer within 3 seconds, is left out
        with one log line. The driver never turns a TV on.
      - Finding TVs: an SSDP search for casting devices (ssdp.lua), each asked
        whether PiPup answers; picking one adds it to the list.

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

gState = { savedVars = {}, quietOk = true, foundAt = nil, found = {}, saved = {}, badEntries = {} }

--[[=============================================================================
    Saved state
    DL_TV: for each TV of the list ("host:port"), whether PiPup answered there,
    and its name and PiPup's version. DL_VARS: LAST_NOTIFICATION. The token
    stays in its property.
===============================================================================]]
function SaveState()
	local tvs = {}
	for _, tv in ipairs(TvList()) do
		tvs[#tvs + 1] = JsonObject({ key = tv.key, seen = tv.seenHere, name = tv.info.name, version = tv.info.version })
	end
	StoreSet("DL_TV", JsonObject({ tvs = tvs }))
end

local function LoadState()
	local s = StoreGet("DL_TV")
	if type(s) ~= "table" then return end
	-- 1.0.0-beta.1 and beta.2 had one TV ("TV IP Address"): its address moves to TV IP Addresses
	local oldHost = JsonField(s, "host")
	if type(oldHost) == "string" and ValidAddress(oldHost) then gState.oldHost = oldHost end
	for _, t in ipairs(JsonField(s, "tvs") or {}) do
		local key = type(t) == "table" and JsonField(t, "key")
		if type(key) == "string" then
			local name, version = JsonField(t, "name"), JsonField(t, "version")
			gState.saved[key] = {
				seen = JsonField(t, "seen") == true,
				info = { name = type(name) == "string" and name or nil, version = type(version) == "string" and version or nil },
			}
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

local function PortFromProperty()
	local n = tonumber(Properties["PiPup Port"] or "")
	if n and n >= 1 and n <= 65535 then return math.floor(n) end
	return PIPUP_PORT
end

-- One TV's state, as Status says it when it is the only one
function TvStatusText(tv)
	local s = tv.state
	if s == "ready" then return "Ready" end
	if s == "off" then return "Off" end
	if s == "token" then
		return gTvToken ~= "" and "PiPup did not take the token: check PiPup Token" or "PiPup asks for a token: enter the one from PiPup's settings in PiPup Token"
	end
	if s == "blocked" then return "PiPup refuses this controller: allow " .. (ControllerAddress() or "its address") .. " in PiPup's settings (IP allowlist)" end
	if s == "noapp" then return "The TV answers, but PiPup does not: open PiPup on the TV (or check the port)" end
	if s == "unreachable" then return tv.seenHere and "Off" or "Not reachable" end
	return "Checking..."
end

-- The same, short, for a list of TVs
local function TvShortText(tv)
	local s = tv.state
	if s == "token" then return "needs the token" end
	if s == "blocked" then return "PiPup refuses this controller" end
	if s == "noapp" then return "PiPup not answering" end
	return TvStatusText(tv)
end

function StatusText()
	local tvs = TvList()
	local text
	if #tvs == 0 then
		text = "Enter the TVs' IP addresses, or pick them in TVs Found"
	elseif #tvs == 1 then
		text = TvStatusText(tvs[1])
	else
		local ready, others = 0, {}
		for _, tv in ipairs(tvs) do
			if tv.state == "ready" then ready = ready + 1 else others[#others + 1] = TvName(tv) .. ": " .. TvShortText(tv) end
		end
		if ready == #tvs then
			text = "Ready: " .. #tvs .. " TVs"
		else
			text = ready .. " of " .. #tvs .. " TVs ready - " .. table.concat(others, ", ")
		end
	end
	if #gState.badEntries > 0 then text = text .. " - not an address: " .. table.concat(gState.badEntries, ", ") end
	if not gState.quietOk then text = text .. " - Quiet Hours not understood: write it as 22:00-07:00" end
	return text
end

-- "SONY XR-77A95L (192.168.1.127): Ready · PiPup 0.3.4" for each TV
function TvsText()
	local parts = {}
	for _, tv in ipairs(TvList()) do
		parts[#parts + 1] = TvName(tv) .. (TvName(tv) ~= tv.host and (" (" .. tv.host .. ")") or "") .. ": " .. TvShortText(tv)
			.. (tv.info.version and (", PiPup " .. tv.info.version) or "")
	end
	return table.concat(parts, " · ")
end

function UpdateStatus()
	local status = StatusText()
	if status ~= Properties["Status"] then LogDebug("Status: %s", status) end
	UpdateProperty("Status", status)
	UpdateProperty("TVs", TvsText())
end

-- From tvapp.lua: a TV's state or what PiPup said about it changed
function TvChanged()
	local key = {}
	for _, tv in ipairs(TvList()) do key[#key + 1] = tv.key .. "|" .. tostring(tv.seenHere) .. "|" .. tostring(tv.info.name) .. "|" .. tostring(tv.info.version) end
	key = table.concat(key, ";")
	if key ~= gState.savedKey then
		gState.savedKey = key
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
    The TVs' addresses, PiPup's port and token
===============================================================================]]
local function ApplyTvs(reason)
	local list, bad = ParseTvList(Properties["TV IP Addresses"], PortFromProperty())
	gState.badEntries = bad
	if #bad > 0 then LogWarn("TV IP Addresses: not an address: %s", table.concat(bad, ", ")) end
	local before = {}
	for _, tv in ipairs(TvList()) do before[tv.key] = true end
	local added = {}
	for _, e in ipairs(list) do
		if not before[e.key] then added[#added + 1] = e.host .. (e.port ~= PIPUP_PORT and (":" .. e.port) or "") end
	end
	if #added > 0 then LogInfo("TV%s %s%s", #added > 1 and "s" or "", table.concat(added, ", "), reason and (" (" .. reason .. ")") or "") end
	TvConfigure(list, trim(Properties["PiPup Token"]), gState.saved)
	SaveState()
	UpdateStatus()
end

--[[=============================================================================
    Finding TVs: the casting devices on the network, each asked whether PiPup answers;
    picking one adds it to TV IP Addresses
===============================================================================]]
local function FoundItem(dev)
	local name = dev.name or trim((dev.maker or "") .. " " .. (dev.model or ""))
	if name == "" then name = "TV" end
	return name .. " (" .. dev.ip .. ")" .. (dev.app and " - PiPup answers" or "")
end

-- GET /ping: "pipup <version>"
local function ProbeApp(dev, done)
	local url = "http://" .. dev.ip .. ":" .. PortFromProperty() .. "/ping"
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
			local resp = responses and responses[#responses]
			finish((errCode == nil or errCode == 0) and resp ~= nil and string.find(string.lower(tostring(resp.body or "")), "pipup", 1, true) == 1)
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
				LogInfo("Find TVs: no TV answered. A TV answers while it is on; or type its IP address in TV IP Addresses")
			else
				local names = {}
				for i = 2, #items do names[#names + 1] = items[i] end
				LogInfo("Find TVs: %s. Pick a TV in TVs Found to add it", table.concat(names, ", "))
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

-- A TV picked in TVs Found is added to TV IP Addresses (once)
local function PickFound()
	local v = Properties["TVs Found"] or "-"
	local ip = string.match(v, "%((%d+%.%d+%.%d+%.%d+)%)")
	if not ip then return end
	local list = ParseTvList(Properties["TV IP Addresses"], PortFromProperty())
	for _, e in ipairs(list) do
		if e.host == ip then
			LogInfo("%s is already in TV IP Addresses", ip)
			return
		end
	end
	local current = trim(Properties["TV IP Addresses"])
	UpdateProperty("TV IP Addresses", current == "" and ip or (current .. ", " .. ip))
	ApplyTvs("picked in TVs Found")
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
	if #TvList() == 0 then
		LogWarn("Test Notification: enter the TVs' IP addresses first")
		return
	end
	LogInfo("Test Notification: sending a pop-up to %s", #TvList() == 1 and "the TV" or ("the " .. #TvList() .. " TVs"))
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
		"PiPup         : port " .. PortFromProperty() .. ", token " .. (gTvToken ~= "" and "set (never shown)" or "not set"),
	}
	lines[#lines + 1] = "TVs           :" .. (#TvList() == 0 and " none" or "")
	for _, tv in ipairs(TvList()) do
		lines[#lines + 1] = "   " .. tv.host .. ":" .. tv.port .. " " .. TvName(tv) .. (tv.info.version and (" (PiPup " .. tv.info.version .. ")") or "")
			.. " - " .. TvStateText(tv) .. ", screen " .. (tv.screenOn == nil and "?" or (tv.screenOn and "on" or "off"))
			.. ", token " .. (tv.authEnabled == true and "required" or (tv.authEnabled == false and "not required" or "?"))
			.. ", " .. tv.sent .. " pop-ups, " .. tv.checks .. " checks"
			.. (tv.lastOkAt and (", last answer " .. ClockText(tv.lastOkAt)) or ", no answer yet")
			.. (tv.nextCheckAt and (", next check " .. ClockText(tv.nextCheckAt)) or "")
			.. (tv.lastError and (" - last error: " .. tv.lastError .. " at " .. ClockText(tv.lastErrorAt)) or "")
	end
	lines[#lines + 1] = "Pop-ups       : " .. tostring(Properties["Position"]) .. ", " .. tostring(Properties["Seconds On Screen"]) .. " s, pictures " .. tostring(Properties["Pictures"])
	lines[#lines + 1] = "Kinds on      : " .. (KindsText() ~= "" and KindsText() or "none")
	lines[#lines + 1] = "Quiet Hours   : " .. (quiet ~= "" and (quiet .. (gState.quietOk and (InQuietHours() and " (now)" or " (not now)") or " (NOT UNDERSTOOD)")) or "none")
		.. ", local time " .. os.date("%H:%M")
	lines[#lines + 1] = "DirectorLink  : DIRECTORLINK_NOTIFY = " .. tostring(GetVar("DIRECTORLINK_NOTIFY")) .. ", DIRECTORLINK_NOTIFY_KINDS = " .. tostring(GetVar("DIRECTORLINK_NOTIFY_KINDS"))
	lines[#lines + 1] = "Notifications : " .. gNotify.counts.shown .. " shown, " .. gNotify.counts.failed .. " not shown, " .. gNotify.counts.skipped .. " skipped"
		.. (#gNotify.queue > 0 and (", " .. #gNotify.queue .. " waiting") or "") .. (gNotify.busy and ", one on its way" or "")
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
	local from = ParseQuietHours(Properties["Quiet Hours"])
	gState.quietOk = from ~= false
	if trim(Properties["TV IP Addresses"]) == "" and gState.oldHost then
		LogInfo("TV IP Addresses: %s, the TV of the earlier version", gState.oldHost)
		UpdateProperty("TV IP Addresses", gState.oldHost)
		gState.saved[string.lower(gState.oldHost) .. ":" .. PortFromProperty()] = { seen = true, info = {} }
	end
	UpdatePropertyList("TVs Found", { "-" }, "-")
	UpdateStatus()
	if trim(Properties["TV IP Addresses"]) ~= "" then
		SetTimer("START", 2000, function() ApplyTvs() end)
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
	LogDebug("Property changed: %s = %s", name, name == "PiPup Token" and "***" or tostring(Properties[name]))
	if name == "Log Level" then
		ApplyLogSettings()
	elseif name == "TV IP Addresses" or name == "PiPup Port" or name == "PiPup Token" then
		-- Applied once the installer is done typing
		SetTimer("ADDRESS_APPLY", 1500, function() ApplyTvs() end)
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
