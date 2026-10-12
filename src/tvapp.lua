--[[=============================================================================
    DirectorLink Android TV Notifications - the TV and its app
    An Android TV, Google TV or Fire TV shows a pop-up over whatever is on
    when an app on it is asked to over the home network. The driver works
    with two such apps, chosen per TV in the "TV App" property:

      - "Notifications for Android TV" (Christian Fees; Google Play on
        Android TV / Google TV 11 and newer, "Notifications for Fire TV" in
        the Amazon Appstore): port 7676, a multipart POST to "/" with the
        fields msg, title, duration, position, bkgcolor, transparency,
        interrupt and imageurl, and a small icon as the file part "filename".
        The app has no published API: this is the request Home Assistant's
        integration (notifications-android-tv) and FHEM send, which the app
        has taken for years. The picture goes as "imageurl": the TV fetches
        it. Any HTTP answer to "GET /" means the app is there; 200 to the POST
        means it took the pop-up. It cannot say whether the screen is on.
      - PiPup (the maintained version, github.com/mhoogenbosch/PiPup,
        installed with its script): port 7979, POST /notify with JSON (id,
        duration, position, title, message, media.image.uri), answered 200
        once the pop-up is on the screen. GET /state says whether the screen
        is on and whether the app may draw over other apps: a pop-up goes
        only to a screen that is on.

    Off or not reachable: the TV has TV_CONNECT_S (3 s) to take the
    connection; then the pop-up is dropped. A TV that refuses the connection
    at once is on, without the app running. The driver never turns the TV on
    (PiPup's /power is never used).

    The app is checked every minute while it answers; when it does not,
    after 5 s, 30 s, 2 min, then every 5 min. Each pop-up tries the TV
    whatever the last check said.

    Copyright 2026 DirectorLink
    SPDX-License-Identifier: Apache-2.0
===============================================================================]]

TV_APPS = {
	nfa = { key = "nfa", name = "Notifications for Android TV", port = 7676, timeoutS = 15 },
	pipup = { key = "pipup", name = "PiPup", port = 7979, timeoutS = 10 },
}
TV_APP_BY_NAME = { ["Notifications for Android TV"] = "nfa", ["PiPup"] = "pipup" }
TV_CONNECT_S = 3              -- the TV takes the connection within this, or it is off / not reachable
TV_STATE_TIMEOUT_S = 3        -- PiPup's /state, before a pop-up
TV_CHECK_MS = 60000           -- the app answers: checked again this often
TV_BACKOFF_S = { 5, 30, 120, 300 }
POPUP_ID = "directorlink"     -- PiPup: one pop-up at a time, a new one replaces it
PIPUP_IMAGE_WIDTH = 480
NFA_BACKGROUND = "#000000"
NFA_TRANSPARENCY = "1"        -- 0% transparent
-- The icon the app shows beside the text (Home Assistant's: a 1 x 1 transparent PNG)
NFA_ICON = "\137PNG\013\010\026\010\000\000\000\013IHDR\000\000\000\001\000\000\000\001\008\004\000\000\000\181\028\012\002\000\000\000\011IDATx\156c\250\207\000\000\002\007\001\002\154\0281q\000\000\000\000IEND\174B`\130"

-- "Position" property -> each app's number
TV_POSITIONS = {
	["Top Right"] = { nfa = 2, pipup = 0 },
	["Top Left"] = { nfa = 3, pipup = 1 },
	["Bottom Right"] = { nfa = 0, pipup = 2 },
	["Bottom Left"] = { nfa = 1, pipup = 3 },
	["Center"] = { nfa = 4, pipup = 4 },
}

gTv = {
	host = "", app = "nfa",
	state = "idle",           -- idle, checking, ready, off (PiPup: screen off), nooverlay, noapp, unreachable
	seenHere = false,         -- the app answered at this address before (Off rather than Not reachable)
	lastError = nil, lastErrorAt = nil, lastOkAt = nil,
	info = {},                -- PiPup's /state: name, model, maker, android, version
	screenOn = nil, overlay = nil,
	backoff = 0, checks = 0, sent = 0, req = 0,
	gen = 0,                  -- a new address or app: answers to older requests are dropped
}

local function Changed()
	if TvChanged then TvChanged() end
end

function TvApp()
	return TV_APPS[gTv.app]
end

--[[------------------------------------------------------------------ HTTP to the TV
    cb(code, body, fail): fail is nil, or { kind, text } with kind
      "refused"      the TV refused at once: it is on, the app is not listening
      "unreachable"  no connection within TV_CONNECT_S: off, or not on the network
      "timeout"      connected, but no answer in time
      "error"        anything else                                          ]]
local function Http(method, path, body, headers, timeoutS, cb)
	local gen = gTv.gen
	local url = "http://" .. gTv.host .. ":" .. TvApp().port .. path
	local started = NowMs()
	gTv.req = gTv.req + 1
	local guard = "TV_HTTP_" .. gTv.req
	local over = false
	local function finish(code, rbody, fail)
		if over then return end
		over = true
		KillTimer(guard)
		if gen ~= gTv.gen then return end
		cb(code, rbody, fail)
	end
	-- Director answers every request; this is in case it does not
	SetTimer(guard, (timeoutS + 5) * 1000, function() finish(nil, nil, { kind = "timeout", text = "no answer" }) end)
	LogTrace("%s %s%s", method, url, body and (" (" .. #body .. " bytes)") or "")
	local ok, err = pcall(function()
		local x = C4:url()
		x:SetOptions({ fail_on_error = false, timeout = timeoutS, connect_timeout = TV_CONNECT_S })
		x:OnDone(function(_, responses, errCode, errMsg)
			local resp = responses and responses[#responses]
			if (errCode ~= nil and errCode ~= 0) or not resp then
				local elapsed = NowMs() - started
				local kind = "error"
				if errCode == 7 and elapsed < 1000 then
					kind = "refused"
				elseif errCode == 7 or (errCode == 28 and elapsed < (TV_CONNECT_S + 1) * 1000) then
					kind = "unreachable"
				elseif errCode == 28 then
					kind = "timeout"
				end
				return finish(nil, nil, { kind = kind, text = tostring(errMsg or ("error " .. tostring(errCode))) })
			end
			LogTrace("%s %s -> HTTP %s (%d ms)", method, path, tostring(resp.code), NowMs() - started)
			finish(tonumber(resp.code) or 0, resp.body or "", nil)
		end)
		if method == "POST" then x:Post(url, body or "", headers or {}) else x:Get(url, headers or {}) end
	end)
	if not ok then finish(nil, nil, { kind = "error", text = tostring(err) }) end
end

local function FailText(fail, timeoutS)
	local app = TvApp()
	if fail.kind == "refused" then
		return "the TV answers, but " .. app.name .. " does not (not installed, or not started)"
	elseif fail.kind == "unreachable" then
		return "the TV did not answer within " .. TV_CONNECT_S .. " s (" .. (gTv.seenHere and "off" or "not reachable") .. ")"
	elseif fail.kind == "timeout" then
		return "no answer from " .. app.name .. " within " .. tostring(timeoutS or app.timeoutS) .. " s"
	end
	return app.name .. ": " .. tostring(fail.text)
end

--[[------------------------------------------------------------------ The state ]]
local ScheduleCheck -- forward

local function SetState(state, why)
	local before = gTv.state
	gTv.state = state
	if state == "ready" or state == "off" or state == "nooverlay" then
		gTv.seenHere = true
		gTv.lastOkAt = NowMs()
	end
	if state == "ready" then
		gTv.lastError = nil
	elseif why then
		gTv.lastError, gTv.lastErrorAt = why, NowMs()
	end
	if before ~= state and (before == "ready" or state == "ready") and before ~= "idle" and before ~= "checking" then
		LogInfo("The TV is now %s", TvStateText())
	end
	Changed()
end

-- A request the TV did not answer: the state says why. A pop-up that finds the TV gone starts the
-- checks again from 5 s (a check schedules its own next one).
local function Unanswered(fail, timeoutS, fromCheck)
	local wasReady = gTv.state == "ready"
	if fail.kind == "refused" then
		SetState("noapp", FailText(fail, timeoutS))
	elseif fail.kind == "unreachable" then
		SetState("unreachable", FailText(fail, timeoutS))
	else
		SetState(gTv.state == "idle" and "unreachable" or gTv.state, FailText(fail, timeoutS))
	end
	if wasReady and gTv.state ~= "ready" then
		gTv.backoff = 0
		if not fromCheck then ScheduleCheck(false) end
	end
end

function TvStateText()
	local s = gTv.state
	if s == "ready" then return "ready" end
	if s == "off" then return "off (its screen is off)" end
	if s == "nooverlay" then return "on, but PiPup may not draw over other apps" end
	if s == "noapp" then return "on, but " .. TvApp().name .. " does not answer" end
	if s == "unreachable" then return gTv.seenHere and "off or away" or "not reachable" end
	return s
end

-- PiPup's /state: cb(ok, why). ok when the app answered (its screen and permission are in gTv). fromCheck:
-- called by a check (which schedules the next one itself).
local function ReadState(cb, fromCheck)
	Http("GET", "/state", nil, nil, TV_STATE_TIMEOUT_S, function(code, body, fail)
		if fail then
			Unanswered(fail, TV_STATE_TIMEOUT_S, fromCheck)
			return cb(false, FailText(fail, TV_STATE_TIMEOUT_S))
		end
		local st = code == 200 and JsonDecode(body) or nil
		if type(st) ~= "table" then
			-- An early PiPup without /state: it answers, the rest is not known
			gTv.screenOn, gTv.overlay = nil, nil
			SetState("ready")
			return cb(true)
		end
		local device = JsonField(st, "device")
		local perms = JsonField(st, "permissions")
		gTv.info = {
			name = JsonField(st, "name"), version = JsonField(st, "version"),
			model = type(device) == "table" and JsonField(device, "model") or nil,
			maker = type(device) == "table" and JsonField(device, "manufacturer") or nil,
			android = type(device) == "table" and JsonField(device, "android") or nil,
		}
		gTv.screenOn = JsonField(st, "screenOn")
		gTv.overlay = nil -- not "a and b or nil": false must stay false
		if type(perms) == "table" then gTv.overlay = JsonField(perms, "overlay") end
		if gTv.overlay == false then
			SetState("nooverlay", "PiPup may not draw over other apps on the TV")
		elseif gTv.screenOn == false then
			SetState("off", "the TV's screen is off")
		else
			SetState("ready")
		end
		cb(true)
	end)
end

--[[------------------------------------------------------------------ Checks ]]
-- ok: the app answered (check again in a minute); not ok: 5 s, 30 s, 2 min, then every 5 min
ScheduleCheck = function(ok)
	if not ValidAddress(gTv.host) then return end
	local ms
	if ok then
		gTv.backoff = 0
		ms = TV_CHECK_MS
	else
		gTv.backoff = gTv.backoff + 1
		ms = TV_BACKOFF_S[math.min(gTv.backoff, #TV_BACKOFF_S)] * 1000
	end
	gTv.nextCheckAt = NowMs() + ms
	SetTimer("TV_CHECK", ms, function() TvCheck() end)
end

function TvCheck()
	KillTimer("TV_CHECK")
	if not ValidAddress(gTv.host) then
		gTv.state = "idle"
		Changed()
		return
	end
	gTv.checks = gTv.checks + 1
	if gTv.state == "idle" then
		gTv.state = "checking"
		Changed()
	end
	if gTv.app == "pipup" then
		ReadState(function(ok) ScheduleCheck(ok) end, true)
	else
		Http("GET", "/", nil, nil, 5, function(code, body, fail)
			if fail then
				Unanswered(fail, 5, true)
				return ScheduleCheck(false)
			end
			-- Any answer: the app is there (the same check Home Assistant makes)
			SetState("ready")
			ScheduleCheck(true)
		end)
	end
end

-- A new address or app: forget the old one, check the new one now
function TvConfigure(host, app, sameTv)
	gTv.gen = gTv.gen + 1
	KillTimer("TV_CHECK")
	gTv.host, gTv.app = host or "", app or gTv.app
	gTv.state = "idle"
	gTv.backoff = 0
	gTv.lastError = nil
	gTv.screenOn, gTv.overlay = nil, nil
	gTv.info = {}
	if not sameTv then gTv.seenHere = false end
	Changed()
	if ValidAddress(gTv.host) then TvCheck() end
end

function TvStop()
	gTv.gen = gTv.gen + 1
	KillTimer("TV_CHECK")
end

--[[------------------------------------------------------------------ A pop-up ]]
local function Seconds()
	local n = tonumber(Properties["Seconds On Screen"]) or 15
	return math.max(3, math.min(120, math.floor(n)))
end

local function Position(app)
	local p = TV_POSITIONS[Properties["Position"] or ""] or TV_POSITIONS["Top Right"]
	return p[app]
end

-- Title and message for the app: a title alone is the message
local function Texts(item)
	local title, message = item.title or "", item.message or ""
	if message == "" then title, message = "", title end
	return title, message
end

local function Part(boundary, name, value)
	return "--" .. boundary .. "\r\nContent-Disposition: form-data; name=\"" .. name .. "\"\r\n\r\n" .. value .. "\r\n"
end

-- Notifications for Android TV: multipart/form-data, as Home Assistant sends it
function NfaBody(item, boundary)
	local title, message = Texts(item)
	local parts = { Part(boundary, "msg", message) }
	if title ~= "" then parts[#parts + 1] = Part(boundary, "title", title) end
	parts[#parts + 1] = Part(boundary, "duration", tostring(Seconds()))
	parts[#parts + 1] = Part(boundary, "position", tostring(Position("nfa")))
	parts[#parts + 1] = Part(boundary, "bkgcolor", NFA_BACKGROUND)
	parts[#parts + 1] = Part(boundary, "transparency", NFA_TRANSPARENCY)
	parts[#parts + 1] = Part(boundary, "interrupt", "0")
	if item.picture then parts[#parts + 1] = Part(boundary, "imageurl", item.picture) end
	parts[#parts + 1] = "--" .. boundary .. "\r\nContent-Disposition: form-data; name=\"filename\"; filename=\"icon.png\"\r\n"
		.. "Content-Type: application/octet-stream\r\n\r\n" .. NFA_ICON .. "\r\n"
	parts[#parts + 1] = "--" .. boundary .. "--\r\n"
	return table.concat(parts)
end

-- PiPup: JSON
function PipupBody(item)
	local title, message = Texts(item)
	local popup = JsonObject({
		id = POPUP_ID, duration = Seconds(), position = Position("pipup"),
		titleSize = 20, messageSize = 16, backgroundColor = "#E6000000",
	})
	if title ~= "" then popup.title = title end
	if message ~= "" then popup.message = message end
	if item.picture then
		popup.media = JsonObject({ image = JsonObject({ uri = item.picture, width = PIPUP_IMAGE_WIDTH }) })
	end
	return JsonEncode(popup)
end

-- done(ok, why) exactly once; item.sentMs is set when the pop-up goes to the TV
function TvShow(item, done)
	if not ValidAddress(gTv.host) then return done(false, "no TV address") end
	local app = TvApp()
	local function answered(code, body, fail)
		if fail then
			Unanswered(fail, app.timeoutS)
			return done(false, FailText(fail, app.timeoutS))
		end
		if code ~= 200 then
			return done(false, app.name .. " answered HTTP " .. tostring(code) .. (body ~= "" and (": " .. string.sub(body, 1, 80)) or ""))
		end
		gTv.sent = gTv.sent + 1
		if gTv.app == "nfa" and gTv.state ~= "ready" then
			SetState("ready")
			ScheduleCheck(true)
		end
		done(true)
	end
	if gTv.app == "pipup" then
		ReadState(function(ok, why)
			if not ok then return done(false, why) end
			if gTv.overlay == false then return done(false, "PiPup may not draw over other apps on the TV") end
			if gTv.screenOn == false then return done(false, "the TV's screen is off") end
			item.sentMs = NowMs()
			Http("POST", "/notify", PipupBody(item), { ["Content-Type"] = "application/json; charset=utf-8" }, app.timeoutS, answered)
		end)
	else
		local boundary = "DirectorLink" .. string.format("%08x", math.random(0, 2147483646)) .. tostring(gTv.req)
		item.sentMs = NowMs()
		Http("POST", "/", NfaBody(item, boundary), { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary }, app.timeoutS, answered)
	end
end
