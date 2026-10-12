# Changelog

All notable changes to DirectorLink · Android TV Notifications for Control4. Versions follow the `VERSION` file; the driver version Composer compares is in brackets.

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
