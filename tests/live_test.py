"""Live test: the real driver code against a real TV, from a computer on the same network.

    python tests/live_test.py find                                # Find TVs: the driver's own search, over real UDP
    python tests/live_test.py <TV IP> [nfa|pipup] [picture URL]   # check the app, Print Diagnostics, pop-ups

Runs the assembled driver.lua in the harness (Lua 5.1 and the fake Director) with its
requests made for real: HTTP to the TV's app (and to the casting devices' descriptions),
UDP for the search. The driver's clock follows the real one. Not part of CI.

The pop-ups: Test Notification, a DIRECTORLINK_NOTIFY doorbell in Hebrew (with the picture
URL, when given: an address the TV can open, for example a camera's snapshot), and Show
Notification with the same picture.
"""
import http.client
import select
import socket
import sys
import time
from urllib.parse import urlsplit

from harness import Driver, lua_bytes

HE_TITLE, HE_MESSAGE = "דלת הכניסה", "מישהו מצלצל בדלת"
CONNECT_S = 3


def real_http(method, url, headers, body):
    """C4:url, made real: refused at once, no connection within 3 s, or the answer."""
    parts = urlsplit(url)
    path = parts.path or "/"
    if parts.query:
        path += "?" + parts.query
    conn = http.client.HTTPConnection(parts.hostname, parts.port or 80, timeout=CONNECT_S)
    try:
        conn.connect()
    except ConnectionRefusedError:
        return ("refused",)
    except OSError as e:
        print(f"   [http] {parts.hostname}:{parts.port}: {e}")
        return ("silent",)
    try:
        conn.sock.settimeout(20)
        started = time.time()
        conn.request(method, path, body=body, headers={str(k): str(v) for k, v in (headers or {}).items()})
        r = conn.getresponse()
        data = r.read()
        took = int((time.time() - started) * 1000)
        print(f"   [http] {method} {parts.hostname}:{parts.port}{path} -> {r.status} ({took} ms)")
        return ("ok", r.status, dict(r.getheaders()), data, 5)
    except OSError as e:
        print(f"   [http] {method} {url}: {e}")
        return ("silent",)
    finally:
        conn.close()


class Udp:
    """The SSDP search's network connection, made real."""

    def __init__(self, d):
        self.d = d
        self.sock = None
        d.listen("239.255.255.250", 1900, self)

    def net(self, d, op, binding, port, data):
        if op == "connect":
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
            s.bind(("", 0))
            s.setblocking(False)
            self.sock, self.binding, self.port = s, binding, port
            d.deliver(0, "status", binding, port, "ONLINE")
        elif op == "send" and self.sock:
            self.sock.sendto(data, ("239.255.255.250", 1900))
        elif op == "disconnect" and self.sock:
            self.sock.close()
            self.sock = None

    def poll(self, timeout=0.05):
        if not self.sock:
            time.sleep(timeout)
            return
        ready, _, _ = select.select([self.sock], [], [], timeout)
        while ready:
            try:
                data, _ = self.sock.recvfrom(65536)
            except (BlockingIOError, OSError):
                break
            self.d.deliver(0, "data", self.binding, self.port, data)


class Live:
    def __init__(self, props):
        offset_h = round(time.localtime().tm_gmtoff / 3600)
        self.d = Driver(props=props, http=real_http, now_ms=int(time.time() * 1000), tz_offset_h=offset_h)
        self.udp = Udp(self.d)
        self.seen = 0
        self.last = time.time()
        self.d.start()

    def logs(self):
        lines = self.d.logs()
        new, self.seen = lines[self.seen:], len(lines)
        prev = None
        for line in new:
            if line != prev:
                print("   " + line)
            prev = line

    def run(self, seconds, until=None):
        end = time.time() + seconds
        while time.time() < end:
            self.udp.poll()
            now = time.time()
            self.d.pump(int((now - self.last) * 1000))
            self.last = now
            self.logs()
            if until and until():
                return True
        return False


def find():
    live = Live({"Log Level": "Debug"})
    live.run(12)
    print("\nTVs Found:", live.d.prop_list("TVs Found"))


def show(ip, app, picture):
    live = Live({"TV IP Address": ip, "TV App": "PiPup" if app == "pipup" else "Notifications for Android TV", "Log Level": "Trace"})
    d = live.d
    print(f"\n== Checking {ip} ({d.prop('TV App')})")
    live.run(8, until=lambda: d.prop("Status") not in ("Starting...", "Checking..."))
    print(f"\n== Status: {d.prop('Status')}   TV: {d.prop('TV')}")
    if d.prop("Status") != "Ready":
        d.action("PrintDiagnostics")
        live.logs()
        return
    print("\n== Test Notification")
    d.action("TestNotification")
    live.run(20, until=lambda: d.events())
    print("\n== DIRECTORLINK_NOTIFY doorbell, in Hebrew" + (" with the picture" if picture else ""))
    params = {"VERSION": "1", "ID": f"live-{int(time.time())}", "KIND": "doorbell", "TITLE": HE_TITLE, "MESSAGE": HE_MESSAGE}
    if picture:
        params["PICTURE"] = picture
    d.command("DIRECTORLINK_NOTIFY", params)
    live.run(25, until=lambda: len(d.events()) >= 2)
    print("\n== Show Notification" + (" with the picture" if picture else ""))
    d.command("SHOW_NOTIFICATION", {"Title": "Gate", "Message": "Opened", "Picture URL": picture or ""})
    live.run(25, until=lambda: len(d.events()) >= 3)
    print("\n== Events:", d.events(), "\n== LAST_NOTIFICATION:", d.var("LAST_NOTIFICATION"))
    d.action("PrintDiagnostics")
    live.logs()
    print("\nLook at the TV: three pop-ups (the Hebrew one right to left" + (", the last two with the picture)." if picture else ")."))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if sys.argv[1] == "find":
        find()
    else:
        args = sys.argv[2:]
        app = "pipup" if "pipup" in args else "nfa"
        pic = next((a for a in args if a.startswith("http")), None)
        show(sys.argv[1], app, pic)
