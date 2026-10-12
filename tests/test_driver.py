"""The driver against the TV apps (offline).   python tests/test_driver.py

The real driver code in Lua 5.1, a fake Director (harness.py) and fake TV apps
(fake_apps.py): Notifications for Android TV and PiPup, a TV that is off (no answer), one
whose app is not running (refused at once), slow, or refusing; PiPup's screen and overlay
permission; pictures; the checks (every minute, then 5 s, 30 s, 2 min, every 5 min); the
DirectorLink notification agreement (variables, both ways in, VERSION, KIND, ID repeats); the
kinds, Quiet Hours, one pop-up every 5 s with a doorbell or the alarm first; Find TVs.
"""
import json

from fake_apps import FakeNfa, FakePiPup, attach_ssdp
from harness import Driver, check, finish

IP = "192.168.50.50"
CTRL = "192.168.50.10"
HE_TITLE, HE_MESSAGE = "דלת הכניסה", "מישהו מצלצל בדלת"


def tv(app="nfa", props=None, persist=None, fake=None):
    """A driver set up for the TV at IP with its app: (driver, fake app)."""
    p = {"TV IP Address": IP}
    if app == "pipup":
        p["TV App"] = "PiPup"
    p.update(props or {})
    d = Driver(props=p, persist=persist)
    fake = fake or (FakePiPup(IP) if app == "pipup" else FakeNfa(IP))
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


def posts(fake, path):
    return [r for r in fake.requests if r[0] == "POST" and r[1] == path]


# ============================================================ variables (the agreement)
d = Driver()
d.start()
check(d.var_order() == ["LAST_NOTIFICATION", "DIRECTORLINK_NOTIFY", "DIRECTORLINK_NOTIFY_KINDS"],
      f"variables in their fixed order: LAST_NOTIFICATION, then the agreement's ({d.var_order()})")
check(d.var("DIRECTORLINK_NOTIFY") == "1" and d.var("DIRECTORLINK_NOTIFY_KINDS") == "doorbell,alarm", "DIRECTORLINK_NOTIFY = 1; kinds doorbell,alarm by default")
check(d.prop("Status").startswith("Enter the TV's IP address"), f"no address: Status says to enter it ({d.prop('Status')})")
d.set_prop("Camera Alerts", "On")
check(d.var("DIRECTORLINK_NOTIFY_KINDS") == "doorbell,camera,alarm", "a kind switched on: DIRECTORLINK_NOTIFY_KINDS follows")
d, app = tv()
d.command("SHOW_NOTIFICATION", {"Title": "Hello", "Message": "World"})
d.pump(1000)
d2 = Driver(props={"TV IP Address": IP, "Alarm": "Off"}, persist=d.persisted())
FakeNfa(IP).attach(d2)
d2.start()
check("DIRECTORLINK_NOTIFY" in list(d2.g.VAR_LOG.values()) and d2.var("DIRECTORLINK_NOTIFY_KINDS") == "doorbell", "a restart writes the agreement's variables again")
check(d2.var("LAST_NOTIFICATION") == "Hello: World" and d2.var_order()[0] == "LAST_NOTIFICATION", "LAST_NOTIFICATION comes back after a restart, same order")

# ============================================================ Notifications for Android TV
d, app = tv()
check(d.prop("Status") == "Ready" and d.prop("TV") == "Notifications for Android TV", f"the app answers GET /: Ready ({d.prop('Status')})")
check(app.requests and app.requests[0][:2] == ("GET", "/"), "checked with GET / on port 7676 (as Home Assistant does)")
d.clear()
notify(d, title=HE_TITLE, message=HE_MESSAGE, nid="n-1", PICTURE="http://127.0.0.1:47200/notify/abc.jpg")
check(d.events() == [], "never blocks: DIRECTORLINK_NOTIFY returns before the TV answers")
d.pump(1000)
shown = app.shown[-1] if app.shown else {}
check(shown.get("title") == HE_TITLE and shown.get("msg") == HE_MESSAGE, f"the pop-up: title and message apart, Hebrew exactly as given ({shown.get('title')}, {shown.get('msg')})")
check(shown.get("imageurl") == f"http://{CTRL}:47200/notify/abc.jpg", f"the picture as imageurl, at the controller's address ({shown.get('imageurl')})")
check(shown.get("duration") == "15" and shown.get("position") == "2" and shown.get("interrupt") == "0", "15 s, top right, not taking the remote")
check(len(shown.get("icon", b"")) == 68, "the icon part (Home Assistant's 1 x 1 PNG)")
check(d.events() == ["Notification Shown"] and d.event_vars() == [("Notification Shown", f"{HE_TITLE}: {HE_MESSAGE}")],
      "Notification Shown, LAST_NOTIFICATION set before it")
req = [r for r in d.http_log(IP) if r["method"] == "POST"][-1]
check(req["opts"].get("connect_timeout") == 3 and req["opts"].get("timeout") == 15, "the TV has 3 s to take the connection; the app 15 s to answer")
check(any("Shown on the TV: Doorbell" in l and "with its picture" in l for l in d.logs()), "one Info line, with its picture")
d.clear()
notify(d, via="ReceivedFromProxy", nid="n-2", kind="alarm", title="Alarm", message="Burglary")
d.pump(6000)
check(app.shown[-1]["msg"] == "Burglary" and d.events() == ["Notification Shown"], "DIRECTORLINK_NOTIFY by ReceivedFromProxy too")
d.clear()
d.command("SHOW_NOTIFICATION", {"Title": "Gate", "Message": "Opened", "Picture URL": "http://192.168.50.60/snapshot.jpg"})
d.pump(6000)
check(app.shown[-1]["imageurl"] == "http://192.168.50.60/snapshot.jpg" and app.shown[-1]["title"] == "Gate", "Show Notification with a Picture URL")
d.set_prop("Pictures", "Off")
notify(d, nid="n-3", PICTURE="http://127.0.0.1/x.jpg")
d.pump(6000)
check("imageurl" not in app.shown[-1], "Pictures Off: no picture")
d.set_prop("Pictures", "On")
d.set_prop("Position", "Bottom Left")
d.set_prop("Seconds On Screen", "30")
notify(d, nid="n-4", PICTURE="ftp://nope/x.jpg")
d.pump(6000)
check(app.shown[-1]["position"] == "1" and app.shown[-1]["duration"] == "30" and "imageurl" not in app.shown[-1],
      "Position and Seconds On Screen; a picture that is not http(s) is left out")
check(any("not an http address" in l for l in d.logs()), "the log says why the picture was left out")
d.clear()
d.command("SHOW_NOTIFICATION", {"Title": "Cam", "Message": "x", "Picture URL": "http://admin:Secr3tPw@192.168.50.61/snap.jpg"})
d.pump(6000)
d.set_prop("Log Level", "Trace")
d.command("SHOW_NOTIFICATION", {"Title": "Cam", "Message": "y", "Picture URL": "http://admin:Secr3tPw@192.168.50.61/snap.jpg"})
d.pump(6000)
d.action("PrintDiagnostics")
check(app.shown[-1]["imageurl"] == "http://admin:Secr3tPw@192.168.50.61/snap.jpg", "a camera login in the picture's address goes to the TV")
check(not [l for l in d.logs() if "Secr3tPw" in l], "but never into a log line (Trace and Print Diagnostics too)")

# ============================================================ PiPup
d, app = tv("pipup")
check(d.prop("Status") == "Ready", f"PiPup answers /state: Ready ({d.prop('Status')})")
check(d.prop("TV") == "Family Room TV · Sony BRAVIA 4K VH21 · Android 12 · PiPup 0.26.1", f"the TV property from PiPup's /state ({d.prop('TV')})")
d.clear()
n_state = len([r for r in app.requests if r[1] == "/state"])
notify(d, title=HE_TITLE, message=HE_MESSAGE, nid="p-1", PICTURE="http://127.0.0.1:47200/notify/abc.jpg")
d.pump(1000)
check(len([r for r in app.requests if r[1] == "/state"]) == n_state + 1, "before a pop-up, /state: is the screen on?")
popup = app.shown[-1] if app.shown else {}
check(popup.get("id") == "directorlink" and popup.get("title") == HE_TITLE and popup.get("message") == HE_MESSAGE and popup.get("duration") == 15
      and popup.get("position") == 0, f"POST /notify: one pop-up id, Hebrew as given, 15 s, top right ({popup})")
check(popup.get("media") == {"image": {"uri": f"http://{CTRL}:47200/notify/abc.jpg", "width": 480}}, "the picture as media.image, at the controller's address")
hdr = posts(app, "/notify")[-1][2]
check(any(k.lower() == "content-type" and v == "application/json; charset=utf-8" for k, v in hdr.items()), "JSON, UTF-8")
check(d.events() == ["Notification Shown"], "Notification Shown")
app.screen_on = False
d.pump(5000)
d.clear()
notify(d, nid="p-2")
d.pump(1000)
check(d.events() == ["Notification Failed"] and len(app.shown) == 1, "the screen off: no pop-up, Notification Failed")
check(d.prop("Status") == "Off" and any("screen is off" in l for l in d.logs()), f"Status Off, the log says the screen is off ({d.prop('Status')})")
app.screen_on = True
app.overlay = False
d.pump(5000)
d.clear()
notify(d, nid="p-3")
d.pump(1000)
check(d.events() == ["Notification Failed"] and d.prop("Status").startswith("PiPup may not show pop-ups"),
      f"no overlay permission (PiPup would answer 200 and show nothing): not sent, Status says what to allow ({d.prop('Status')})")
app.overlay = True
app.has_state = False
d.pump(5000)
d.clear()
notify(d, nid="p-4")
d.pump(1000)
check(d.events() == ["Notification Shown"] and len(app.shown) == 2, "an early PiPup without /state: sent all the same")
check(not [r for r in app.requests if r[1].startswith("/power")], "the driver never asks PiPup to turn the screen on")

# Switching the app re-checks the TV with the other one
d, nfa = tv()
pip = FakePiPup(IP).attach(d)
d.set_prop("TV App", "PiPup", pump_ms=2000)
check(pip.requests and pip.requests[0][1] == "/state" and d.prop("Status") == "Ready", "TV App changed: the TV is checked with PiPup")

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
check(d.events() == ["Notification Failed"] and "does not: install it and open it once on the TV" in d.prop("Status"),
      f"the TV refuses at once (the app not running): Failed at once, Status says to open it ({d.prop('Status')})")
app.running = True
app.delay_ms = 8000
d.pump(5000)
d.clear()
notify(d, nid="o-3", PICTURE="http://192.168.50.60/snap.jpg")
d.pump(9000)
check(d.events() == ["Notification Shown"], "an answer after 8 s (a picture can take a while): Shown")
app.delay_ms = 20000
d.pump(5000)
d.clear()
notify(d, nid="o-4")
d.pump(16000)
check(d.events() == ["Notification Failed"] and any("no answer from Notifications for Android TV within 15 s" in l for l in d.logs()), "no answer within 15 s: Failed")
app.delay_ms = 30
app.status = 500
d.pump(5000)
d.clear()
notify(d, nid="o-5")
d.pump(6000)
check(d.events() == ["Notification Failed"] and any("answered HTTP 500" in l for l in d.logs()), "HTTP 500: Failed")
d = Driver(props={"TV IP Address": "192.168.50.99"})
d.start()
d.pump(10000)
check(d.prop("Status") == "Not reachable", f"no TV ever at the address: Not reachable ({d.prop('Status')})")

# ============================================================ checks: every minute; when gone, 5 s, 30 s, 2 min, then every 5 min
d, app = tv()
n0 = len([r for r in app.requests if r[0] == "GET"])
d.pump(5 * 60000 + 1000)
check(len([r for r in app.requests if r[0] == "GET"]) - n0 == 5, "the app answers: checked every minute")
app.network = False
d.pump(61000 + 4000)
check(d.prop("Status") == "Off", "gone: Off")
d2, app2 = tv()
app2.network = False
d2.pump(61000)  # the next check fails (3 s)
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
d2 = Driver(props={"TV IP Address": IP}, persist=persist)
gone = FakeNfa(IP)
gone.network = False
gone.attach(d2)
d2.start()
d2.pump(10000)
check(d2.prop("Status") == "Off", f"after a restart, a TV that answered here before: Off ({d2.prop('Status')})")
table_persist = {k: (json.loads(v[5:]) if isinstance(v, str) and v.startswith("json:") else v) for k, v in persist.items()}
d3 = Driver(props={"TV IP Address": IP}, persist=table_persist)
FakeNfa(IP).attach(d3)
d3.start()
d3.pump(3000)
check(d3.var("LAST_NOTIFICATION") is not None and d3.prop("Status") == "Ready", "saved values Director returns as a table are read too")

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
check(app.shown[-1]["msg"] == "Person", "Camera Alerts On: shown")
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
texts = [s["msg"] for s in app.shown]
check(texts == ["1", "3", "5", "2", "4"], f"one at a time; the doorbell and the alarm before those waiting ({texts})")
check(d.eval("gNotify.lastSentMs") - t0 >= 20000, "at most one pop-up every 5 s")

# ============================================================ Find TVs
d = Driver()
ssdp = attach_ssdp(d, [
    {"ip": "192.168.50.50", "name": "Family Room TV", "maker": "Sony", "model": "BRAVIA 4K VH21"},
    {"ip": "192.168.50.51", "name": "Kitchen", "maker": "Google", "model": "Chromecast"},
    {"ip": "192.168.50.52", "maker": "TCL", "model": "Google TV"},
    {"ip": "192.168.50.53", "name": "Bedroom TV", "standby": True},
])
FakeNfa("192.168.50.50").attach(d)
d.start()
d.pump(12000)
items = d.prop_list("TVs Found")
check(items == ["-", "Family Room TV (192.168.50.50) - Notifications for Android TV answers", "Kitchen (192.168.50.51)", "TCL Google TV (192.168.50.52)"],
      f"no address: Find TVs runs; the TVs with the app first, each by its own name ({items})")
check(len(ssdp.searches) == 3, "the M-SEARCH is sent 3 times")
d.set_prop("TVs Found", "Family Room TV (192.168.50.50) - Notifications for Android TV answers", pump_ms=2000)
check(d.prop("TV IP Address") == "192.168.50.50" and d.prop("Status") == "Ready", "picking a TV fills TV IP Address and checks it")

finish()
