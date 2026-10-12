--[[=============================================================================
    DirectorLink Android TV Notifications - finding TVs (SSDP)
    An SSDP search (UDP to 239.255.255.250:1900) for DIAL, the service every
    Android TV, Google TV, Chromecast and Fire TV announces for casting:
        ST: urn:dial-multiscreen-org:service:dial:1
    The same way DirectorLink finds Sonos players (driver/src/sonos/client.lua
    at https://github.directorlink.io), as Snap One's own SSDP module does it:
    a UDP network connection to the multicast address, the search sent three
    times when Director says it is up (a second later in any case), and the
    answers in ReceivedFromNetwork. Director does not say who sent an answer,
    so the device's address is read from its LOCATION, and its name, maker
    and model from the description there (<friendlyName>, <manufacturer>,
    <modelName>), read once for each device, from the home network only.

    Some casting receivers that are not TVs answer too. driver.lua asks each
    device found whether the chosen app answers on it.

    SsdpSearch(onDone) -> onDone({ { ip, name, maker, model, location }, ... }) after SSDP_SECONDS

    Copyright 2026 DirectorLink
    SPDX-License-Identifier: Apache-2.0
===============================================================================]]

SSDP_BINDING = 6100
SSDP_ADDRESS = "239.255.255.250"
SSDP_PORT = 1900
SSDP_TARGET = "urn:dial-multiscreen-org:service:dial:1"
SSDP_SECONDS = 5
SSDP_MAX = 24
SSDP_SENDS = 3

gSsdp = { search = nil, created = false, lastFound = {}, lastAt = nil }

function SsdpRequest()
	return "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: "
		.. SSDP_TARGET .. "\r\n\r\n"
end

-- A private IPv4 address of the home network (10.x, 172.16-31.x, 192.168.x, 169.254.x)
function PrivateIPv4(ip)
	if not IsIPv4(ip) then return false end
	local a, b = string.match(ip, "^(%d+)%.(%d+)%.")
	a, b = tonumber(a), tonumber(b)
	return a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) or (a == 169 and b == 254)
end

-- The devices in an SSDP answer (one datagram, or several run together)
function SsdpReplies(data)
	local out = {}
	for chunk in (tostring(data or "") .. "\nHTTP/1.1 "):gmatch("(.-)\n[Hh][Tt][Tt][Pp]/1%.1 ") do
		local headers = {}
		for line in (chunk .. "\n"):gmatch("([^\n]*)\n") do
			local name, value = string.match(line, "^([%w%.%-_]+):(.*)$")
			if name then headers[string.upper(name)] = trim(value) end
		end
		local target = headers.ST or headers.NT
		local location = headers.LOCATION or ""
		local ip = string.match(location, "^[hH][tT][tT][pP]://(%d+%.%d+%.%d+%.%d+)[:/]")
		if target == SSDP_TARGET and ip and PrivateIPv4(ip) then
			out[#out + 1] = { ip = ip, usn = headers.USN, location = location }
		end
	end
	return out
end

local function Send()
	local s = gSsdp.search
	if not s or s.sent then return end
	s.sent = true
	local msg = SsdpRequest()
	pcall(function()
		for _ = 1, SSDP_SENDS do C4:SendToNetwork(SSDP_BINDING, SSDP_PORT, msg) end
	end)
	LogDebug("Looking for TVs (SSDP %s)", SSDP_TARGET)
end

function XmlText(xml, tag)
	local v = string.match(xml or "", "<" .. tag .. ">%s*(.-)%s*</" .. tag .. ">")
	if not v or v == "" then return nil end
	v = string.gsub(v, "&lt;", "<")
	v = string.gsub(v, "&gt;", ">")
	v = string.gsub(v, "&quot;", '"')
	v = string.gsub(v, "&apos;", "'")
	v = string.gsub(v, "&#39;", "'")
	return (string.gsub(v, "&amp;", "&"))
end

-- The device's name, maker and model from its description (only from the address that answered)
local function ReadDescription(dev)
	if string.match(dev.location or "", "^http://([%d%.]+)[:/]") ~= dev.ip then return end
	pcall(function()
		local x = C4:url()
		x:SetOptions({ fail_on_error = false, timeout = 3, connect_timeout = 2 })
		x:OnDone(function(_, responses, errCode)
			local resp = responses and responses[#responses]
			if (errCode ~= nil and errCode ~= 0) or not resp or tonumber(resp.code) ~= 200 then return end
			local function field(tag)
				local v = XmlText(resp.body, tag)
				return (v and #v <= 80) and v or nil
			end
			dev.name, dev.maker, dev.model = field("friendlyName"), field("manufacturer"), field("modelName")
		end)
		x:Get(dev.location, {})
	end)
end

local function End()
	local s = gSsdp.search
	if not s then return nil end
	gSsdp.search = nil
	KillTimer("SSDP_SEND")
	KillTimer("SSDP_END")
	pcall(function() C4:NetDisconnect(SSDP_BINDING, SSDP_PORT) end)
	return s
end

function SsdpSearch(onDone)
	End()
	gSsdp.search = { onDone = onDone, sent = false, found = {}, byIp = {} }
	local ok, err = pcall(function()
		if not gSsdp.created then
			C4:CreateNetworkConnection(SSDP_BINDING, SSDP_ADDRESS)
			gSsdp.created = true
		end
		C4:NetConnect(SSDP_BINDING, SSDP_PORT, "UDP")
	end)
	if not ok then
		End()
		LogWarn("Find TVs: cannot search the network (%s)", tostring(err))
		if onDone then onDone({}, tostring(err)) end
		return false
	end
	SetTimer("SSDP_SEND", 1000, Send)
	SetTimer("SSDP_END", SSDP_SECONDS * 1000, function()
		local s = End()
		if not s then return end
		gSsdp.lastFound, gSsdp.lastAt = s.found, NowMs()
		if s.onDone then s.onDone(s.found) end
	end)
	return true
end

-- Director: OnConnectionStatusChanged / ReceivedFromNetwork for the search's binding (true when it was)
function SsdpStatus(binding, status)
	if tonumber(binding) ~= SSDP_BINDING then return false end
	if string.upper(tostring(status or "")) == "ONLINE" then Send() end
	return true
end

function SsdpData(binding, data)
	if tonumber(binding) ~= SSDP_BINDING then return false end
	local s = gSsdp.search
	if not s or type(data) ~= "string" or string.find(data, "M-SEARCH", 1, true) then return true end
	for _, dev in ipairs(SsdpReplies(data)) do
		if not s.byIp[dev.ip] and #s.found < SSDP_MAX then
			s.byIp[dev.ip] = true
			s.found[#s.found + 1] = dev
			LogDebug("Found a casting device at %s", dev.ip)
			ReadDescription(dev)
		end
	end
	return true
end
