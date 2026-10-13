--[[=============================================================================
    DirectorLink Android TV Notifications - the TV and PiPup
    The TV runs "PiPup - TV Notifications" by Alexander Savin (Google Play:
    nyc.savin.pipup; https://pipup.android.savin.nyc), a free app that shows
    pop-ups over whatever is on when a device on the home network asks. Its
    HTTP API (its "How to use" page, and its maker's Home Assistant
    integration):
      - GET  /ping    "pipup <version>": the app is there
      - GET  /status  {"version","id","name","port","active","count",
                       "screenOn","uptimeSeconds","authEnabled"}
      - POST /notify  JSON: title, message, duration (s), position (0 top
                      right, 1 top left, 2 bottom right, 3 bottom left,
                      4 center), id (the same id updates that pop-up in
                      place), media.image {uri, width} (uri: an address,
                      or the picture inline as a data: URI); answers
                      {"status":"ok","id":...}
      - A token set in PiPup's settings goes with every request as
        "Authorization: Bearer <token>" (401 without it). An IP allowlist in
        PiPup's settings refuses other addresses (403).
    Port 7979 unless changed in PiPup's settings.

    Other apps named PiPup (the original, and other forks) take other
    requests: the driver works with this one only.

    A pop-up goes only to a TV whose screen is on (/status, just before);
    the TV has TV_CONNECT_S (3 s) to take the connection, then the pop-up is
    dropped. A TV that refuses the connection at once is on without PiPup
    running. The driver never turns the TV on.

    PiPup is checked every minute while it answers; when it does not, after
    5 s, 30 s, 2 min, then every 5 min. Each pop-up tries the TV whatever the
    last check said.

    Copyright 2026 DirectorLink
    SPDX-License-Identifier: Apache-2.0
===============================================================================]]

PIPUP_PORT = 7979
TV_CONNECT_S = 3              -- the TV takes the connection within this, or it is off / not reachable
TV_TIMEOUT_S = 10             -- PiPup answers a pop-up within this
TV_STATUS_TIMEOUT_S = 3       -- /status, before a pop-up
TV_CHECK_MS = 60000           -- PiPup answers: checked again this often
TV_BACKOFF_S = { 5, 30, 120, 300 }
POPUP_ID = "directorlink"     -- one pop-up at a time: a new one updates it in place
PIPUP_IMAGE_WIDTH = 640

-- "Position" property -> PiPup's position
TV_POSITIONS = { ["Top Right"] = 0, ["Top Left"] = 1, ["Bottom Right"] = 2, ["Bottom Left"] = 3, ["Center"] = 4 }

gTv = {
	host = "", port = PIPUP_PORT, token = "",
	state = "idle",           -- idle, checking, ready, off (screen off), token, blocked, noapp, unreachable
	seenHere = false,         -- PiPup answered at this address before (Off rather than Not reachable)
	lastError = nil, lastErrorAt = nil, lastOkAt = nil,
	info = {},                -- /status: name, version, id
	screenOn = nil, authEnabled = nil,
	backoff = 0, checks = 0, sent = 0, req = 0,
	gen = 0,                  -- a new address, port or token: answers to older requests are dropped
}

local function Changed()
	if TvChanged then TvChanged() end
end

--[[------------------------------------------------------------------ HTTP to PiPup
    cb(code, body, fail): fail is nil, or { kind, text } with kind
      "refused"      the TV refused at once: it is on, PiPup is not listening
      "unreachable"  no connection within TV_CONNECT_S: off, or not on the network
      "timeout"      connected, but no answer in time
      "error"        anything else                                          ]]
local function Http(method, path, body, timeoutS, cb)
	local gen = gTv.gen
	local url = "http://" .. gTv.host .. ":" .. gTv.port .. path
	local headers = {}
	if body then headers["Content-Type"] = "application/json; charset=utf-8" end
	if gTv.token ~= "" then headers["Authorization"] = "Bearer " .. gTv.token end
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
	LogTrace("%s %s%s", method, url, body and (" " .. string.sub(body, 1, 300)) or "")
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
			LogTrace("%s %s -> HTTP %s (%d ms) %s", method, path, tostring(resp.code), NowMs() - started, string.sub(tostring(resp.body or ""), 1, 200))
			finish(tonumber(resp.code) or 0, resp.body or "", nil)
		end)
		if method == "POST" then x:Post(url, body or "", headers) else x:Get(url, headers) end
	end)
	if not ok then finish(nil, nil, { kind = "error", text = tostring(err) }) end
end

local function FailText(fail, timeoutS)
	if fail.kind == "refused" then
		return "the TV answers, but PiPup does not (not installed, not started, or on another port)"
	elseif fail.kind == "unreachable" then
		return "the TV did not answer within " .. TV_CONNECT_S .. " s (" .. (gTv.seenHere and "off" or "not reachable") .. ")"
	elseif fail.kind == "timeout" then
		return "no answer from PiPup within " .. tostring(timeoutS or TV_TIMEOUT_S) .. " s"
	end
	return "PiPup: " .. tostring(fail.text)
end

--[[------------------------------------------------------------------ The state ]]
local ScheduleCheck -- forward

local function SetState(state, why)
	local before = gTv.state
	gTv.state = state
	if state == "ready" or state == "off" or state == "token" or state == "blocked" then
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

-- PiPup answered a request with 401 or 403: it wants a token, or does not take this controller
local function Refusal(code)
	if code == 401 then
		local why = gTv.token ~= "" and "PiPup did not take the token in PiPup Token" or "PiPup asks for a token: enter the one set in PiPup's settings in PiPup Token"
		SetState("token", why)
		return why
	end
	local ip = ControllerAddress() or "the controller"
	local why = "PiPup refuses requests from " .. ip .. ": allow it in PiPup's settings (IP allowlist)"
	SetState("blocked", why)
	return why
end

-- A request PiPup did not answer: the state says why. A pop-up that finds the TV gone starts the checks
-- again from 5 s (a check schedules its own next one).
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
	if s == "token" then return "on, but PiPup wants a token" end
	if s == "blocked" then return "on, but PiPup refuses this controller" end
	if s == "noapp" then return "on, but PiPup does not answer" end
	if s == "unreachable" then return gTv.seenHere and "off or away" or "not reachable" end
	return s
end

-- /status: cb(ok, why). ok when PiPup answered and may be sent a pop-up (screen on, no token missing).
-- fromCheck: called by a check (which schedules the next one itself).
local function ReadStatus(cb, fromCheck)
	Http("GET", "/status", nil, TV_STATUS_TIMEOUT_S, function(code, body, fail)
		if fail then
			Unanswered(fail, TV_STATUS_TIMEOUT_S, fromCheck)
			return cb(false, FailText(fail, TV_STATUS_TIMEOUT_S))
		end
		if code == 401 or code == 403 then return cb(false, Refusal(code)) end
		local st = code == 200 and JsonDecode(body) or nil
		if type(st) ~= "table" then
			-- A PiPup without /status: it answers, the rest is not known
			gTv.screenOn, gTv.authEnabled = nil, nil
			SetState("ready")
			return cb(true)
		end
		gTv.info = { name = JsonField(st, "name"), version = JsonField(st, "version"), id = JsonField(st, "id") }
		gTv.screenOn = JsonField(st, "screenOn")
		gTv.authEnabled = JsonField(st, "authEnabled")
		if gTv.authEnabled == true and gTv.token == "" then
			local why = Refusal(401)
			return cb(false, why)
		end
		if gTv.screenOn == false then
			SetState("off", "the TV's screen is off")
			return cb(false, "the TV's screen is off")
		end
		SetState("ready")
		cb(true)
	end)
end

--[[------------------------------------------------------------------ Checks ]]
-- answered: PiPup answered (check again in a minute); not: 5 s, 30 s, 2 min, then every 5 min
ScheduleCheck = function(answered)
	if not ValidAddress(gTv.host) then return end
	local ms
	if answered then
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
	ReadStatus(function()
		ScheduleCheck(gTv.state ~= "unreachable" and gTv.state ~= "noapp" and gTv.state ~= "checking")
	end, true)
end

-- A new address, port or token: forget the old one, check now
function TvConfigure(host, port, token, sameTv)
	gTv.gen = gTv.gen + 1
	KillTimer("TV_CHECK")
	if gTv.token ~= "" and gTv.token ~= token then ForgetSecret(gTv.token) end
	gTv.host, gTv.port, gTv.token = host or "", port or PIPUP_PORT, token or ""
	RegisterSecret(gTv.token)
	gTv.state = "idle"
	gTv.backoff = 0
	gTv.lastError = nil
	gTv.screenOn, gTv.authEnabled = nil, nil
	if not sameTv then
		gTv.seenHere = false
		gTv.info = {}
	end
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

-- PiPup's JSON: a title alone is the message
function PipupBody(item)
	local title, message = item.title or "", item.message or ""
	if message == "" then title, message = "", title end
	local popup = JsonObject({
		id = POPUP_ID, duration = Seconds(), position = TV_POSITIONS[Properties["Position"] or ""] or 0,
	})
	if title ~= "" then popup.title = title end
	if message ~= "" then popup.message = message end
	-- The picture inline (fetched by the driver), else its address for PiPup to fetch
	local uri = item.pictureData or item.picture
	if uri then
		popup.media = JsonObject({ image = JsonObject({ uri = uri, width = PIPUP_IMAGE_WIDTH }) })
	end
	return JsonEncode(popup)
end

-- done(ok, why) exactly once; item.sentMs is set when the pop-up goes to the TV
function TvShow(item, done)
	if not ValidAddress(gTv.host) then return done(false, "no TV address") end
	ReadStatus(function(ok, why)
		if not ok then return done(false, why) end
		item.sentMs = NowMs()
		Http("POST", "/notify", PipupBody(item), TV_TIMEOUT_S, function(code, body, fail)
			if fail then
				Unanswered(fail, TV_TIMEOUT_S)
				return done(false, FailText(fail, TV_TIMEOUT_S))
			end
			if code == 401 or code == 403 then return done(false, Refusal(code)) end
			if code ~= 200 then
				return done(false, "PiPup answered HTTP " .. tostring(code) .. (body ~= "" and (": " .. string.sub(body, 1, 80)) or ""))
			end
			gTv.sent = gTv.sent + 1
			done(true)
		end)
	end)
end
