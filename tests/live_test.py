"""Live test: the real driver code against a real TV, from a computer on the same network.

    python tests/live_test.py find                               # Find TVs: the driver's own search, over real UDP
    python tests/live_test.py <TV IP> [picture URL] [token=...]   # check PiPup, Print Diagnostics, pop-ups
    python tests/live_test.py alltvs <TV IP> [picture URL]        # Send To All TVs, with one TV: two copies on it

Runs the assembled driver.lua in the harness (Lua 5.1 and the fake Director) with its
requests made for real: HTTP to PiPup on the TV (and to the casting devices' descriptions),
UDP for the search. The driver's clock follows the real one. Not part of CI.

The pop-ups: Test Notification, a DIRECTORLINK_NOTIFY doorbell in Hebrew (with the picture
URL, when given: an address the TV can open, for example a camera's snapshot), and Show
Notification with the same picture.

alltvs: two copies of the driver (Living Room TV and Bedroom TV), both pointing at the one TV,
with the Director's part played here: C4:GetDevicesByC4iName answers { [device id] = name } as
Director does, and what one copy sends with C4:SendToDevice reaches the other's ExecuteCommand.
Show Notification with Send To = All TVs on one copy shows on the TV twice, one from each copy.
"""
import http.client
import re
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
    if parts.scheme == "https":
        conn = http.client.HTTPSConnection(parts.hostname, parts.port or 443, timeout=CONNECT_S)
    else:
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
    def __init__(self, props, device_id=900, label="", setup=""):
        offset_h = round(time.localtime().tm_gmtoff / 3600)
        self.d = Driver(props=props, http=real_http, device_id=device_id, now_ms=int(time.time() * 1000), tz_offset_h=offset_h)
        self.udp = Udp(self.d)
        self.label = label
        self.seen = 0
        self.last = time.time()
        if setup:
            self.d.run(setup)
        self.d.start()

    def logs(self):
        lines = self.d.logs()
        new, self.seen = lines[self.seen:], len(lines)
        prev = None
        for line in new:
            if line != prev:
                print("   " + (f"[{self.label}] " if self.label else "") + line)
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


def show(ip, picture, token):
    live = Live({"TV IP Address": ip, "PiPup Token": token or "", "Log Level": "Trace"})
    d = live.d
    print(f"\n== Checking PiPup at {ip}")
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


ROOMS = ((900, "Living Room TV", "Top Right"), (905, "Bedroom TV", "Bottom Left"))


def pipup_count(ip, token):
    """How many pop-ups PiPup has on the screen now (its /status count)."""
    answer = real_http("GET", f"http://{ip}:7979/status", {"Authorization": f"Bearer {token}"} if token else {}, None)
    if answer[0] != "ok":
        return None
    match = re.search(rb'"count"\s*:\s*(\d+)', answer[3])
    return int(match.group(1)) if match else None


def route(live, copies):
    """The Director: what a copy sends with C4:SendToDevice reaches that device's ExecuteCommand."""
    sent = list(live.d.g.SENT_TO_DEVICE.values())
    if not sent:
        return
    live.d.run("SENT_TO_DEVICE = {}")
    for e in sent:
        params = {lua_bytes(k).decode(): lua_bytes(v) for k, v in dict(e.params).items()}
        cmd = lua_bytes(e.cmd).decode()
        target = copies.get(int(e.id))
        shown = {k: v.decode("utf-8") for k, v in params.items()}
        print(f"   [Director] {live.label} -> SendToDevice({int(e.id)}, {cmd}, {shown})")
        if target:
            target.d.command(cmd, params)


def run_all(copies, seconds, until=None):
    end = time.time() + seconds
    while time.time() < end:
        time.sleep(0.05)
        now = time.time()
        for live in copies.values():
            live.d.pump(int((now - live.last) * 1000))
            live.last = now
            route(live, copies)
            live.logs()
        if until and until():
            return True
    return False


def all_tvs(ip, picture, token):
    names = ", ".join(f'[{dev}] = "{room}"' for dev, room, _ in ROOMS)
    copies = {}
    for dev, room, position in ROOMS:
        props = {"TV IP Address": ip, "PiPup Token": token or "", "Position": position, "Log Level": "Debug"}
        # Director: the room's name, and every copy of the driver file as { [device id] = name }
        setup = (f'DISPLAY_NAME = "{room}"; DEVICES_BY_FILE["DirectorLink-Android-TV.c4z"] = {{ {names} }}; '
                 f'DEVICE_NAMES = {{ {names} }}')
        copies[dev] = Live(props, device_id=dev, label=room, setup=setup)
    living, bedroom = copies[900], copies[905]
    print(f"\n== Two copies of the driver, both on the TV at {ip}")
    run_all(copies, 10, until=lambda: all(c.d.prop("Status") not in ("Starting...", "Checking...") for c in copies.values()))
    for c in copies.values():
        print(f"   {c.label}: Status {c.d.prop('Status')}, TV {c.d.prop('TV')}")
    if any(c.d.prop("Status") != "Ready" for c in copies.values()):
        return False
    results = []

    print("\n== 1. Living Room TV: Show Notification, Send To = All TVs")
    for c in copies.values():
        c.d.clear()
        c.seen = 0
    living.d.command("SHOW_NOTIFICATION", {"Title": "Send To: All TVs", "Message": "From Living Room TV, to every TV",
                                           "Picture URL": picture or "", "Send To": "All TVs"})
    run_all(copies, 25, until=lambda: all(c.d.events() for c in copies.values()))
    on_screen = pipup_count(ip, token)
    ev = {c.label: c.d.events() for c in copies.values()}
    print(f"   Events: {ev}")
    # PiPup shows one pop-up at a time: on one TV the second copy's replaces the first's (count 1)
    print(f"   PiPup has {on_screen} pop-up(s) on the screen now (one TV: Bedroom TV's replaced Living Room TV's)")
    results.append(("All TVs: shown by both copies", all(e and e[0] == "Notification Shown" for e in ev.values())))

    print("\n== 2. Bedroom TV: Show Notification, Send To = This TV")
    for c in copies.values():
        c.d.clear()
        c.seen = 0
    bedroom.d.command("SHOW_NOTIFICATION", {"Title": "Send To: This TV", "Message": "Bedroom TV only",
                                            "Picture URL": "", "Send To": "This TV"})
    run_all(copies, 25, until=lambda: bedroom.d.events())
    run_all(copies, 3)
    ev = {c.label: c.d.events() for c in copies.values()}
    print(f"   Events: {ev}")
    results.append(("This TV: shown by Bedroom TV only", bool(ev["Bedroom TV"]) and not ev["Living Room TV"]))

    print()
    for label, ok in results:
        print(("PASS  " if ok else "FAIL  ") + label)
    return all(ok for _, ok in results)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if sys.argv[1] == "find":
        find()
    elif sys.argv[1] == "alltvs":
        args = sys.argv[3:]
        pic = next((a for a in args if a.startswith("http")), None)
        tok = next((a[len("token="):] for a in args if a.startswith("token=")), None)
        sys.exit(0 if all_tvs(sys.argv[2], pic, tok) else 1)
    else:
        args = sys.argv[2:]
        pic = next((a for a in args if a.startswith("http")), None)
        tok = next((a[len("token="):] for a in args if a.startswith("token=")), None)
        show(sys.argv[1], pic, tok)
