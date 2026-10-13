"""The parts on their own (offline).   python tests/test_protocol.py

JSON (UTF-8 text through and back), PiPup's JSON, the picture's address (127.0.0.1 becomes the
controller's), the SSDP answers of casting devices, Quiet Hours, and the log filter (a login in
an address, and the token, never in a log line).
"""
import json

from harness import Driver, check, finish, lua_bytes, utf8

d = Driver()
L = d.lua
G = L.globals()

# ---- JSON
hebrew = "שער הכניסה נפתח"
enc = utf8(d.call("JsonEncode", d.table({"message": hebrew.encode("utf-8"), "n": 3})))
check(json.loads(enc) == {"message": hebrew, "n": 3} and "\\u05" not in enc, f"JSON: Hebrew as UTF-8, read back by a standard parser ({enc})")
dec = d.call("JsonDecode", '{"version":"0.3.4","id":"4613e383-04aa-3839-be1d-57ddd9a0e209","name":"SONY XR-77A95L","port":7979,'
                           '"active":false,"count":0,"screenOn":false,"uptimeSeconds":517,"authEnabled":true}')
check(dec.screenOn is False and dec.authEnabled is True and dec.name == "SONY XR-77A95L", "JSON: PiPup's /status (as PiPup 0.3.4 answered) is read")

# ---- PiPup: the JSON
G.Properties["Seconds On Screen"] = "20"
G.Properties["Position"] = "Top Right"
item = d.table({"title": "דלת הכניסה".encode(), "message": "מישהו בדלת".encode(), "picture": b"http://192.168.50.10:9000/snap/1.jpg"})
popup = json.loads(utf8(d.call("PipupBody", item)))
check(popup == {"id": "directorlink", "duration": 20, "position": 0, "title": "דלת הכניסה", "message": "מישהו בדלת",
                "media": {"image": {"uri": "http://192.168.50.10:9000/snap/1.jpg", "width": 640}}},
      f"PiPup: one pop-up id, Hebrew as given, the picture as media.image, nothing PiPup does not document ({popup})")
for pos, n in (("Top Right", 0), ("Top Left", 1), ("Bottom Right", 2), ("Bottom Left", 3), ("Center", 4)):
    G.Properties["Position"] = pos
    check(json.loads(utf8(d.call("PipupBody", item)))["position"] == n, f"Position {pos} is {n}, as PiPup numbers them")
plain = json.loads(utf8(d.call("PipupBody", d.table({"title": b"A", "message": b"B"}))))
check("media" not in plain and plain["title"] == "A" and plain["message"] == "B", "no picture, no media")
only_title = json.loads(utf8(d.call("PipupBody", d.table({"title": b"Gate", "message": b""}))))
check(only_title.get("message") == "Gate" and "title" not in only_title, "a title alone is the message")
G.Properties["Seconds On Screen"] = "500"
check(json.loads(utf8(d.call("PipupBody", item)))["duration"] == 120, "Seconds On Screen is kept within 3-120")

# ---- The picture's address
def pic(u):
    r = d.call("PictureUrl", u.encode())
    return utf8(r) if r is not None else None


check(pic("http://127.0.0.1:47200/notify/abc.jpg") == "http://192.168.50.10:47200/notify/abc.jpg", "127.0.0.1 becomes the controller's address (the TV fetches it)")
check(pic("http://localhost/x.jpg") == "http://192.168.50.10/x.jpg", "localhost too")
check(pic("http://192.168.1.20/snap.jpg") == "http://192.168.1.20/snap.jpg" and pic("HTTPS://cam.local:8443/a?b=1") == "https://cam.local:8443/a?b=1",
      "any other http(s) address is kept as it is")
check(pic("http://admin:pa55@192.168.1.20/snap.jpg") == "http://admin:pa55@192.168.1.20/snap.jpg", "a login in the address is kept (the TV needs it)")
for bad in ("ftp://x/y.jpg", "not a url", "http://", "http://a b/c.jpg", ""):
    check(pic(bad) is None, f"'{bad}' is no picture")

# ---- SSDP answers (DIAL)
answer = (b"HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.50:8008/ssdp/device-desc.xml\r\nST: urn:dial-multiscreen-org:service:dial:1\r\n"
          b"USN: uuid:a::urn:dial-multiscreen-org:service:dial:1\r\n\r\n"
          b"HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.51:56789/dd.xml\r\nST: urn:dial-multiscreen-org:service:dial:1\r\n\r\n"
          b"HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.52:1400/xml/device_description.xml\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n"
          b"HTTP/1.1 200 OK\r\nLOCATION: http://8.8.8.8:8008/x\r\nST: urn:dial-multiscreen-org:service:dial:1\r\n\r\n")
devs = [dict(r) for r in d.call("SsdpReplies", answer).values()]
check([r["ip"] for r in devs] == ["192.168.1.50", "192.168.1.51"], f"SSDP: the DIAL devices, not a Sonos, not a public address ({[r['ip'] for r in devs]})")
req = utf8(d.call("SsdpRequest"))
check("ST: urn:dial-multiscreen-org:service:dial:1\r\n" in req and req.startswith("M-SEARCH * HTTP/1.1\r\n"), "SSDP: the M-SEARCH for DIAL")
xml = "<root><device><friendlyName>Family Room TV &amp; more</friendlyName><manufacturer>Sony</manufacturer></device></root>"
check(utf8(d.call("XmlText", xml, "friendlyName")) == "Family Room TV & more", "the description's friendlyName, unescaped")

# ---- Quiet Hours (the same rules as the LG driver)
def qh(text):
    r = d.call("ParseQuietHours", text.encode("utf-8"))
    return r if not isinstance(r, tuple) else tuple(r)


check(qh("") is None and qh("22:00-07:00") == (1320, 420) and qh("22-7") == (1320, 420) and qh("22.00–07.00") == (1320, 420),
      "Quiet Hours: empty, 22:00-07:00, 22-7, an en dash")
check(qh("evening") is False and qh("22:00-22:00") is False, "Quiet Hours: not understood")
G.Properties["Quiet Hours"] = "22:00-07:00"
check(d.call("InQuietHours", 23 * 60) and d.call("InQuietHours", 0) and not d.call("InQuietHours", 7 * 60), "Quiet Hours: across midnight")
G.Properties["Quiet Hours"] = ""

# ---- The log filter
red = d.call("Redact", "GET http://admin:pa55w0rd@192.168.1.20/snap.jpg failed; picture https://u:p@cam/x")
check("pa55w0rd" not in red and "u:p@" not in red and "http://***@192.168.1.20/snap.jpg" in red, f"Log: a login in an address is hidden ({red})")
d.call("RegisterSecret", "S3cretTok3n")
red = d.call("Redact", "Authorization: Bearer S3cretTok3n")
check("S3cretTok3n" not in red, f"Log: the token is hidden ({red})")

finish()
