"""The TV apps for the tests, as the open-source clients (Home Assistant, FHEM) and PiPup's own
documentation describe them, and the SSDP answers of casting devices.

- FakeNfa: "Notifications for Android TV" on port 7676. GET / answers (Home Assistant's
  check); POST / takes multipart/form-data with msg (needed), title, duration, position,
  bkgcolor, transparency, interrupt, imageurl and the icon as the file part "filename".
  The form is parsed strictly (boundary, CRLF, closing delimiter); every field is kept as text.
- FakePiPup: PiPup (the maintained fork) on port 7979. GET /state (screenOn, permissions.overlay,
  device, name, version); POST /notify with JSON, 200 once the pop-up is on the screen.
- Each: running (False: the connection is refused at once), network (False: no answer at all,
  the TV off or gone), delay_ms (how long it takes to answer).
- FakeSSDP: casting devices answering the DIAL search, each with its description.
"""
import json
import re


class FakeApp:
    port = 0

    def __init__(self, ip="192.168.50.50"):
        self.ip = ip
        self.running = True
        self.network = True
        self.delay_ms = 30
        self.requests = []   # (method, path, headers, body)

    def attach(self, d):
        d.serve(f"{self.ip}:{self.port}", self)
        return self

    def gate(self, method, path, headers, body):
        self.requests.append((method, path, headers, body))
        if not self.network:
            return ("silent",)
        if not self.running:
            return ("refused",)
        return None


def parse_multipart(content_type, body):
    """Strict multipart/form-data: {name: (headers dict, bytes)} or raises."""
    m = re.match(r"multipart/form-data;\s*boundary=(\S+)$", content_type or "")
    if not m:
        raise ValueError(f"not multipart/form-data with a boundary: {content_type!r}")
    boundary = m.group(1).encode()
    if not body.startswith(b"--" + boundary + b"\r\n"):
        raise ValueError("the body does not start with the boundary")
    if not body.endswith(b"--" + boundary + b"--\r\n"):
        raise ValueError("the body does not end with the closing delimiter")
    parts = {}
    for chunk in body.split(b"--" + boundary)[1:-1]:
        if not chunk.startswith(b"\r\n") or not chunk.endswith(b"\r\n"):
            raise ValueError("a part is not framed by CRLF")
        head, _, data = chunk[2:-2].partition(b"\r\n\r\n")
        headers = {}
        for line in head.split(b"\r\n"):
            k, _, v = line.decode("latin-1").partition(":")
            headers[k.strip().lower()] = v.strip()
        name = re.search(r'name="([^"]+)"', headers.get("content-disposition", ""))
        if not name:
            raise ValueError("a part without a name")
        parts[name.group(1)] = (headers, data)
    return parts


class FakeNfa(FakeApp):
    """Notifications for Android TV (port 7676)."""
    port = 7676

    def __init__(self, ip="192.168.50.50"):
        super().__init__(ip)
        self.shown = []          # the notifications taken: {field: text}, plus "icon" bytes
        self.status = 200

    def http(self, method, path, headers, body):
        g = self.gate(method, path, headers, body)
        if g:
            return g
        if method == "GET" and path == "/":
            return ("ok", 200, {"Content-Type": "text/html"}, b"<html>Notifications for Android TV</html>", self.delay_ms)
        if method == "POST" and path == "/":
            ct = next((v for k, v in headers.items() if k.lower() == "content-type"), "")
            try:
                parts = parse_multipart(ct, body)
            except ValueError as e:
                return ("ok", 400, {}, str(e).encode(), self.delay_ms)
            if "msg" not in parts:
                return ("ok", 400, {}, b"msg missing", self.delay_ms)
            note = {k: v[1].decode("utf-8") for k, v in parts.items() if k != "filename"}
            if "filename" in parts:
                note["icon"] = parts["filename"][1]
                note["icon_headers"] = parts["filename"][0]
            if self.status == 200:
                self.shown.append(note)
            return ("ok", self.status, {}, b"", self.delay_ms)
        return ("ok", 404, {}, b"", self.delay_ms)


class FakePiPup(FakeApp):
    """PiPup, the maintained fork (port 7979)."""
    port = 7979

    def __init__(self, ip="192.168.50.50"):
        super().__init__(ip)
        self.screen_on = True
        self.overlay = True
        self.has_state = True
        self.shown = []          # the /notify JSON bodies taken

    def state(self):
        return {
            "app": "PiPup", "version": "0.26.1", "id": "6f1f9c1e-4a3f", "name": "Family Room TV",
            "visible": False, "screenOn": self.screen_on, "popupsShown": len(self.shown), "uptime": 86400,
            "device": {"model": "BRAVIA 4K VH21", "manufacturer": "Sony", "android": "12"},
            "power": {"canWake": True, "canSleep": False},
            "permissions": {"overlay": self.overlay, "installPackages": True, "autoStart": None, "complete": self.overlay},
        }

    def http(self, method, path, headers, body):
        g = self.gate(method, path, headers, body)
        if g:
            return g
        if path == "/state" and method in ("GET", "POST"):
            if not self.has_state:
                return ("ok", 404, {}, b"Not Found", self.delay_ms)
            return ("ok", 200, {"Content-Type": "application/json"}, json.dumps(self.state()).encode(), self.delay_ms)
        if path == "/notify" and method == "POST":
            ct = next((v for k, v in headers.items() if k.lower() == "content-type"), "")
            if not ct.startswith("application/json"):
                return ("ok", 400, {}, b"invalid request: content type", self.delay_ms)
            try:
                popup = json.loads(body.decode("utf-8"))
            except ValueError:
                return ("ok", 400, {}, b"invalid request: json", self.delay_ms)
            self.shown.append(popup)
            return ("ok", 200, {"Content-Type": "text/plain"}, body, self.delay_ms)
        if path.startswith("/power"):
            raise AssertionError("the driver must never use /power")
        return ("ok", 404, {}, b"Not Found", self.delay_ms)


class FakeSSDP:
    """Casting devices answering the DIAL search (unicast to the search's binding), each with its
    description at its LOCATION (port 8008, as a Chromecast or Google TV serves it)."""

    def __init__(self, devices):
        self.devices = devices  # dicts: ip, name, maker, model, standby
        self.searches = []
        self.described = []

    def net(self, d, op, binding, port, data):
        if op == "connect":
            d.deliver(5, "status", binding, port, "ONLINE")
        elif op == "send":
            text = data.decode("latin-1")
            self.searches.append(text)
            if "ST: urn:dial-multiscreen-org:service:dial:1" not in text:
                return
            for i, dev in enumerate(self.devices):
                if dev.get("standby"):
                    continue
                reply = (
                    "HTTP/1.1 200 OK\r\n"
                    "CACHE-CONTROL: max-age=1800\r\n"
                    "EXT:\r\n"
                    f"LOCATION: http://{dev['ip']}:8008/ssdp/device-desc.xml\r\n"
                    "SERVER: Linux/3.8.13+, UPnP/1.0, Portable SDK for UPnP devices/1.6.18\r\n"
                    "ST: urn:dial-multiscreen-org:service:dial:1\r\n"
                    f"USN: uuid:{i:08d}-0000-0000-0000-000000000000::urn:dial-multiscreen-org:service:dial:1\r\n"
                    "\r\n"
                )
                d.deliver(40 + 25 * i, "data", binding, port, reply.encode("latin-1"))


class Description:
    """A device's DIAL description (friendlyName, manufacturer, modelName) on port 8008."""

    def __init__(self, ssdp, dev):
        self.ssdp, self.dev = ssdp, dev

    def http(self, method, path, headers, body):
        self.ssdp.described.append(self.dev["ip"])
        if path != "/ssdp/device-desc.xml":
            return ("ok", 404, {}, b"", 10)
        esc = lambda s: s.replace("&", "&amp;").replace("<", "&lt;")  # noqa: E731
        name = f"<friendlyName>{esc(self.dev['name'])}</friendlyName>" if self.dev.get("name") else ""
        xml = ('<?xml version="1.0"?><root xmlns="urn:schemas-upnp-org:device-1-0"><device>'
               "<deviceType>urn:dial-multiscreen-org:device:dial:1</deviceType>" + name
               + f"<manufacturer>{esc(self.dev.get('maker', ''))}</manufacturer>"
               + f"<modelName>{esc(self.dev.get('model', ''))}</modelName>"
               + "<UDN>uuid:00000000-0000</UDN></device></root>")
        return ("ok", 200, {"Content-Type": "text/xml"}, xml.encode("utf-8"), 10)


def attach_ssdp(d, devices):
    """FakeSSDP plus each device's description server."""
    ssdp = FakeSSDP(devices)
    d.listen("239.255.255.250", 1900, ssdp)
    for dev in devices:
        d.serve(f"{dev['ip']}:8008", Description(ssdp, dev))
    return ssdp
