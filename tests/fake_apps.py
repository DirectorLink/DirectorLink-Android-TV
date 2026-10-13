"""PiPup for the tests, as "PiPup - TV Notifications" by Alexander Savin (Google Play
nyc.savin.pipup) answers: its "How to use" page (https://pipup.android.savin.nyc/how-to-use.html),
its maker's Home Assistant integration (github.com/alex-savin/hassio-integration-pipup-notification)
and what PiPup 0.3.4 answered on a real Sony TV (2026-10-13). And the SSDP answers of casting
devices.

- FakePiPup (port 7979): GET /ping "pipup 0.3.4"; GET /status {"version","id","name","port",
  "active","count","screenOn","uptimeSeconds","authEnabled"} (no token needed); GET /state is
  not PiPup's ("not found: /state", 404); POST /notify with JSON -> {"status":"ok","id":...};
  with a token set, every request but /ping and /status needs "Authorization: Bearer <token>"
  (401); blocked (the IP allowlist without the controller): 403.
- running (False: the connection is refused at once), network (False: no answer at all, the TV
  off or gone), delay_ms (how long it takes to answer).
- FakeSSDP: casting devices answering the DIAL search, each with its description.
"""
import json


class FakePiPup:
    """PiPup - TV Notifications (nyc.savin.pipup) on port 7979."""
    port = 7979

    def __init__(self, ip="192.168.50.50", name="SONY XR-77A95L"):
        self.ip = ip
        self.name = name
        self.running = True
        self.network = True
        self.delay_ms = 30
        self.screen_on = True
        self.token = ""          # set in PiPup's settings: requests need it
        self.blocked = False     # the IP allowlist leaves the controller out
        self.has_status = True
        self.requests = []       # (method, path, headers, body)
        self.shown = []          # the /notify JSON bodies taken

    def attach(self, d):
        d.serve(f"{self.ip}:{self.port}", self)
        return self

    def status(self):
        return {"version": "0.3.4", "id": "4613e383-04aa-3839-be1d-57ddd9a0e209", "name": self.name, "port": self.port,
                "active": False, "count": len(self.shown), "screenOn": self.screen_on, "uptimeSeconds": 517,
                "authEnabled": self.token != ""}

    def http(self, method, path, headers, body):
        self.requests.append((method, path, headers, body))
        if not self.network:
            return ("silent",)
        if not self.running:
            return ("refused",)
        if self.blocked:
            return ("ok", 403, {"Content-Type": "text/plain"}, b"forbidden", self.delay_ms)
        route = path.split("?")[0]
        if method == "GET" and route == "/ping":
            return ("ok", 200, {"Content-Type": "text/plain"}, b"pipup 0.3.4", self.delay_ms)
        if method == "GET" and route == "/status":
            if not self.has_status:
                return ("ok", 404, {"Content-Type": "text/plain"}, b"not found: /status", self.delay_ms)
            return ("ok", 200, {"Content-Type": "application/json"}, json.dumps(self.status()).encode(), self.delay_ms)
        if self.token:
            auth = next((v for k, v in headers.items() if k.lower() == "authorization"), "")
            if auth != f"Bearer {self.token}":
                return ("ok", 401, {"Content-Type": "text/plain"}, b"unauthorized", self.delay_ms)
        if method == "POST" and route == "/notify":
            ct = next((v for k, v in headers.items() if k.lower() == "content-type"), "")
            if not ct.startswith("application/json"):
                return ("ok", 400, {}, b"invalid request: content type", self.delay_ms)
            try:
                popup = json.loads(body.decode("utf-8"))
            except ValueError:
                return ("ok", 400, {}, b"invalid request: json", self.delay_ms)
            self.shown.append(popup)
            return ("ok", 200, {"Content-Type": "application/json"},
                    json.dumps({"status": "ok", "id": popup.get("id", "p1")}).encode(), self.delay_ms)
        if route.startswith("/power"):
            raise AssertionError("the driver must never ask PiPup to turn the screen on or off")
        return ("ok", 404, {"Content-Type": "text/plain"}, f"not found: {route}".encode(), self.delay_ms)


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


JPEG = (b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
        b"\xff\xc0\x00\x11\x08\x01\x68\x02\x80\x03\x01\x22\x00\x02\x11\x01\x03\x11\x01" + bytes(range(256)) * 20 + b"\xff\xd9")


class FakePictures:
    """A picture server (the controller's, as DirectorLink's PICTURE, or a camera's): path -> answer."""

    def __init__(self, pictures=None, delay_ms=20):
        self.pictures = pictures or {}   # path -> bytes (200), or (code, bytes)
        self.delay_ms = delay_ms
        self.requests = []

    def http(self, method, path, headers, body):
        self.requests.append(path)
        v = self.pictures.get(path)
        if v is None:
            return ("ok", 404, {}, b"not found", self.delay_ms)
        code, data = v if isinstance(v, tuple) else (200, v)
        return ("ok", code, {"Content-Type": "image/jpeg"}, data, self.delay_ms)
