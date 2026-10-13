--[[=============================================================================
    DirectorLink Android TV Notifications - the TVs and PiPup
    One driver shows each notification on every TV in its list, at once.
    Each TV runs "PiPup - TV Notifications" by Alexander Savin (Google Play:
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
    Port 7979 unless changed in PiPup's settings ("ip:port" in the list).

    Other apps named PiPup (the original, and other forks) take other
    requests: the driver works with this one only.

    For each TV, a pop-up goes only when its screen is on (/status, just
    before); the TV has TV_CONNECT_S (3 s) to take the connection, else it
    is left out. A TV that refuses the connection at once is on without PiPup
    running. The driver never turns a TV on. The notification counts as shown
    when at least one TV showed it.

    Each TV is checked every minute while PiPup answers; when it does not,
    after 5 s, 30 s, 2 min, then every 5 min. Each pop-up tries every TV
    whatever the last check said.

    Copyright 2026 DirectorLink
    SPDX-License-Identifier: Apache-2.0
===============================================================================]]

PIPUP_PORT = 7979
TV_MAX = 16                   -- TVs in one driver
TV_CONNECT_S = 3              -- a TV takes the connection within this, or it is off / not reachable
TV_TIMEOUT_S = 10             -- PiPup answers a pop-up within this
TV_STATUS_TIMEOUT_S = 3       -- /status, before a pop-up
TV_CHECK_MS = 60000           -- PiPup answers: checked again this often
TV_BACKOFF_S = { 5, 30, 120, 300 }
POPUP_ID = "directorlink"     -- one pop-up at a time on a TV: a new one updates it in place
PIPUP_IMAGE_WIDTH = 640

-- "Position" property -> PiPup's position
TV_POSITIONS = { ["Top Right"] = 0, ["Top Left"] = 1, ["Bottom Right"] = 2, ["Bottom Left"] = 3, ["Center"] = 4 }

gTvs = {}         -- the TVs, in the order of TV IP Addresses
gTvByKey = {}     -- "host:port" -> tv
gTvToken = ""     -- PiPup Token, for every TV
gTvReq = 0

--[[ A TV:
    { key = "host:port", host, port,
      state = idle, checking, ready, off (screen off), token, blocked, noapp, unreachable,
      seenHere (PiPup answered at this address before: Off rather than Not reachable),
      lastError, lastErrorAt, lastOkAt, nextCheckAt,
      info = { name, version, id } (/status), screenOn, authEnabled,
      backoff, checks, sent, gen (a TV removed or reset: answers to older requests are dropped) } ]]

local function Changed()
	if TvChanged then TvChanged() end
end

function TvName(tv)
	local n = tv.info and tv.info.name
	return (n and n ~= "") and n or tv.host
end

function TvList()
	return gTvs
end

--[[------------------------------------------------------------------ HTTP to PiPup
    cb(code, body, fail): fail is nil, or { kind, text } with kind
      "refused"      the TV refused at once: it is on, PiPup is not listening
      "unreachable"  no connection within TV_CONNECT_S: off, or not on the network
      "timeout"      connected, but no answer in time
      "error"        anything else                                          ]]
local function Http(tv, method, path, body, timeoutS, cb)
	local gen = tv.gen
	local url = "http://" .. tv.host .. ":" .. tv.port .. path
	local headers = {}
	if body then headers["Content-Type"] = "application/json; charset=utf-8" end
	if gTvToken ~= "" then headers["Authorization"] = "Bearer " .. gTvToken end
	local started = NowMs()
	gTvReq = gTvReq + 1
	local guard = "TV_HTTP_" .. gTvReq
	local over = false
	local function finish(code, rbody, fail)
		if over then return end
		over = true
		KillTimer(guard)
		if gen ~= tv.gen then return end
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
			LogTrace("%s %s%s -> HTTP %s (%d ms) %s", method, tv.host, path, tostring(resp.code), NowMs() - started, string.sub(tostring(resp.body or ""), 1, 200))
			finish(tonumber(resp.code) or 0, resp.body or "", nil)
		end)
		if method == "POST" then x:Post(url, body or "", headers) else x:Get(url, headers) end
	end)
	if not ok then finish(nil, nil, { kind = "error", text = tostring(err) }) end
end

local function FailText(tv, fail, timeoutS)
	if fail.kind == "refused" then
		return "the TV answers, but PiPup does not (not installed, not started, or on another port)"
	elseif fail.kind == "unreachable" then
		return "the TV did not answer within " .. TV_CONNECT_S .. " s (" .. (tv.seenHere and "off" or "not reachable") .. ")"
	elseif fail.kind == "timeout" then
		return "no answer from PiPup within " .. tostring(timeoutS or TV_TIMEOUT_S) .. " s"
	end
	return "PiPup: " .. tostring(fail.text)
end

--[[------------------------------------------------------------------ A TV's state ]]
local ScheduleCheck -- forward

local function SetState(tv, state, why)
	local before = tv.state
	tv.state = state
	if state == "ready" or state == "off" or state == "token" or state == "blocked" then
		tv.seenHere = true
		tv.lastOkAt = NowMs()
	end
	if state == "ready" then
		tv.lastError = nil
	elseif why then
		tv.lastError, tv.lastErrorAt = why, NowMs()
	end
	if before ~= state and (before == "ready" or state == "ready") and before ~= "idle" and before ~= "checking" then
		LogInfo("%s is now %s", TvName(tv), TvStateText(tv))
	end
	Changed()
end

-- PiPup answered with 401 or 403: it wants a token, or does not take this controller
local function Refusal(tv, code)
	if code == 401 then
		local why = gTvToken ~= "" and "PiPup did not take the token in PiPup Token" or "PiPup asks for a token: enter the one set in PiPup's settings in PiPup Token"
		SetState(tv, "token", why)
		return why
	end
	local why = "PiPup refuses requests from " .. (ControllerAddress() or "the controller") .. ": allow it in PiPup's settings (IP allowlist)"
	SetState(tv, "blocked", why)
	return why
end

-- A request PiPup did not answer: the state says why. A pop-up that finds the TV gone starts its checks
-- again from 5 s (a check schedules its own next one).
local function Unanswered(tv, fail, timeoutS, fromCheck)
	local wasReady = tv.state == "ready"
	if fail.kind == "refused" then
		SetState(tv, "noapp", FailText(tv, fail, timeoutS))
	elseif fail.kind == "unreachable" then
		SetState(tv, "unreachable", FailText(tv, fail, timeoutS))
	else
		SetState(tv, tv.state == "idle" and "unreachable" or tv.state, FailText(tv, fail, timeoutS))
	end
	if wasReady and tv.state ~= "ready" then
		tv.backoff = 0
		if not fromCheck then ScheduleCheck(tv, false) end
	end
end

function TvStateText(tv)
	local s = tv.state
	if s == "ready" then return "ready" end
	if s == "off" then return "off (its screen is off)" end
	if s == "token" then return "on, but PiPup wants a token" end
	if s == "blocked" then return "on, but PiPup refuses this controller" end
	if s == "noapp" then return "on, but PiPup does not answer" end
	if s == "unreachable" then return tv.seenHere and "off or away" or "not reachable" end
	return s
end

-- /status: cb(ok, why). ok when PiPup answered and may be sent a pop-up (screen on, no token missing).
-- fromCheck: called by a check (which schedules the next one itself).
local function ReadStatus(tv, cb, fromCheck)
	Http(tv, "GET", "/status", nil, TV_STATUS_TIMEOUT_S, function(code, body, fail)
		if fail then
			Unanswered(tv, fail, TV_STATUS_TIMEOUT_S, fromCheck)
			return cb(false, FailText(tv, fail, TV_STATUS_TIMEOUT_S))
		end
		if code == 401 or code == 403 then return cb(false, Refusal(tv, code)) end
		local st = code == 200 and JsonDecode(body) or nil
		if type(st) ~= "table" then
			-- A PiPup without /status: it answers, the rest is not known
			tv.screenOn, tv.authEnabled = nil, nil
			SetState(tv, "ready")
			return cb(true)
		end
		tv.info = { name = JsonField(st, "name"), version = JsonField(st, "version"), id = JsonField(st, "id") }
		tv.screenOn = JsonField(st, "screenOn")
		tv.authEnabled = JsonField(st, "authEnabled")
		if tv.authEnabled == true and gTvToken == "" then
			return cb(false, Refusal(tv, 401))
		end
		if tv.screenOn == false then
			SetState(tv, "off", "the TV's screen is off")
			return cb(false, "its screen is off")
		end
		SetState(tv, "ready")
		cb(true)
	end)
end

--[[------------------------------------------------------------------ Checks ]]
-- answered: PiPup answered (check again in a minute); not: 5 s, 30 s, 2 min, then every 5 min
ScheduleCheck = function(tv, answered)
	if gTvByKey[tv.key] ~= tv then return end
	local ms
	if answered then
		tv.backoff = 0
		ms = TV_CHECK_MS
	else
		tv.backoff = tv.backoff + 1
		ms = TV_BACKOFF_S[math.min(tv.backoff, #TV_BACKOFF_S)] * 1000
	end
	tv.nextCheckAt = NowMs() + ms
	SetTimer("TV_CHECK_" .. tv.key, ms, function() TvCheck(tv) end)
end

function TvCheck(tv)
	KillTimer("TV_CHECK_" .. tv.key)
	if gTvByKey[tv.key] ~= tv then return end
	tv.checks = tv.checks + 1
	if tv.state == "idle" then
		tv.state = "checking"
		Changed()
	end
	ReadStatus(tv, function()
		ScheduleCheck(tv, tv.state ~= "unreachable" and tv.state ~= "noapp" and tv.state ~= "checking")
	end, true)
end

-- "192.168.1.127, 192.168.1.140:8080" -> { { host, port }, ... } (each once, at most TV_MAX), and the
-- entries that are not addresses
function ParseTvList(text, port)
	local out, bad, seen = {}, {}, {}
	for entry in string.gmatch(tostring(text or ""), "[^,;%s]+") do
		local host, p = string.match(entry, "^([^:]+):(%d+)$")
		if not host then host = entry end
		local n = tonumber(p or "") or port or PIPUP_PORT
		if ValidAddress(host) and n >= 1 and n <= 65535 then
			local key = string.lower(host) .. ":" .. n
			if not seen[key] and #out < TV_MAX then
				seen[key] = true
				out[#out + 1] = { host = host, port = n, key = key }
			end
		else
			bad[#bad + 1] = entry
		end
	end
	return out, bad
end

-- A new list of TVs (or a new token): TVs that stay keep their state unless the token changed; new
-- ones are checked now. saved: key -> { seen, info } from the saved state.
function TvConfigure(list, token, saved)
	local tokenChanged = token ~= gTvToken
	if gTvToken ~= "" and tokenChanged then ForgetSecret(gTvToken) end
	gTvToken = token or ""
	RegisterSecret(gTvToken)
	local keep = {}
	for _, e in ipairs(list) do keep[e.key] = true end
	for key, tv in pairs(gTvByKey) do
		if not keep[key] then
			tv.gen = tv.gen + 1
			KillTimer("TV_CHECK_" .. key)
			gTvByKey[key] = nil
		end
	end
	local tvs = {}
	for _, e in ipairs(list) do
		local tv = gTvByKey[e.key]
		local fresh = tv == nil or tokenChanged
		if not tv then
			local s = saved and saved[e.key]
			tv = { key = e.key, host = e.host, port = e.port, state = "idle", seenHere = s and s.seen or false,
				info = (s and s.info) or {}, backoff = 0, checks = 0, sent = 0, gen = 0 }
			gTvByKey[e.key] = tv
		elseif tokenChanged then
			tv.gen = tv.gen + 1
			tv.state, tv.backoff, tv.lastError = "idle", 0, nil
		end
		tvs[#tvs + 1] = tv
		if fresh then TvCheck(tv) end
	end
	gTvs = tvs
	Changed()
end

function TvStop()
	for key, tv in pairs(gTvByKey) do
		tv.gen = tv.gen + 1
		KillTimer("TV_CHECK_" .. key)
	end
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

-- One TV: cb(ok, why)
local function ShowOn(tv, item, body, cb)
	ReadStatus(tv, function(ok, why)
		if not ok then return cb(false, why) end
		item.sentMs = item.sentMs or NowMs()
		Http(tv, "POST", "/notify", body, TV_TIMEOUT_S, function(code, rbody, fail)
			if fail then
				Unanswered(tv, fail, TV_TIMEOUT_S)
				return cb(false, FailText(tv, fail, TV_TIMEOUT_S))
			end
			if code == 401 or code == 403 then return cb(false, Refusal(tv, code)) end
			if code ~= 200 then
				return cb(false, "PiPup answered HTTP " .. tostring(code) .. (rbody ~= "" and (": " .. string.sub(rbody, 1, 80)) or ""))
			end
			tv.sent = tv.sent + 1
			cb(true)
		end)
	end)
end

-- Every TV at once. done(ok, why) exactly once: ok when at least one TV showed it; why says where (or
-- why not). item.results: { { tv = name, ok, why } } for each TV.
function TvShow(item, done)
	local tvs = TvList()
	if #tvs == 0 then return done(false, "no TV address") end
	local body = PipupBody(item)
	local left = #tvs
	local shown, missed = {}, {}
	item.results = {}
	for _, tv in ipairs(tvs) do
		ShowOn(tv, item, body, function(ok, why)
			item.results[#item.results + 1] = { tv = TvName(tv), ok = ok, why = why }
			if ok then shown[#shown + 1] = TvName(tv) else missed[#missed + 1] = TvName(tv) .. ": " .. tostring(why) end
			left = left - 1
			if left > 0 then return end
			if #shown == 0 then
				return done(false, #tvs == 1 and tostring(why) or table.concat(missed, "; "))
			end
			local where = #tvs == 1 and "the TV" or (#shown == #tvs and ("all " .. #tvs .. " TVs") or (#shown .. " of " .. #tvs .. " TVs"))
			if #tvs > 1 then where = where .. " (" .. table.concat(shown, ", ") .. (#missed > 0 and ("; not on " .. table.concat(missed, "; ")) or "") .. ")" end
			done(true, where)
		end)
	end
end
