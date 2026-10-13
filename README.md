# DirectorLink · Android TV Notifications for Control4

Free, open-source Control4 driver that shows notifications as a pop-up **with a picture** on TVs that run Google TV or Android TV: a doorbell ring with who is at the door, a camera alert, a door or gate opened, the alarm. Part of [DirectorLink Drivers](https://directorlink.io/drivers).

It works on your local network only: the driver talks straight to **PiPup**, a free app on the TV. No cloud, no account, no extra hardware.

Free. No subscription, no license key, no account with us.

Made by [DirectorLink](https://directorlink.io), the open-source management layer for Control4 homes. Works on its own: DirectorLink is not required (Composer programming can show pop-ups too).

DirectorLink is an independent project, not affiliated with Control4 or Snap One. Not affiliated with or endorsed by Google, Amazon or the makers of the TV apps it works with. Android TV, Google TV and Fire TV are trademarks of their owners.

**Download:** [releases](../../releases) · **Help and updates:** [directorlink.io/drivers/android-tv](https://directorlink.io/drivers/android-tv) (online with 1.0.0)

> **Beta.** Tested on a Sony XR-77A95L (Google TV) with PiPup 0.3.4: the driver's own code, run from a computer on the TV's network, showed pop-ups in English and Hebrew, with pictures inline and by address. Not yet confirmed from a Control4 controller: see [Trying the beta](#trying-the-beta).

## What you get

| | |
|---|---|
| A pop-up on the TV | Over whatever is on, in a corner of the screen (you choose which), for 15 seconds or as long as you set |
| The picture | Who is at the door or the gate, in the pop-up: the picture DirectorLink sends with a ring, or any camera's snapshot from programming |
| With DirectorLink 1.13 | DirectorLink's notifications: doorbell rings, camera alerts, doors and gates opened, the alarm, others; you choose which kinds each TV shows |
| Composer programming | **Show Notification** (Title, Message, Picture URL); *Notification Shown* and *Notification Failed*; `LAST_NOTIFICATION` |
| Quiet Hours | No pop-ups on this TV at night, or whenever you set |
| Several TVs | One driver per TV. Each has its own kinds, Quiet Hours and look; a notification shows on every TV that is on, at the same moment |

What it never does: turn the TV on, change its channel, input or volume.

## The app on the TV: PiPup

The TV runs **PiPup — TV Notifications** by Alexander Savin, free on Google Play ([play.google.com/store/apps/details?id=nyc.savin.pipup](https://play.google.com/store/apps/details?id=nyc.savin.pipup), [pipup.android.savin.nyc](https://pipup.android.savin.nyc)). It runs a small web server on the TV that shows a pop-up when a device on the home network asks, with no cloud and no account.

**Only this PiPup.** Other apps called PiPup (the original by rogro82, and other forks) take other requests, and the driver does not work with them. In Google Play, look for **PiPup — TV Notifications** by Alexander Savin.

### Setting up PiPup

1. On the TV, open **Google Play**, search **PiPup — TV Notifications** and install it.
2. Open **PiPup** once. Select **Grant display permission** (PiPup needs *Display over other apps*). On Google TV it opens the setting; on some older Android TV models the setting is not in the menus and is granted from a computer with `adb shell appops set nyc.savin.pipup SYSTEM_ALERT_WINDOW allow` (see PiPup's own instructions).
3. PiPup's main screen shows the TV's address (for example `192.168.1.50:7979`), a QR code and a test button. Press the test button: a pop-up shows.
4. Leave PiPup's **token** and **IP allowlist** off, or: with a token, enter the same token in the driver's **PiPup Token**; with an allowlist, add the Control4 controller's address to it.

PiPup starts by itself when the TV starts.

## Which TVs

A TV or box with **Google TV** or **Android TV**, Android 7 or newer, with Google Play: look in its **Settings → About**. The same brand often ships different systems in different countries, so check the TV itself.

| Works | |
|---|---|
| Google TV / Android TV | Sony Bravia (all since 2021), TCL (most countries), Hisense (US Google TV models), Sharp (Europe, Japan), Xiaomi, Panasonic (2026 Google TV models), Philips (2021-2025 upper range only), Nokia, Thomson, Motorola, OnePlus, Skyworth, Haier, iFFALCON, Kogan, Metz Blue, some Grundig and JVC |
| Boxes (on any TV) | Google TV Streamer, Chromecast with Google TV, Nvidia Shield, Xiaomi TV Box S, onn. 4K, Nokia Streaming Box |
| Fire TV (Fire OS 7 / 8) | Not in Google Play: PiPup's APK can be installed by hand. Not tested |

| Does not work | |
|---|---|
| Samsung (Tizen), Vizio, Roku TVs, Hisense and Toshiba with VIDAA, Philips 2026 (Titan OS), Loewe, Bang & Olufsen | Not Android |
| LG (webOS) | Use [DirectorLink · LG TV Notifications](https://directorlink.io/drivers/lg-tv) (pop-ups without a picture) |
| The newest Fire TV sticks (Vega OS) | No Android apps |

## Requirements

- **Control4 OS 3.3.0 or newer** and Composer Pro.
- **A TV with Google TV or Android TV** running PiPup (above).
- **A fixed IP address for the TV** in the router. The controller reaches PiPup on port 7979 (or the port set in PiPup).
- For DirectorLink's notifications: DirectorLink 1.13 or newer.

## Installation

1. Download `DirectorLink-Android-TV.c4z` from the [releases](../../releases).
2. In Composer Pro: **Driver → Add or Update Driver or Agent**.
3. Search **DirectorLink** and add **DirectorLink · Android TV Notifications** to the room of the TV. Add it once for each TV.

> **Keep the exact file name.** If your browser saves a second copy as `DirectorLink-Android-TV (1).c4z`, rename it before you upload. Composer knows a driver by its file name, so a renamed copy installs as a separate driver instead of updating the one you have.

## Setup

1. Set up PiPup on the TV (above). Turn the TV on.
2. Pick the TV in **TVs Found** (the driver looks for TVs when it is added; the ones where PiPup answers come first, marked *PiPup answers*; run **Find TVs** to look again), or type its IP address in **TV IP Address**. **Status** says *Ready*.
3. Run **Test Notification**: the TV shows *Control4 · Test: pop-ups from Control4 work on this TV.*
4. Choose what this TV shows: **Doorbell**, **Camera Alerts**, **Doors and Gates**, **Alarm**, **Other** (Doorbell and Alarm are on), **Quiet Hours**, and the look: **Position**, **Seconds On Screen**, **Pictures**.

### Status

| Status | Means |
|---|---|
| Ready | PiPup answers and the screen is on: pop-ups show |
| Off | The TV does not answer (it answered at this address before), or its screen is off |
| Not reachable | Nothing has answered at this address yet: check the address and that the TV is on |
| The TV answers, but PiPup does not | PiPup is not running, or listens on another port: open PiPup on the TV once; check **PiPup Port** |
| PiPup asks for a token | A token is set in PiPup: enter it in **PiPup Token** |
| PiPup refuses this controller | PiPup's IP allowlist leaves the controller out: add the address Status names |
| Enter the TV's IP address, or pick it in TVs Found | No address yet |

When **Quiet Hours** cannot be read, **Status** adds *Quiet Hours not understood: write it as 22:00-07:00*.

### Settings

| Property | |
|---|---|
| Status | What the driver is doing (above) |
| TV | The TV's name and PiPup's version, as PiPup reports them |
| TV IP Address | The TV's IP address, for example `192.168.1.50` |
| TVs Found | The TVs and casting devices that answered **Find TVs**, the ones where PiPup answers first. Picking one fills in TV IP Address |
| PiPup Port | 7979, unless it was changed in PiPup's settings |
| PiPup Token | Only when a token is set in PiPup's settings: the same token. Never written to a log |
| Doorbell · Camera Alerts · Doors and Gates · Alarm · Other | *On* or *Off*: which of DirectorLink's notifications this TV shows. Doorbell and Alarm are *On* by default |
| Quiet Hours | From-to in the controller's local time, for example `22:00-07:00` (also `22-7`): no pop-ups then. Empty: none |
| Pictures | *On* (default): the notification's picture shows in the pop-up |
| Position | *Top Right* (default), *Top Left*, *Bottom Right*, *Bottom Left*, *Center* |
| Seconds On Screen | 3 to 120, 15 by default |
| Log Level | *Info* writes one line for every pop-up. *Debug* and *Trace* show every check and request |

**Actions:** Find TVs · Test Notification · Print Diagnostics

**Print Diagnostics** shows the driver version, the TV and PiPup (its screen, whether it wants a token), the last checks, the look, the kinds and Quiet Hours, the DirectorLink variables and the last 10 notifications with what happened to each. It never shows the token.

### When a pop-up shows

- **Only when the screen is on.** Just before each pop-up the driver asks PiPup (`/status`); a TV with its screen off gets nothing.
- **The TV has 3 seconds to answer.** No answer (off, or not on the network): the pop-up is dropped, with one line in the log. The driver never turns the TV on.
- **One pop-up every 5 seconds at most,** on each TV. Others wait their turn; a doorbell or the alarm goes before the rest. One that waited more than 30 seconds (a minute for a doorbell or the alarm), or that does not fit (5 wait at most), is dropped.
- **Only the kinds switched on, and nothing during Quiet Hours.** Show Notification from programming is shown whatever the kinds, but not during Quiet Hours. Test Notification always shows.
- **The text as it was sent:** the title and the message, Hebrew and other right-to-left languages as given.
- **One pop-up on the screen:** a new one replaces the one still showing.
- **PiPup is checked** every minute while it answers; when it does not, after 5 s, 30 s, 2 min, then every 5 min. Each pop-up tries the TV whatever the last check said.

### Pictures

- **From DirectorLink**, the notification's `PICTURE` (a picture on the controller), and **from programming**, Show Notification's **Picture URL** (for example a camera's snapshot address).
- **The driver fetches the picture itself** and sends it inside the pop-up. The TV never has to reach the controller or the camera, and a picture that lasts 60 seconds cannot expire on the way. The driver runs on the controller, so an address with `127.0.0.1` works, and a login written in a camera's address (`http://user:password@192.168.1.30/snapshot.jpg`) is sent as a login. The login is never written to the log.
- A picture that cannot be fetched within 2 seconds, or is larger than 1.5 MB, goes as its address instead, for PiPup to fetch (`127.0.0.1` becomes the controller's address).
- JPEG, PNG, GIF and WebP. **Pictures** *Off* sends text only.

## DirectorLink

DirectorLink 1.13 and newer sends its notifications to this driver as soon as both are in the project. Nothing needs to be set up: the driver follows the **DirectorLink notification agreement, version 1**, the same as DirectorLink · LG TV Notifications, so DirectorLink recognizes it by what it says, not by its file name.

### The agreement, version 1

| What | The driver | DirectorLink |
|---|---|---|
| **Marker** | A string variable `DIRECTORLINK_NOTIFY`, value `1` (the agreement's version), set at every start | Knows the driver takes notifications |
| **Kinds** | A string variable `DIRECTORLINK_NOTIFY_KINDS`: the kinds the driver shows, comma-separated, from `doorbell`, `camera`, `door`, `alarm`, `other`; updated whenever its settings change (empty: none) | Sends only those kinds |
| **A notification** | Takes the command `DIRECTORLINK_NOTIFY` | Sends it with `C4:SendToDevice`, to every driver with the marker |

1. **The variables** are ordinary driver variables (`C4:AddVariable`), read by their names, added **after the driver's existing variables**, never reordering them. This driver's are `LAST_NOTIFICATION`, then `DIRECTORLINK_NOTIFY`, then `DIRECTORLINK_NOTIFY_KINDS`, written at every start.
2. **The command** `DIRECTORLINK_NOTIFY` comes by `C4:SendToDevice`: in `ExecuteCommand` when sent to the driver's own device, in `ReceivedFromProxy` when sent to a proxy; a driver takes it from both. Its parameters, all strings:

   | Parameter | |
   |---|---|
   | `VERSION` | `1`. A later version only adds: read it as version 1 |
   | `ID` | Unique for each notification, the same for every target. The same ID again within 10 minutes is ignored |
   | `KIND` | `doorbell`, `camera`, `door`, `alarm` or `other` (another value is taken as `other`) |
   | `TITLE`, `MESSAGE` | The final text, in the home's language (it may be Hebrew, right to left), UTF-8. Shown exactly as given |
   | `PICTURE` | Optional. An `http://` address on the controller that gives a JPEG for 60 seconds. This driver fetches it and shows it in the pop-up |

3. **Rules for the driver:** never block; only the kinds switched on, nothing during Quiet Hours; at most one pop-up every 5 seconds on each screen, a doorbell or the alarm first; set `LAST_NOTIFICATION`, then fire `Notification Shown` or `Notification Failed` (a notification left out on purpose fires neither); work the same without DirectorLink.

```lua
-- DirectorLink's side: to each device whose driver says DIRECTORLINK_NOTIFY = "1" and lists the kind
C4:SendToDevice(deviceId, "DIRECTORLINK_NOTIFY", {
    VERSION = "1", ID = "ring-158-1760206443", KIND = "doorbell",
    TITLE = "Front door", MESSAGE = "Someone is at the door",
    PICTURE = "http://127.0.0.1:47200/notify/ring-158.jpg",
})
```

## Programming

- **Command:** **Show Notification** (`SHOW_NOTIFICATION`), with **Title**, **Message** and an optional **Picture URL**. Shown whatever the kinds, not during Quiet Hours. For example: *When* the gate opens → Show Notification *Gate*, *Opened*, `http://user:password@192.168.1.31/snapshot.jpg` (the gate camera's snapshot).
- **Events:** **Notification Shown** · **Notification Failed** (off, not reachable, PiPup not running or refusing, or no answer).
- **Variable:** `LAST_NOTIFICATION` (STRING): the text of the last pop-up shown or failed, as `Title: Message`. Set before the event fires.
- **Several TVs:** add Show Notification for each TV in the same *When*; they run one after the other at once.

## Updating

1. Download the new `DirectorLink-Android-TV.c4z` from the [releases](../../releases).
2. Check that the name is exactly `DirectorLink-Android-TV.c4z`, not `... (1).c4z`.
3. **Driver → Add or Update Driver or Agent**. The driver keeps its settings and the programming.

**From 1.0.0-beta.1:** the **TV App** property is gone (the driver works with PiPup only); install PiPup on the TV as above.

## Troubleshooting

| What you see | What to do |
|---|---|
| Not reachable | Check **TV IP Address**, that the TV is on, and that the controller and the TV are on the same network. **Find TVs** lists what answers; PiPup's main screen shows the TV's address |
| The TV answers, but PiPup does not | Open PiPup on the TV once; check **PiPup Port** against the port PiPup's screen shows |
| PiPup asks for a token / refuses this controller | Enter PiPup's token in **PiPup Token**, or add the controller's address to PiPup's allowlist (or turn them off in PiPup) |
| *Ready*, but nothing on the screen | In PiPup, select **Grant display permission** again, and try PiPup's own test button |
| A pop-up without its picture | **Print Diagnostics** and the log at *Debug* say why the picture could not be fetched |
| *Ready*, but no pop-ups from DirectorLink | Check the kinds and **Quiet Hours**. **Print Diagnostics** lists the last 10 notifications and why each was skipped or not shown |

For details run **Print Diagnostics**, with **Log Level** set to *Debug*. The output appears in the Lua tab and in the driver log.

## Trying the beta

1. Install PiPup on the TV and press its test button. Give the TV a fixed IP address and turn it on.
2. Add **DirectorLink · Android TV Notifications** to the TV's room, set **Log Level** to *Trace*, and pick the TV in **TVs Found** (or type its address).
3. Run **Test Notification**. Then **Show Notification** from programming with a Hebrew title and message and a camera's snapshot address as **Picture URL**.
4. Turn the TV off (standby) and run **Test Notification** again: nothing shows, and the log says why (its screen is off, or it did not answer within 3 s).
5. Run **Print Diagnostics** and send it with the Lua tab output (or `driver_log.log`), the TV's model, and photos of the pop-ups, in an [issue](../../issues).

Every line of the driver carries `Android TV '<name>':` after its time and level. It never shows the token or a login from a picture's address.

## Privacy

The driver talks only to PiPup on the TV, to the picture's address it is given (the controller, a camera), and, for **Find TVs**, to the casting devices that answer the search on the home network. It sends nothing to DirectorLink, Google, the app's maker or anyone else, and collects no usage data.

## Support

Community-supported, best effort. Report problems in [Issues](../../issues).

Please include the TV model and its Android / Google TV version, PiPup's version (the **TV** property), your Control4 OS version, the **Print Diagnostics** output and the log with **Log Level** set to *Debug*. Remove addresses and names you don't want to share. Security problems: see [SECURITY.md](SECURITY.md).

## Building from source

```
pip install lupa pillow
python tools/make_icons.py       # after changing icons
cd tests && python test_static.py && python test_xml.py && python test_protocol.py && python test_driver.py && cd ..
python tools/build.py            # -> dist/DirectorLink-Android-TV.c4z, dist/SHA256SUMS.txt
```

`test_static.py` needs `luac` 5.1 (`apt install lua5.1`). `tests/live_test.py` runs the same driver code against a real TV from a computer on the TV's network (not part of CI): `python tests/live_test.py find`, or `python tests/live_test.py <TV IP> [picture URL] [token=...]`.

| Path | Contents |
|---|---|
| `src/core.lua` | Logging (the token and a login in an address never logged), timers, variables and events, saved settings, utilities |
| `src/json.lua` | JSON (UTF-8 text through as it is) |
| `src/ssdp.lua` | Find TVs: the SSDP search for casting devices (DIAL) and their descriptions |
| `src/tvapp.lua` | The TV and PiPup: `/status`, `/notify`, the token, the checks |
| `src/notify.lua` | Notifications: IDs, kinds, Quiet Hours, one every 5 seconds, a doorbell or the alarm first, the picture fetched and carried inline |
| `src/driver.lua`, `src/driver.xml`, `src/www/` | The driver, its definition, documentation and icons |
| `tools/` | `build.py` (package), `make_icons.py` (icons) |
| `tests/` | `harness.py` (Lua 5.1 with a fake Director and a virtual clock), `fake_apps.py` (PiPup as it answers, picture servers, the search), the tests, and `live_test.py` |
| `VERSION`, `CHANGELOG.md`, `docs/releases/` | The version, the change log, and the notes for each release |

The driver version Composer compares is major·1000000 + minor·10000 + patch·100 + build, where build is the beta number, or 99 for the release: `1.0.0-beta.2` → `1000002`, `1.0.0` → `1000099`.

The tests run the real driver code in Lua 5.1 against a fake Director and `fake_apps.py`, PiPup as it answered on a real TV. They cover `/status` before each pop-up (the screen off, a token wanted), `/notify` (Hebrew, position, duration, the picture), a token (401) and the IP allowlist (403), a TV that is off (3 s), PiPup not running (refused at once), slow answers, the pictures (fetched and carried inline byte for byte, a camera with a login, not a picture, too large, too slow, Pictures Off), the checks (every minute; 5 s, 30 s, 2 min, then every 5 min), a restart, the agreement's variables and both ways the command comes in, the kinds, IDs, Quiet Hours, one pop-up every 5 seconds with a doorbell or the alarm first, Find TVs, and that no log line shows the token or a login.

**How it works**

- **PiPup:** `GET http://<TV>:7979/status` (version, name, `screenOn`, `authEnabled`), then `POST /notify` with JSON: `id`, `title`, `message`, `duration`, `position`, `media.image.uri` (the picture inline as a `data:` URI, or its address), with `Authorization: Bearer <token>` when a token is set. Find TVs asks `GET /ping` (`pipup <version>`).
- **Find TVs:** SSDP `M-SEARCH` for `urn:dial-multiscreen-org:service:dial:1`, each device's description (`friendlyName`), and `/ping` on PiPup's port.

**Rules for new versions**

- `VERSION` is the only place the version is set.
- **Never rename** the `.c4z` file, and from 1.0.0 on **never change or remove** the order of variables, event ids, command and property names. Adding new ones at the end is fine.
- Update `VERSION`, `CHANGELOG.md`, the change log in `src/www/documentation.html`, and `docs/releases/v<version>.md`. Then tag `v<version>`: GitHub Actions tests, builds and publishes the release with `SHA256SUMS.txt` (a pre-release for `-beta` versions). Releases are immutable.

## License and trademarks

[Apache License 2.0](LICENSE). See also [NOTICE](NOTICE).

The requests to PiPup follow PiPup's own documentation ([pipup.android.savin.nyc](https://pipup.android.savin.nyc/how-to-use.html)) and its maker's Home Assistant integration ([hassio-integration-pipup-notification](https://github.com/alex-savin/hassio-integration-pipup-notification), MIT). No code was copied from them. Control4 interfaces follow the public [Snap One DriverWorks documentation](https://snap-one.github.io/docs-driverworks-fundamentals/). DirectorLink's own source code: [github.directorlink.io](https://github.directorlink.io).

Installing third-party drivers or changing a Control4 project can affect compatibility, support, warranty or recovery. Keep a backup of your project.

Apache License 2.0. Copyright 2026 DirectorLink. DirectorLink is an independent project, not affiliated with Control4 or Snap One. Not affiliated with or endorsed by Google, Amazon or the makers of the TV apps it works with. Android TV, Google TV and Fire TV are trademarks of their owners.
