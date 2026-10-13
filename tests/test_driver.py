"""The driver against PiPup (offline).   python tests/test_driver.py

The real driver code in Lua 5.1, a fake Director (harness.py) and a fake PiPup (fake_apps.py,
"PiPup - TV Notifications" by Alexander Savin as it answers): /status before each pop-up (the
screen on, a token wanted), /notify, a token (401), the IP allowlist (403), a TV that is off (no
answer), PiPup not running (refused at once), slow or refusing answers; pictures; the checks (every
minute, then 5 s, 30 s, 2 min, every 5 min); the DirectorLink notification agreement (variables,
both ways in, VERSION, KIND, ID repeats); the kinds, Quiet Hours, one pop-up every 5 s with a
doorbell or the alarm first; Find TVs.
"""
import json

import base64

from fake_apps import JPEG, FakePictures, FakePiPup, attach_ssdp
from harness import Driver, check, finish

IP = "192.168.50.50"
CTRL = "192.168.50.10"
HE_TITLE, HE_MESSAGE = "דלת הכניסה", "מישהו מצלצל בדלת"


def tv(props=None, persist=None, fake=None):
    """A driver set up for the TV at IP with PiPup: (driver, fake PiPup)."""
    p = {"TV IP Addresses": IP}
    p.update(props or {})
    d = Driver(props=p, persist=persist)
    fake = fake or FakePiPup(IP)
    fake.attach(d)
    d.start()
    d.pump(3000)
    return d, fake


def notify(d, kind="doorbell", nid=None, title="Front Door", message="Someone is at the door", via="ExecuteCommand", **extra):
    params = {"VERSION": "1", "KIND": kind, "TITLE": title, "MESSAGE": message}
    if nid is not None:
        params["ID"] = nid
    params.update(extra)
    if via == "ExecuteCommand":
        return d.command("DIRECTORLINK_NOTIFY", params)
    return d.from_proxy(5001, "DIRECTORLINK_NOTIFY", params)


def paths(fake, method=None):
    return [r[1] for r in fake.requests if method is None or r[0] == method]


# ============================================================ variables (the agreement)
d = Driver()
d.start()
check(d.var_order() == ["LAST_NOTIFICATION", "DIRECTORLINK_NOTIFY", "DIRECTORLINK_NOTIFY_KINDS"],
      f"variables in their fixed order: LAST_NOTIFICATION, then the agreement's ({d.var_order()})")
check(d.var("DIRECTORLINK_NOTIFY") == "1" and d.var("DIRECTORLINK_NOTIFY_KINDS") == "doorbell,alarm", "DIRECTORLINK_NOTIFY = 1; kinds doorbell,alarm by default")
check(d.prop("Status").startswith("Enter the TVs' IP addresses"), f"no address: Status says to enter them ({d.prop('Status')})")
d.set_prop("Camera Alerts", "On")
check(d.var("DIRECTORLINK_NOTIFY_KINDS") == "doorbell,camera,alarm", "a kind switched on: DIRECTORLINK_NOTIFY_KINDS follows")
d, app = tv()
d.command("SHOW_NOTIFICATION", {"Title": "Hello", "Message": "World"})
d.pump(1000)
d2 = Driver(props={"TV IP Addresses": IP, "Alarm": "Off"}, persist=d.persisted())
FakePiPup(IP).attach(d2)
d2.start()
check("DIRECTORLINK_NOTIFY" in list(d2.g.VAR_LOG.values()) and d2.var("DIRECTORLINK_NOTIFY_KINDS") == "doorbell", "a restart writes the agreement's variables again")
check(d2.var("LAST_NOTIFICATION") == "Hello: World" and d2.var_order()[0] == "LAST_NOTIFICATION", "LAST_NOTIFICATION comes back after a restart, same order")

# ============================================================ PiPup: checks and pop-ups
d, app = tv()
check(d.prop("Status") == "Ready", f"PiPup answers /status: Ready ({d.prop('Status')})")
check(d.prop("TVs") == f"SONY XR-77A95L ({IP}): Ready, PiPup 0.3.4", f"the TVs property from PiPup's /status ({d.prop('TVs')})")
check(paths(app)[:1] == ["/status"] and "/state" not in paths(app), "checked with GET /status on port 7979 (PiPup has no /state)")
d.clear()
n_status = paths(app).count("/status")
notify(d, title=HE_TITLE, message=HE_MESSAGE, nid="p-1", PICTURE="http://127.0.0.1:47200/notify/abc.jpg")
check(d.events() == [], "never blocks: DIRECTORLINK_NOTIFY returns before the TV answers")
d.pump(2500)
check(paths(app).count("/status") == n_status + 1, "before a pop-up, /status: is the screen on?")
popup = app.shown[-1] if app.shown else {}
check(popup.get("id") == "directorlink" and popup.get("duration") == 15 and popup.get("position") == 0 and popup.get("title") == HE_TITLE
      and popup.get("message") == HE_MESSAGE, f"POST /notify: Hebrew as given, 15 s, top right ({ {k: v for k, v in popup.items() if k != 'media'} })")
check(popup.get("media") == {"image": {"uri": f"http://{CTRL}:47200/notify/abc.jpg", "width": 640}},
      "no picture server answering: the pop-up carries the picture's address, at the controller's address")
req = [r for r in app.requests if r[1] == "/notify"][-1]
check(any(k.lower() == "content-type" and v.startswith("application/json") for k, v in req[2].items()), "JSON")
check(not any(k.lower() == "authorization" for k in req[2]), "no token set: no Authorization header")
check(d.events() == ["Notification Shown"] and d.event_vars() == [("Notification Shown", f"{HE_TITLE}: {HE_MESSAGE}")],
      "Notification Shown, LAST_NOTIFICATION set before it")
check(any("Shown on the TV: Doorbell" in l and "with its picture" in l for l in d.logs()), "one Info line, with its picture")
http = [r for r in d.http_log(IP) if r["url"].endswith("/notify")][-1]
check(http["opts"].get("connect_timeout") == 3, "the TV has 3 s to take the connection")
d.pump(5000)
d.clear()
notify(d, via="ReceivedFromProxy", nid="p-2", kind="alarm", title="Alarm", message="Burglary")
d.pump(6000)
check(app.shown[-1]["message"] == "Burglary" and d.events() == ["Notification Shown"], "DIRECTORLINK_NOTIFY by ReceivedFromProxy too")
d.clear()
d.command("SHOW_NOTIFICATION", {"Title": "Gate", "Message": "Opened", "Picture URL": "http://192.168.50.60/snapshot.jpg"})
d.pump(6000)
check(app.shown[-1]["media"]["image"]["uri"] == "http://192.168.50.60/snapshot.jpg" and app.shown[-1]["title"] == "Gate", "Show Notification with a Picture URL")
d.set_prop("Pictures", "Off")
notify(d, nid="p-3", PICTURE="http://127.0.0.1/x.jpg")
d.pump(6000)
check("media" not in app.shown[-1], "Pictures Off: no picture")
d.set_prop("Pictures", "On")
d.set_prop("Position", "Bottom Left")
d.set_prop("Seconds On Screen", "30")
notify(d, nid="p-4", PICTURE="ftp://nope/x.jpg")
d.pump(6000)
check(app.shown[-1]["position"] == 3 and app.shown[-1]["duration"] == 30 and "media" not in app.shown[-1],
      "Position and Seconds On Screen; a picture that is not http(s) is left out")
d.set_prop("Log Level", "Trace")
d.command("SHOW_NOTIFICATION", {"Title": "Cam", "Message": "y", "Picture URL": "http://admin:Secr3tPw@192.168.50.61/snap.jpg"})
d.pump(6000)
d.action("PrintDiagnostics")
check(app.shown[-1]["media"]["image"]["uri"] == "http://admin:Secr3tPw@192.168.50.61/snap.jpg", "a camera login in the picture's address goes to PiPup")
check(not [l for l in d.logs() if "Secr3tPw" in l], "but never into a log line (Trace and Print Diagnostics too)")
check(not [p for p in paths(app) if p.startswith("/power")], "the driver never asks PiPup to turn the screen on")

# ============================================================ pictures, inline
d, app = tv()
pics = FakePictures({"/notify/ring.jpg": JPEG, "/page.html": b"<html>not a picture</html>", "/big.jpg": JPEG + b"x" * 2000000})
d.serve("127.0.0.1:47200", pics)
cam = FakePictures({"/snap.jpg": JPEG})
d.serve("192.168.50.61:80", cam)
d.clear()
notify(d, nid="i-1", title="Front Door", message="Ring", PICTURE="http://127.0.0.1:47200/notify/ring.jpg")
d.pump(1000)
uri = app.shown[-1]["media"]["image"]["uri"]
check(pics.requests == ["/notify/ring.jpg"] and uri.startswith("data:image/jpeg;base64,") and base64.b64decode(uri.split(",", 1)[1]) == JPEG,
      "DirectorLink's picture on the controller: fetched by the driver (127.0.0.1), carried inline, byte for byte")
check(d.events() == ["Notification Shown"] and any("with its picture" in l for l in d.logs()), "shown with its picture")
d.pump(5000)
d.command("SHOW_NOTIFICATION", {"Title": "Gate", "Message": "Opened", "Picture URL": "http://admin:Secr3tPw@192.168.50.61/snap.jpg"})
d.pump(1000)
uri = app.shown[-1]["media"]["image"]["uri"]
check(cam.requests == ["/snap.jpg"] and uri.startswith("data:image/jpeg;base64,"), "a camera's snapshot with a login: fetched by the driver, carried inline")
check(any(r["url"] == "http://admin:Secr3tPw@192.168.50.61/snap.jpg" for r in d.http_log()), "the login goes in the address Control4 fetches (it sends it as a login)")
for path, why in (("/page.html", "not a picture"), ("/big.jpg", "too large")):
    d.pump(5000)
    notify(d, nid="i-" + path, PICTURE="http://127.0.0.1:47200" + path)
    d.pump(1000)
    check(app.shown[-1]["media"]["image"]["uri"] == f"http://{CTRL}:47200{path}", f"{why}: the pop-up carries the address instead")
pics.delay_ms = 3000
d.pump(5000)
t0 = d.now()
d.clear()
notify(d, nid="i-slow", PICTURE="http://127.0.0.1:47200/notify/ring.jpg")
d.pump(1900)
check(not d.events(), "a slow picture: the pop-up waits for it")
d.pump(1000)
check(d.events() == ["Notification Shown"] and app.shown[-1]["media"]["image"]["uri"] == f"http://{CTRL}:47200/notify/ring.jpg",
      "not fetched within 2 s: the pop-up goes with the address")
pics.delay_ms = 20
d.set_prop("Pictures", "Off")
n = len(pics.requests)
notify(d, nid="i-off", PICTURE="http://127.0.0.1:47200/notify/ring.jpg")
d.pump(6000)
check(len(pics.requests) == n and "media" not in app.shown[-1], "Pictures Off: nothing fetched, no picture")

# The screen off: nothing sent
app.screen_on = False
d.pump(6000)
d.clear()
notify(d, nid="p-5")
d.pump(1000)
check(d.events() == ["Notification Failed"] and paths(app).count("/notify") == 6, "the screen off: no pop-up, Notification Failed")
check(d.prop("Status") == "Off" and any("screen is off" in l for l in d.logs()), f"Status Off, the log says the screen is off ({d.prop('Status')})")
app.screen_on = True
d.pump(61000)
check(d.prop("Status") == "Ready", "the screen on again: Ready by the next check")

# ============================================================ a token, the IP allowlist
d, app = tv(fake=FakePiPup(IP))
app.token = "S3cretTok3n"
d.pump(61000)
check(d.prop("Status").startswith("PiPup asks for a token"), f"PiPup wants a token (authEnabled): Status says so ({d.prop('Status')})")
d.clear()
notify(d, nid="t-1")
d.pump(2000)
check(d.events() == ["Notification Failed"] and "/notify" not in paths(app)[-2:], "no token: not sent, Notification Failed")
d.set_prop("PiPup Token", "wrong", pump_ms=3000)
d.clear()
notify(d, nid="t-2")
d.pump(6000)
check(d.events() == ["Notification Failed"] and d.prop("Status") == "PiPup did not take the token: check PiPup Token",
      f"a wrong token: 401, Status says to check it ({d.prop('Status')})")
d.set_prop("Log Level", "Trace")
d.set_prop("PiPup Token", "S3cretTok3n", pump_ms=3000)
d.pump(5000)
d.clear()
notify(d, nid="t-3")
d.pump(6000)
req = [r for r in app.requests if r[1] == "/notify"][-1]
check(d.events() == ["Notification Shown"] and req[2].get("Authorization") == "Bearer S3cretTok3n", "the right token: sent as Authorization: Bearer, shown")
check(d.prop("Status") == "Ready", "Ready")
d.action("PrintDiagnostics")
check(not [l for l in d.logs() if "S3cretTok3n" in l], "the token is never in a log line (Trace, Print Diagnostics, the property change)")
check(any("token set (never shown)" in l for l in d.logs()), "Print Diagnostics says a token is set")

d, app = tv()
app.blocked = True
d.pump(5000)
d.clear()
notify(d, nid="b-1")
d.pump(2000)
check(d.events() == ["Notification Failed"] and d.prop("Status").startswith(f"PiPup refuses this controller: allow {CTRL}"),
      f"the IP allowlist leaves the controller out (403): Status names the address to allow ({d.prop('Status')})")

# ============================================================ off, not running, slow, refusing
d, app = tv()
app.network = False
d.clear()
notify(d, nid="o-1")
d.pump(2900)
check(d.events() == [], "the TV off: no answer yet at 2.9 s")
d.pump(200)
check(d.events() == ["Notification Failed"] and any("did not answer within 3 s (off)" in l for l in d.logs()),
      "no connection within 3 s: Notification Failed, the log says the TV is off")
check(d.prop("Status") == "Off", f"a TV that answered here before: Status Off ({d.prop('Status')})")
app.network = True
app.running = False
d.pump(5000)
d.clear()
notify(d, nid="o-2")
d.pump(100)
check(d.events() == ["Notification Failed"] and d.prop("Status").startswith("The TV answers, but PiPup does not"),
      f"the TV refuses at once (PiPup not running): Failed at once, Status says to open PiPup ({d.prop('Status')})")
app.running = True
app.delay_ms = 2500
d.pump(5000)
d.clear()
notify(d, nid="o-3")
d.pump(9000)
check(d.events() == ["Notification Shown"], "slow answers (2.5 s each): Shown")
app.delay_ms = 4000
d.pump(5000)
d.clear()
notify(d, nid="o-3b")
d.pump(9000)
check(d.events() == ["Notification Failed"] and any("Not shown" in l and "within 3 s" in l for l in d.logs()),
      "a TV that takes 4 s to answer /status: dropped (the TV has 3 s)")
app.delay_ms = 30
d.pump(5000)
d.clear()
app.has_status = False
notify(d, nid="o-4")
d.pump(6000)
check(d.events() == ["Notification Shown"], "a PiPup without /status: sent all the same")
app.has_status = True
d = Driver(props={"TV IP Addresses": "192.168.50.99"})
d.start()
d.pump(10000)
check(d.prop("Status") == "Not reachable", f"no TV ever at the address: Not reachable ({d.prop('Status')})")

# A different port
d, app = tv(props={"PiPup Port": "8080"}, fake=type("P", (FakePiPup,), {"port": 8080})(IP))
check(d.prop("Status") == "Ready" and d.http_log(IP)[0]["url"].startswith(f"http://{IP}:8080/"), "PiPup Port: another port")

# ============================================================ checks: every minute; when gone, 5 s, 30 s, 2 min, then every 5 min
d, app = tv()
n0 = len(paths(app, "GET"))
d.pump(5 * 60000 + 1000)
check(len(paths(app, "GET")) - n0 == 5, "PiPup answers: checked every minute")
d2, app2 = tv()
app2.network = False
d2.pump(61000)
d2.g.HTTP_LOG = d2.lua.table_from([])
d2.pump(40 * 60000)
starts = [e["at"] for e in d2.http_log(IP)]
waits = [round((b - a) / 1000) - 3 for a, b in zip(starts, starts[1:])]
check(waits[:5] == [30, 120, 300, 300, 300] and set(waits[2:]) == {300}, f"not answering: checked after 5 s, 30 s, 2 min, then every 5 min (waits {waits[:6]})")
app2.network = True
d2.pump(6 * 60000)
check(d2.prop("Status") == "Ready", "back: Ready by the next check")

# A restart: a TV that answered there before is Off, not Not reachable
d, app = tv()
persist = d.persisted()
d2 = Driver(props={"TV IP Addresses": IP}, persist=persist)
gone = FakePiPup(IP)
gone.network = False
gone.attach(d2)
d2.start()
d2.pump(10000)
check(d2.prop("Status") == "Off" and d2.prop("TVs").startswith("SONY XR-77A95L"), f"after a restart, a TV that answered here before: Off, its name kept ({d2.prop('Status')}, {d2.prop('TVs')})")
table_persist = {k: (json.loads(v[5:]) if isinstance(v, str) and v.startswith("json:") else v) for k, v in persist.items()}
d3 = Driver(props={"TV IP Addresses": IP}, persist=table_persist)
FakePiPup(IP).attach(d3)
d3.start()
d3.pump(3000)
check(d3.prop("Status") == "Ready", "saved values Director returns as a table are read too")

# ============================================================ several TVs in one driver
IP2 = "192.168.50.51"
d = Driver(props={"TV IP Addresses": f"{IP}, {IP2}"})
sony = FakePiPup(IP, name="Living Room TV").attach(d)
bed = FakePiPup(IP2, name="Bedroom TV").attach(d)
pics = FakePictures({"/notify/ring.jpg": JPEG})
d.serve("127.0.0.1:47200", pics)
d.start()
d.pump(3000)
check(d.prop("Status") == "Ready: 2 TVs", f"two TVs answering: Status Ready: 2 TVs ({d.prop('Status')})")
check(d.prop("TVs") == f"Living Room TV ({IP}): Ready, PiPup 0.3.4 · Bedroom TV ({IP2}): Ready, PiPup 0.3.4", f"TVs lists each ({d.prop('TVs')})")
d.clear()
notify(d, nid="m-1", title=HE_TITLE, message=HE_MESSAGE, PICTURE="http://127.0.0.1:47200/notify/ring.jpg")
d.pump(1000)
check(len(sony.shown) == 1 and sony.shown == bed.shown and sony.shown[0]["title"] == HE_TITLE, "one notification: the same pop-up on both TVs")
check(pics.requests == ["/notify/ring.jpg"] and sony.shown[0]["media"]["image"]["uri"].startswith("data:image/jpeg;base64,"),
      "the picture fetched once, inline on both")
check(d.events() == ["Notification Shown"] and any("Shown on all 2 TVs (Living Room TV, Bedroom TV)" in l for l in d.logs()),
      "Notification Shown once; the log says on which TVs")
bed.network = False
d.pump(5000)
d.clear()
notify(d, nid="m-2")
d.pump(3500)
check(len(sony.shown) == 2 and len(bed.shown) == 1 and d.events() == ["Notification Shown"], "one TV off: shown on the other, Notification Shown")
check(any("Shown on 1 of 2 TVs (Living Room TV; not on Bedroom TV: the TV did not answer within 3 s (off))" in l for l in d.logs()),
      "the log says which TV left it out, and why")
check(d.prop("Status") == "1 of 2 TVs ready - Bedroom TV: Off", f"Status names the TV that is off ({d.prop('Status')})")
sony.screen_on = False
d.pump(5000)
d.clear()
notify(d, nid="m-3")
d.pump(3500)
check(d.events() == ["Notification Failed"] and any("Not shown (Living Room TV: its screen is off; Bedroom TV: the TV did not answer" in l for l in d.logs()),
      "no TV showed it: Notification Failed, the log says why for each")
sony.screen_on = True
bed.network = True
d.pump(5 * 60000)
check(d.prop("Status") == "Ready: 2 TVs", "both back: Ready by their checks")
# Each TV is checked on its own: one gone does not slow the other's checks
bed.network = False
n_sony = len(sony.requests)
d.pump(5 * 60000)
check(len(sony.requests) - n_sony == 5, "the TV that answers is still checked every minute while the other is gone")
bed.network = True
d.pump(6 * 60000)
# Removing a TV: no more requests to it
d.set_prop("TV IP Addresses", IP, pump_ms=2000)
n_bed = len(bed.requests)
d.pump(5000)
notify(d, nid="m-4")
d.pump(5 * 60000)
check(len(bed.requests) == n_bed and d.prop("Status") == "Ready" and len(sony.shown) == 3, "a TV taken out of the list: no more requests to it")
# ip:port, and an entry that is not an address
d = Driver(props={"TV IP Addresses": f"{IP}, {IP2}:8080, not-an-ip!"})
FakePiPup(IP).attach(d)
other = type("P8080", (FakePiPup,), {"port": 8080})(IP2, name="Den TV")
other.attach(d)
d.start()
d.pump(3000)
check(other.requests and d.prop("Status").startswith("Ready: 2 TVs - not an address: not-an-ip!"),
      f"ip:port reaches PiPup on its own port; an entry that is not an address is named in Status ({d.prop('Status')})")

# An update from 1.0.0-beta.2 (one TV in "TV IP Address"): its address moves to TV IP Addresses
d = Driver(persist={"DL_TV": 'json:{"host":"%s","seen":"%s","info":{"name":"SONY XR-77A95L","version":"0.3.4"}}' % (IP, IP)})
FakePiPup(IP).attach(d)
d.start()
d.pump(3000)
check(d.prop("TV IP Addresses") == IP and d.prop("Status") == "Ready", f"from beta.2: the TV's address is moved to TV IP Addresses ({d.prop('TV IP Addresses')})")

# ============================================================ kinds, IDs, Quiet Hours
d, app = tv()
d.clear()
for k, i in (("camera", 1), ("door", 2), ("other", 3), ("spaceship", 4)):
    notify(d, kind=k, nid=f"k-{i}")
d.pump(30000)
check(not app.shown and d.events() == [], "Camera Alerts, Doors and Gates, Other off by default (and an unknown KIND is Other)")
d.set_prop("Camera Alerts", "On")
notify(d, kind="camera", nid="k-5", title="Garden", message="Person")
d.pump(1000)
check(app.shown[-1]["message"] == "Person", "Camera Alerts On: shown")
notify(d, nid="same")
d.pump(6000)
notify(d, nid="same")
d.pump(6000)
check(len(app.shown) == 2, "the same ID within 10 minutes: shown once")
d.pump(10 * 60000)
notify(d, nid="same")
d.pump(6000)
check(len(app.shown) == 3, "the same ID after 10 minutes: shown again")
d.set_prop("Quiet Hours", "22:00-07:00")
d.set_local_time(23, 0)
d.clear()
notify(d, nid="q-1")
d.command("SHOW_NOTIFICATION", {"Title": "At", "Message": "night"})
d.pump(12000)
check(len(app.shown) == 3 and d.events() == [], "Quiet Hours: nothing (Show Notification too)")
d.action("TestNotification")
d.pump(2000)
check(len(app.shown) == 4 and app.shown[-1]["title"] == "Control4", "Test Notification shows during Quiet Hours")
d.set_local_time(7, 0)
notify(d, nid="q-2")
d.pump(6000)
check(len(app.shown) == 5, "at 07:00: shown again")

# ============================================================ one every 5 seconds, a doorbell or the alarm first
d, app = tv(props={"Camera Alerts": "On", "Doors and Gates": "On", "Other": "On"})
d.pump(10000)
t0 = d.now()
notify(d, kind="camera", nid="r-1", title="Cam", message="1")
notify(d, kind="door", nid="r-2", title="Door", message="2")
notify(d, kind="doorbell", nid="r-3", title="Bell", message="3")
notify(d, kind="other", nid="r-4", title="Other", message="4")
notify(d, kind="alarm", nid="r-5", title="Alarm", message="5")
d.pump(30000)
texts = [s["message"] for s in app.shown]
check(texts == ["1", "3", "5", "2", "4"], f"one at a time; the doorbell and the alarm before those waiting ({texts})")
check(d.eval("gNotify.lastSentMs") - t0 >= 20000, "at most one pop-up every 5 s")

# ============================================================ Find TVs
d = Driver()
ssdp = attach_ssdp(d, [
    {"ip": "192.168.50.50", "name": "SONY XR-77A95L", "maker": "Sony", "model": "BRAVIA 4K AE1"},
    {"ip": "192.168.50.51", "name": "TapCast-4085", "maker": "Google Inc.", "model": "Eureka Dongle"},
    {"ip": "192.168.50.52", "maker": "Xiaomi", "model": "MiTV-AFKR0"},
    {"ip": "192.168.50.53", "name": "Bedroom TV", "standby": True},
])
FakePiPup("192.168.50.50").attach(d)
d.start()
d.pump(12000)
items = d.prop_list("TVs Found")
check(items == ["-", "SONY XR-77A95L (192.168.50.50) - PiPup answers", "TapCast-4085 (192.168.50.51)", "Xiaomi MiTV-AFKR0 (192.168.50.52)"],
      f"no address: Find TVs runs; the TVs with PiPup first (GET /ping), each by its own name ({items})")
check(len(ssdp.searches) == 3, "the M-SEARCH is sent 3 times")
d.set_prop("TVs Found", "SONY XR-77A95L (192.168.50.50) - PiPup answers", pump_ms=2000)
check(d.prop("TV IP Addresses") == "192.168.50.50" and d.prop("Status") == "Ready", "picking a TV adds it to TV IP Addresses and checks it")
d.set_prop("TVs Found", "SONY XR-77A95L (192.168.50.50) - PiPup answers", pump_ms=2000)
check(d.prop("TV IP Addresses") == "192.168.50.50", "picking it again does not add it twice")
FakePiPup("192.168.50.52", name="Kitchen TV").attach(d)
d.set_prop("TVs Found", "Xiaomi MiTV-AFKR0 (192.168.50.52)", pump_ms=2000)
check(d.prop("TV IP Addresses") == "192.168.50.50, 192.168.50.52" and d.prop("Status") == "Ready: 2 TVs",
      f"picking another adds it to the list ({d.prop('TV IP Addresses')}; {d.prop('Status')})")

finish()
