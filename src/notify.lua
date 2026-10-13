--[[=============================================================================
    DirectorLink Android TV Notifications - notifications
    What reaches the TV, and when:
      - DirectorLink's DIRECTORLINK_NOTIFY (the DirectorLink notification
        agreement, version 1), the Show Notification command, and the Test
        Notification action all come here (NotifyAccept);
      - a repeat of the same ID within 10 minutes is ignored; only the kinds
        switched on in the properties are shown, and nothing during Quiet
        Hours (the test action shows all the same);
      - at most one pop-up every 5 seconds: the others wait their turn, a
        doorbell or the alarm before the rest; a wait too long or a queue too
        full drops the least urgent;
      - the TV side is TvShow(item, done) (tvapp.lua): it calls done(true)
        once the TV's app took the pop-up, or done(false, why) (off, not
        reachable, the app not running, refused);
      - LAST_NOTIFICATION is set, then "Notification Shown" or
        "Notification Failed" fires. One log line for each.
      - The picture (the agreement's PICTURE, or Show Notification's Picture
        URL), when Pictures is On: the driver fetches it at once (on the
        controller, so 127.0.0.1 works, and a login in a camera's address
        is sent as a login) and the pop-up carries it inline (a data: URI,
        which PiPup shows): the TV never has to reach the picture's server,
        and a picture that lasts 60 seconds cannot expire on the way. The
        pop-up waits PICTURE_WAIT_MS (2 s) for it at most. When it cannot be
        fetched, or is too large, the pop-up carries the address instead, for
        the TV to fetch (127.0.0.1 then becomes the controller's address).
    Nothing here waits: every step is a timer or a callback.

    Copyright 2026 DirectorLink
    SPDX-License-Identifier: Apache-2.0
===============================================================================]]

NOTIFY_KINDS = { "doorbell", "camera", "door", "alarm", "other" }
KIND_PROPERTY = { doorbell = "Doorbell", camera = "Camera Alerts", door = "Doors and Gates", alarm = "Alarm", other = "Other" }
KIND_LABEL = { doorbell = "Doorbell", camera = "Camera alert", door = "Door or gate", alarm = "Alarm", other = "Other" }
URGENT_KINDS = { doorbell = true, alarm = true }
NOTIFY_GAP_MS = 5000          -- at most one pop-up this often on a TV
DEDUPE_MS = 600000            -- the same ID again within 10 minutes is a repeat
DEDUPE_MAX = 300
QUEUE_MAX = 5                 -- waiting their turn at most
WAIT_MAX_MS = 30000           -- a camera alert, a door, other: dropped after waiting this long
WAIT_MAX_URGENT_MS = 60000    -- a doorbell or the alarm
HISTORY_MAX = 10

gNotify = {
	seen = {}, seenOrder = {},  -- ID -> when it came (ms)
	queue = {},                 -- waiting their turn, in arrival order
	busy = nil,                 -- the one the TV is showing now (waiting for the TV's answer)
	lastSentMs = nil,           -- when the last pop-up went to the TV
	seq = 0,
	history = {},               -- the last HISTORY_MAX, newest first, for Print Diagnostics
	counts = { shown = 0, failed = 0, skipped = 0 },
}

--[[------------------------------------------------------------------ Settings ]]
function KindOn(kind)
	local name = KIND_PROPERTY[kind]
	return name ~= nil and Properties[name] == "On"
end

-- The kinds switched on, in the agreement's order, comma-separated: "doorbell,alarm"
function KindsText()
	local on = {}
	for _, k in ipairs(NOTIFY_KINDS) do
		if KindOn(k) then on[#on + 1] = k end
	end
	return table.concat(on, ",")
end

-- "22:00-07:00" (also "22-7", "22:00 - 07:00", "22.00-07.00", with an en or em dash too): from and to
-- in minutes from midnight.
-- Empty: nil (no quiet hours). Not understood: false.
function ParseQuietHours(text)
	text = trim(text)
	if text == "" then return nil end
	text = string.gsub(text, "\226\128[\147\148]", "-") -- en dash, em dash
	local h1, m1, h2, m2 = string.match(text, "^(%d%d?)[:%.]?(%d?%d?)%s*%-%s*(%d%d?)[:%.]?(%d?%d?)$")
	if not h1 then return false end
	h1, h2 = tonumber(h1), tonumber(h2)
	m1, m2 = tonumber(m1 ~= "" and m1 or "0"), tonumber(m2 ~= "" and m2 or "0")
	if not (m1 and m2) or h1 > 24 or h2 > 24 or m1 > 59 or m2 > 59 then return false end
	local from, to = (h1 % 24) * 60 + m1, (h2 % 24) * 60 + m2
	if from == to then return false end
	return from, to
end

function MinutesText(m)
	return string.format("%02d:%02d", math.floor(m / 60), m % 60)
end

-- Quiet now? From 22:00 to 07:00 takes in midnight; from 13:00 to 15:00 does not. "To" is not part of it.
function InQuietHours(minutes)
	local from, to = ParseQuietHours(Properties["Quiet Hours"])
	if not from then return false end
	minutes = minutes or LocalMinutes()
	if from < to then return minutes >= from and minutes < to end
	return minutes >= from or minutes < to
end

--[[------------------------------------------------------------------ The text
    The pop-up shows the title and the message as given (Hebrew and other
    right-to-left text too). LAST_NOTIFICATION and the log join them with
    TOAST_JOIN.                                                            ]]
TOAST_JOIN = ": "
TOAST_MAX_BYTES = 1000 -- longer text is cut (at a character boundary)
TITLE_MAX_BYTES = 200
PICTURE_WAIT_MS = 2000         -- a pop-up waits this long for its picture, then carries the address
PICTURE_MAX_BYTES = 1500000    -- larger: the address goes instead

function CutUtf8(s, max)
	if #s <= max then return s end
	local i = max
	-- Not inside a UTF-8 character: back up over continuation bytes (10xxxxxx)
	while i > 0 do
		local b = string.byte(s, i + 1)
		if not b or b < 128 or b >= 192 then break end
		i = i - 1
	end
	return string.sub(s, 1, i) .. "..."
end

function ToastText(title, message)
	title, message = trim(title), trim(message)
	local text
	if title ~= "" and message ~= "" then
		text = title .. TOAST_JOIN .. message
	else
		text = title ~= "" and title or message
	end
	return CutUtf8(text, TOAST_MAX_BYTES)
end

-- A picture's address the TV can fetch: http(s), and 127.0.0.1 / localhost (the controller itself, for
-- a driver on it) replaced by the controller's address on the home network. nil when it cannot be.
function PictureUrl(url)
	url = trim(url)
	local scheme, host, rest = string.match(url, "^([hH][tT][tT][pP][sS]?)://([^/]+)(.*)$")
	if not scheme or string.find(url, "%s") then return nil end
	local login, hostport = string.match(host, "^(.*@)(.+)$")
	hostport = hostport or host
	local h, port = string.match(hostport, "^([^:]+)(:?%d*)$")
	if not h then return nil end
	local lower = string.lower(h)
	if lower == "127.0.0.1" or lower == "localhost" then
		local ip = ControllerAddress()
		if not ip then return nil end
		h = ip
	end
	return string.lower(scheme) .. "://" .. (login or "") .. h .. port .. rest
end

-- The picture's media type from its first bytes (nil: not a picture PiPup shows)
function PictureType(data)
	if type(data) ~= "string" or #data < 12 then return nil end
	if string.sub(data, 1, 2) == "\255\216" then return "image/jpeg" end
	if string.sub(data, 1, 8) == "\137PNG\r\n\026\n" then return "image/png" end
	if string.sub(data, 1, 4) == "GIF8" then return "image/gif" end
	if string.sub(data, 1, 4) == "RIFF" and string.sub(data, 9, 12) == "WEBP" then return "image/webp" end
	return nil
end

-- For a log line: one line, not too long
local function Short(s)
	s = string.gsub(tostring(s or ""), "[\r\n]+", " ")
	return CutUtf8(s, 80)
end

--[[------------------------------------------------------------------ Results ]]
local function Remember(item, result, why)
	table.insert(gNotify.history, 1, {
		at = NowMs(), kind = item.kind, source = item.source, id = item.id, text = item.text, result = result, why = why,
		picture = item.picture ~= nil,
	})
	while #gNotify.history > HISTORY_MAX do table.remove(gNotify.history) end
end

local function Describe(item)
	return (item.kind and KIND_LABEL[item.kind] or "Notification") .. " '" .. Short(item.text) .. "'"
		.. (item.source ~= "DirectorLink" and (" (" .. item.source .. ")") or "")
end

local function Finish(item, ok, why)
	if item.finished then return end
	item.finished = true
	item.picturePending = false
	KillTimer("PICTURE_" .. item.seq)
	SetVar("LAST_NOTIFICATION", item.text, true)
	if ok then
		-- why: where it was shown ("the TV", "all 2 TVs (...)", "1 of 2 TVs (...; not on ...)")
		local where = why or "the TV"
		gNotify.counts.shown = gNotify.counts.shown + 1
		Remember(item, "shown", where ~= "the TV" and where or nil)
		LogInfo("Shown on %s: %s%s", where, Describe(item), item.picture and " with its picture" or "")
		FireEvent("Notification Shown")
	else
		gNotify.counts.failed = gNotify.counts.failed + 1
		Remember(item, "not shown", why)
		LogInfo("Not shown (%s): %s", tostring(why), Describe(item))
		FireEvent("Notification Failed")
	end
	if NotifyChanged then NotifyChanged() end
end

local function Skip(item, why)
	gNotify.counts.skipped = gNotify.counts.skipped + 1
	Remember(item, "skipped", why)
	LogDebug("Skipped (%s): %s", why, Describe(item))
end

--[[------------------------------------------------------------------ The queue ]]
local NotifyPump -- forward

local function Urgent(item)
	return URGENT_KINDS[item.kind] == true
end

local function Expired(item, now)
	return now - item.at > (Urgent(item) and WAIT_MAX_URGENT_MS or WAIT_MAX_MS)
end

-- Next to go: the first doorbell or alarm, else the first of the rest
local function NextIndex()
	for i, item in ipairs(gNotify.queue) do
		if Urgent(item) then return i end
	end
	return gNotify.queue[1] and 1 or nil
end

NotifyPump = function()
	if gNotify.busy then return end
	local now = NowMs()
	-- Waited too long: a pop-up about what happened a minute ago helps no one
	local keep = {}
	for _, item in ipairs(gNotify.queue) do
		if Expired(item, now) then Finish(item, false, "waited too long for its turn") else keep[#keep + 1] = item end
	end
	gNotify.queue = keep
	local i = NextIndex()
	if not i then return end
	local item = gNotify.queue[i]
	-- Its picture first (fetched when the notification came; PICTURE_WAIT_MS at most)
	if item.picturePending then return end
	local wait = gNotify.lastSentMs and (gNotify.lastSentMs + NOTIFY_GAP_MS - now) or 0
	if wait > 0 then
		SetTimer("NOTIFY_NEXT", wait, NotifyPump)
		return
	end
	table.remove(gNotify.queue, i)
	gNotify.busy = item
	item.startedMs = now
	LogDebug("To the TV: %s", Describe(item))
	TvShow(item, function(ok, why)
		if gNotify.busy == item then gNotify.busy = nil end
		if item.sentMs then gNotify.lastSentMs = item.sentMs end
		Finish(item, ok, why)
		NotifyPump()
	end)
end

local function Enqueue(item)
	local q = gNotify.queue
	if #q >= QUEUE_MAX then
		-- Full: the newest one waiting that is not a doorbell or the alarm gives way to the new one.
		-- Only doorbells and alarms waiting: a new doorbell or alarm pushes out the oldest of them,
		-- anything else is dropped.
		local drop
		for j = #q, 1, -1 do
			if not Urgent(q[j]) then drop = j break end
		end
		if not drop and not Urgent(item) then
			return Finish(item, false, "too many notifications at once")
		end
		drop = drop or 1
		local old = table.remove(q, drop)
		Finish(old, false, "too many notifications at once")
	end
	q[#q + 1] = item
	NotifyPump()
end

-- The picture, fetched by the driver: item.pictureData = "data:image/jpeg;base64,..." when it comes in
-- time, is a picture and is not too large; else the pop-up carries the address (item.picture).
local function FetchPicture(item, url)
	item.picturePending = true
	local function done(data, why)
		if not item.picturePending then return end
		item.picturePending = false
		KillTimer("PICTURE_" .. item.seq)
		if data then
			item.pictureData = data
		else
			LogDebug("The picture goes as its address (%s): %s", why, Describe(item))
		end
		NotifyPump()
	end
	SetTimer("PICTURE_" .. item.seq, PICTURE_WAIT_MS, function() done(nil, "not fetched within " .. (PICTURE_WAIT_MS / 1000) .. " s") end)
	local ok, err = pcall(function()
		local x = C4:url()
		x:SetOptions({ fail_on_error = false, timeout = math.ceil(PICTURE_WAIT_MS / 1000), connect_timeout = 1 })
		x:OnDone(function(_, responses, errCode, errMsg)
			local resp = responses and responses[#responses]
			if (errCode ~= nil and errCode ~= 0) or not resp then return done(nil, tostring(errMsg or errCode)) end
			local code, body = tonumber(resp.code) or 0, resp.body or ""
			if code ~= 200 then return done(nil, "HTTP " .. code) end
			local kind = PictureType(body)
			if not kind then return done(nil, "not a picture") end
			if #body > PICTURE_MAX_BYTES then return done(nil, ByteSize(#body) .. ", more than " .. ByteSize(PICTURE_MAX_BYTES)) end
			LogDebug("The picture: %s, %s", kind, ByteSize(#body))
			done("data:" .. kind .. ";base64," .. Base64Encode(body))
		end)
		x:Get(url, {})
	end)
	if not ok then done(nil, tostring(err)) end
end

--[[------------------------------------------------------------------ Entry
    n = { source = "DirectorLink" | "programming" | "test", id, kind, title,
          message, picture }. Returns true when it is on its way to the TV.  ]]
function NotifyAccept(n)
	gNotify.seq = gNotify.seq + 1
	local item = {
		seq = gNotify.seq, source = n.source or "programming", id = n.id, kind = n.kind,
		title = CutUtf8(trim(n.title), TITLE_MAX_BYTES), message = CutUtf8(trim(n.message), TOAST_MAX_BYTES),
		text = ToastText(n.title, n.message), at = NowMs(),
	}
	if item.text == "" then
		Skip(item, "no title and no message")
		return false
	end
	-- The same ID again (DirectorLink sends each notification once per target; a repeat is the same one)
	if item.id and item.id ~= "" then
		local seenAt = gNotify.seen[item.id]
		if seenAt and item.at - seenAt < DEDUPE_MS then
			Skip(item, "a repeat of " .. item.id)
			return false
		end
		gNotify.seen[item.id] = item.at
		gNotify.seenOrder[#gNotify.seenOrder + 1] = { item.id, item.at }
		while #gNotify.seenOrder > DEDUPE_MAX do
			local old = table.remove(gNotify.seenOrder, 1)
			if gNotify.seen[old[1]] == old[2] then gNotify.seen[old[1]] = nil end
		end
	end
	if item.source == "DirectorLink" and not KindOn(item.kind) then
		Skip(item, KIND_PROPERTY[item.kind] .. " is Off")
		return false
	end
	if item.source ~= "test" and InQuietHours() then
		Skip(item, "Quiet Hours " .. trim(Properties["Quiet Hours"]))
		return false
	end
	if n.picture and trim(n.picture) ~= "" then
		if Properties["Pictures"] ~= "On" then
			LogDebug("Without its picture (Pictures is Off): %s", Describe(item))
		else
			item.picture = PictureUrl(n.picture)
			if item.picture then
				FetchPicture(item, trim(n.picture))
			else
				LogWarn("Without its picture (not an http address: %s): %s", n.picture, Describe(item))
			end
		end
	end
	Enqueue(item)
	return true
end

-- Forget what waits (Pair Again, a new address): each fails at once
function NotifyFlush(why)
	local q = gNotify.queue
	gNotify.queue = {}
	for _, item in ipairs(q) do Finish(item, false, why) end
end

-- The TV can take the next one (it just became ready)
function NotifyKick()
	NotifyPump()
end
