# Changelog

All notable changes to DirectorLink · Android TV Notifications for Control4. Versions follow the `VERSION` file; the driver version Composer compares is in brackets.

## 1.0.1 (1000199) - 2026-10-13

Show Notification's **Send To: All TVs** finds the other copies more surely.

- The other copies are looked up under the file name the controller has for the driver (`C4:GetDriverFileName`), as well as under `DirectorLink-Android-TV.c4z`, so a driver file saved under another name (a browser's `(1)`) still finds them.
- A Show Notification from another copy is taken whichever way the controller hands it over (ExecuteCommand or ReceivedFromProxy).
- When no other copy is found, the log (Info) says what the controller listed and this copy's device number.
- `tests/live_test.py alltvs <TV IP>` runs two copies of the driver on one TV.

## 1.0.0 (1000099) - 2026-10-13

First full release: the 1.0.0-beta.2 driver, one copy per TV, with **Send To** added to Show Notification. Beta.2 was confirmed from a Control4 controller on a Sony XR-77A95L (Google TV) with PiPup 0.3.4: Find TVs, Test Notification, and Show Notification with a picture (fetched by the controller, sent inside the pop-up).

- **One copy of the driver per TV** again (beta.3's list of TVs in one driver is withdrawn): each TV keeps its own kinds, Quiet Hours, look and Status.
- **Show Notification** has a new parameter, **Send To**: *This TV* (the default) or *All TVs*. *All TVs* shows it on this copy's TV and sends it to every other copy of the driver in the project (`C4:SendToDevice`, with *This TV*, so it goes no further); each shows it on its own TV.
- **From beta.3:** the list's first TV becomes **TV IP Address**; the log names the others, which need a copy of their own. From beta.2: nothing changes. From beta.1: install PiPup on the TV.

## 1.0.0-beta.3 (1000003) - 2026-10-13

One driver for several TVs. Beta.2 was confirmed from a Control4 controller on a Sony XR-77A95L with PiPup 0.3.4: Find TVs, Test Notification and a pop-up with a picture (fetched by the controller, sent inline).

- **TV IP Addresses** (a list, `ip` or `ip:port`, up to 16) replaces TV IP Address; **TVs** (each TV, its state and PiPup's version) replaces TV. From beta.1 or beta.2 the driver moves the TV's address into the list by itself.
- Every notification goes to every TV of the list at once; the picture is fetched once. *Notification Shown* when at least one TV showed it, *Notification Failed* when none did; the log says on which TVs, and why not on the others.
- Each TV is checked on its own (every minute; 5 s, 30 s, 2 min, then every 5 min). **Status** says *Ready: 2 TVs*, or which TVs are not ready.
- Picking a TV in **TVs Found** adds it to the list (once).
- Tested from a computer on the network with the driver's own code: a list of two (the Sony with PiPup, a box without): shown on the Sony, the other named with the reason.

## 1.0.0-beta.2 (1000002) - 2026-10-13

The driver works with one TV app, **PiPup — TV Notifications** by Alexander Savin (Google Play: `nyc.savin.pipup`), as PiPup documents its API, and carries the picture inside the pop-up. Tested on a Sony XR-77A95L (Google TV) with PiPup 0.3.4, from a computer running the driver's own code.

- Why beta.1 showed nothing on that TV: it spoke to "Notifications for Android TV" by default (port 7676, where nothing answered) and to another PiPup fork. Both are gone, with the **TV App** property.
- PiPup's API: `GET /status` before each pop-up (screen off: nothing sent; a token wanted: Status says so), `POST /notify` with JSON, `GET /ping` for Find TVs. New properties **PiPup Port** (7979) and **PiPup Token** (sent as `Authorization: Bearer`, never logged). Status names the controller's address when PiPup's IP allowlist refuses it (403).
- Pictures: the driver fetches the picture (127.0.0.1 works; a login in a camera's address is sent as a login) and sends it inline as a `data:` URI; the address goes instead when it is not fetched within 2 seconds, is not a picture, or is larger than 1.5 MB.
- Find TVs marks the TVs where PiPup answers.
- From beta.1: updates in place; install PiPup on the TV.

## 1.0.0-beta.1 (1000001) - 2026-10-12

First release, a **beta**: built on what the two TV apps take, as Home Assistant, FHEM and PiPup's own documentation describe it, tested against fake apps and a fake Director, not yet confirmed on a real TV.

- One driver, `DirectorLink-Android-TV.c4z` (*DirectorLink · Android TV Notifications* in Composer), one per TV: a pop-up with a picture on a TV with Google TV, Android TV or Fire TV, on the home network only.
- Two apps, chosen per TV in **TV App**: *Notifications for Android TV* (Google Play; *Notifications for Fire TV* in the Amazon Appstore), the default, and *PiPup* (installed with its script). Notifications for Android TV: a multipart POST to port 7676 as Home Assistant sends it, the picture as `imageurl`. PiPup: `/state` (screen on, overlay permission), then `/notify` with JSON, the picture as `media.image`.
- The picture: the notification's `PICTURE`, or Show Notification's **Picture URL**, fetched by the TV; `127.0.0.1` becomes the controller's address. A login in an address is never logged.
- The TV has 3 seconds to take the connection; off or not reachable, the pop-up is dropped with one log line, *Notification Failed*. With PiPup, a screen that is off gets nothing. The driver never turns the TV on.
- The app is checked every minute while it answers; when it does not, after 5 s, 30 s, 2 min, then every 5 min.
- DirectorLink notification agreement, version 1: `DIRECTORLINK_NOTIFY` = `1` and `DIRECTORLINK_NOTIFY_KINDS` (after `LAST_NOTIFICATION`, written at every start, the kinds at every change); the command `DIRECTORLINK_NOTIFY` by `ExecuteCommand` or `ReceivedFromProxy`; the same ID within 10 minutes is ignored.
- Properties: Status, TV, TV App, TV IP Address, TVs Found (an SSDP search for casting devices, each asked whether the app answers), Doorbell, Camera Alerts, Doors and Gates, Alarm, Other (Doorbell and Alarm on), Quiet Hours, Pictures, Position, Seconds On Screen, Log Level. Actions: Find TVs, Test Notification, Print Diagnostics.
- At most one pop-up every 5 seconds per TV, a doorbell or the alarm first; nothing during Quiet Hours.
- Programming: **Show Notification** (Title, Message, Picture URL); *Notification Shown*, *Notification Failed*; `LAST_NOTIFICATION`.

---

DirectorLink is an independent project, not affiliated with Control4 or Snap One. Not affiliated with or endorsed by Google, Amazon or the makers of the TV apps it works with. Android TV, Google TV and Fire TV are trademarks of their owners.
