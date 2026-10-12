# DirectorLink · Android TV Notifications for Control4

Free, open-source Control4 driver that shows notifications as a pop-up **with a picture** on TVs that run Google TV, Android TV or Fire TV: a doorbell ring with who is at the door, a camera alert, a door or gate opened, the alarm. Part of [DirectorLink Drivers](https://directorlink.io/drivers).

It works on your local network only: the driver talks straight to a free app on the TV. No cloud, no account, no extra hardware.

Free. No subscription, no license key, no account with us.

Made by [DirectorLink](https://directorlink.io), the open-source management layer for Control4 homes. Works on its own: DirectorLink is not required (Composer programming can show pop-ups too).

DirectorLink is an independent project, not affiliated with Control4 or Snap One. Not affiliated with or endorsed by Google, Amazon or the makers of the TV apps it works with. Android TV, Google TV and Fire TV are trademarks of their owners.

**Download:** [releases](../../releases) · **Help and updates:** [directorlink.io/drivers/android-tv](https://directorlink.io/drivers/android-tv) (online with 1.0.0)

> **Beta.** The driver sends what the apps take as Home Assistant, FHEM and PiPup's own documentation describe it, and passes its tests against fake apps built from that, but it has not run on a real TV yet. If you try it, please send the log: see [Trying the beta](#trying-the-beta).

## What you get

| | |
|---|---|
| A pop-up on the TV | Over whatever is on, in a corner of the screen (you choose which), for 15 seconds or as long as you set |
| The picture | Who is at the door or the gate, in the pop-up: the picture DirectorLink sends with a ring, or any camera's snapshot address from programming |
| With DirectorLink 1.13 | DirectorLink's notifications: doorbell rings, camera alerts, doors and gates opened, the alarm, others; you choose which kinds each TV shows |
| Composer programming | **Show Notification** (Title, Message, Picture URL); *Notification Shown* and *Notification Failed*; `LAST_NOTIFICATION` |
| Quiet Hours | No pop-ups on this TV at night, or whenever you set |
| Several TVs | One driver per TV. Each has its own kinds, Quiet Hours and look; a notification shows on every TV that is on, at the same moment |

What it never does: turn the TV on, change its channel, input or volume.

## Which TVs

Look in the TV's **Settings → About** (or **Settings → System → About**): if it says **Google TV**, **Android TV** or **Fire OS 7 / 8**, it works. The same brand often ships different systems in different countries, so check the TV itself.

| Works | |
|---|---|
| Google TV / Android TV | Sony Bravia (all since 2021), TCL (most countries), Hisense (US Google TV models), Sharp (Europe, Japan), Xiaomi, Panasonic (2026 Google TV models), Philips (2021-2025 upper range only), Nokia, Thomson, Motorola, OnePlus, Skyworth, Haier, iFFALCON, Kogan, Metz Blue, some Grundig and JVC |
| Fire TV (Fire OS 7 / 8) | Amazon's Fire TV TVs, Panasonic 2024-2025 flagships, and the Fire TV models of TCL, Hisense, Toshiba, Xiaomi, JVC, Grundig, Insignia |
| Streaming boxes (on any TV) | Google TV Streamer, Chromecast with Google TV, Nvidia Shield, Xiaomi TV Box S, onn. 4K, Nokia Streaming Box, Fire TV Stick / Cube with Fire OS 7 or 8 |

| Does not work | |
|---|---|
| Samsung (Tizen), Vizio, Roku TVs, Hisense and Toshiba with VIDAA, Philips 2026 (Titan OS), Loewe, Bang & Olufsen | Not Android: no app can run there |
| LG (webOS) | Use [DirectorLink · LG TV Notifications](https://directorlink.io/drivers/lg-tv) (pop-ups without a picture) |
| The newest Fire TV sticks (Fire TV Stick 4K Select 2025, Fire TV Stick HD 2026, Fire TV Stick 4K 3rd gen 2026) | Amazon's Vega OS runs no Android apps |

## The app on the TV

The TV needs one of two free apps that show pop-ups sent over the home network. Choose it per TV in the driver's **TV App** property.

| | **Notifications for Android TV** (the default) | **PiPup** |
|---|---|---|
| Install | From **Google Play** on the TV (on Fire TV: **Notifications for Fire TV** from the Amazon Appstore) | From a computer, with PiPup's install script (the TV in developer mode) |
| TVs | Android 11 and newer (most TVs from 2021); any Fire TV with Fire OS 7 / 8 | Android 6 and newer, older TVs too; Fire TV |
| Picture | Yes, above the text | Yes, in the pop-up |
| Can the driver tell that the screen is off? | No | Yes: a TV with its screen off gets nothing |
| Made by | Christian Fees ("dream apps"); closed source | Open source ([github.com/mhoogenbosch/PiPup](https://github.com/mhoogenbosch/PiPup), the maintained version) |

### Setting up Notifications for Android TV

1. On the TV, open **Google Play**, search **Notifications for Android TV** and install it (Fire TV: **Notifications for Fire TV** in the Appstore).
2. Open it once and follow its setup. Allow **Notification access** and **Display over other apps** (on Google TV: **Settings → Apps → Special app access**).
3. Restart the TV.

The app's purchases are for its phone app; the TV shows pop-ups from Control4 without them (as Home Assistant's documentation says). A system update has been seen to switch its permissions off again: if pop-ups stop, check them.

### Setting up PiPup

1. On the TV: **Settings → System → About**, select **Build** seven times; then in **Developer options** turn on **USB debugging** (and **Wireless debugging** on recent Google TV). Fire TV: **My Fire TV → About**, select the device name seven times, then **ADB debugging**.
2. On a computer on the same network: download the latest release of [PiPup](https://github.com/mhoogenbosch/PiPup/releases) and run its `install.ps1` (Windows) or `install.sh` with the TV's IP address. Accept the debugging request on the TV. The script installs PiPup, gives it the permissions it needs and checks it.
3. In the driver, set **TV App** to **PiPup**.

On TCL Google TVs, follow PiPup's own TCL notes (TCL's system stops apps in the background). After reinstalling PiPup, run its script again.

## Requirements

- **Control4 OS 3.3.0 or newer** and Composer Pro.
- **A TV with Google TV, Android TV or Fire TV** (above), with one of the two apps.
- **A fixed IP address for the TV** in the router. The controller reaches the TV on port 7676 (Notifications for Android TV) or 7979 (PiPup).
- For pictures: the TV can reach the picture's address (the controller, or the camera) on the home network.
- For DirectorLink's notifications: DirectorLink 1.13 or newer.

## Installation

1. Download `DirectorLink-Android-TV.c4z` from the [releases](../../releases).
2. In Composer Pro: **Driver → Add or Update Driver or Agent**.
3. Search **DirectorLink** and add **DirectorLink · Android TV Notifications** to the room of the TV. Add it once for each TV.

> **Keep the exact file name.** If your browser saves a second copy as `DirectorLink-Android-TV (1).c4z`, rename it before you upload. Composer knows a driver by its file name, so a renamed copy installs as a separate driver instead of updating the one you have.

## Setup

1. Set up the app on the TV (above). Turn the TV on.
2. In the driver's properties, choose the **TV App**.
3. Pick the TV in **TVs Found** (the driver looks for TVs when it is added and asks each whether the app answers; run **Find TVs** to look again), or type its IP address in **TV IP Address**. **Status** says *Ready*.
4. Run **Test Notification**: the TV shows *Control4 · Test: pop-ups from Control4 work on this TV.*
5. Choose what this TV shows: **Doorbell**, **Camera Alerts**, **Doors and Gates**, **Alarm**, **Other** (Doorbell and Alarm are on), **Quiet Hours**, and the look: **Position**, **Seconds On Screen**, **Pictures**.

### Status

| Status | Means |
|---|---|
| Ready | The app answers: pop-ups show |
| Off | The TV does not answer (it answered at this address before), or, with PiPup, its screen is off |
| Not reachable | Nothing has answered at this address yet: check the address and that the TV is on |
| The TV answers, but ... does not | The TV is on, the app is not running: install it and open it once (PiPup: run its script again) |
| PiPup may not show pop-ups | PiPup lacks *Display over other apps*: run its script again |
| Enter the TV's IP address, or pick it in TVs Found | No address yet |

When **Quiet Hours** cannot be read, **Status** adds *Quiet Hours not understood: write it as 22:00-07:00*.

### Settings

| Property | |
|---|---|
| Status | What the driver is doing (above) |
| TV | The app, and with PiPup the TV's name, model and Android version |
| TV App | *Notifications for Android TV* (default) or *PiPup* |
| TV IP Address | The TV's IP address, for example `192.168.1.50` |
| TVs Found | The TVs and casting devices that answered **Find TVs**, the ones where the app answers first. Picking one fills in TV IP Address |
| Doorbell · Camera Alerts · Doors and Gates · Alarm · Other | *On* or *Off*: which of DirectorLink's notifications this TV shows. Doorbell and Alarm are *On* by default |
| Quiet Hours | From-to in the controller's local time, for example `22:00-07:00` (also `22-7`): no pop-ups then. Empty: none |
| Pictures | *On* (default): the notification's picture shows in the pop-up |
| Position | *Top Right* (default), *Top Left*, *Bottom Right*, *Bottom Left*, *Center* |
| Seconds On Screen | 3 to 120, 15 by default |
| Log Level | *Info* writes one line for every pop-up. *Debug* and *Trace* show every check and request |

**Actions:** Find TVs · Test Notification · Print Diagnostics

**Print Diagnostics** shows the driver version, the TV and its app, the last checks, the look, the kinds and Quiet Hours, the DirectorLink variables and the last 10 notifications with what happened to each.

### When a pop-up shows

- **The TV has 3 seconds to take the connection.** No answer (off, or not on the network): the pop-up is dropped, with one line in the log. The driver never turns the TV on.
- **With PiPup, only when the screen is on.** PiPup tells the driver; a TV with its screen off gets nothing. Notifications for Android TV cannot tell: a TV that keeps its network on in standby takes the pop-up and nobody sees it.
- **One pop-up every 5 seconds at most,** on each TV. Others wait their turn; a doorbell or the alarm goes before the rest. One that waited more than 30 seconds (a minute for a doorbell or the alarm), or that does not fit (5 wait at most), is dropped.
- **Only the kinds switched on, and nothing during Quiet Hours.** Show Notification from programming is shown whatever the kinds, but not during Quiet Hours. Test Notification always shows.
- **The text as it was sent:** the title and the message, Hebrew and other right-to-left languages as given.
- **The app is checked** every minute while it answers; when it does not, after 5 s, 30 s, 2 min, then every 5 min. Each pop-up tries the TV whatever the last check said.

### Pictures

The TV fetches the picture itself, from the address the notification gives:

- **From DirectorLink**, the notification's `PICTURE`: an address on the controller. When it names the controller as `127.0.0.1` (or `localhost`), the driver gives the TV the controller's own address on the home network instead.
- **From programming**, Show Notification's **Picture URL**: for example a camera's snapshot address. The TV fetches it straight from the camera, so the address must open without a login prompt. A login written into the address (`http://user:password@...`) may not be passed on by the TV's app (not yet confirmed); many cameras take the login as part of the address instead (for example `...snapshot?user=...&password=...`). A login in the address is never written to the log.

The TV must be able to reach that address on the home network. **Pictures** *Off* sends text only.

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
   | `PICTURE` | Optional. An `http://` address on the controller that gives a JPEG for 60 seconds. This driver hands it to the TV, which fetches it: the address must answer on the controller's home-network address too (`127.0.0.1` is replaced by it), without a login |

3. **Rules for the driver:** never block; only the kinds switched on, nothing during Quiet Hours; at most one pop-up every 5 seconds on each screen, a doorbell or the alarm first; set `LAST_NOTIFICATION`, then fire `Notification Shown` or `Notification Failed` (a notification left out on purpose fires neither); work the same without DirectorLink.

```lua
-- DirectorLink's side: to each device whose driver says DIRECTORLINK_NOTIFY = "1" and lists the kind
C4:SendToDevice(deviceId, "DIRECTORLINK_NOTIFY", {
    VERSION = "1", ID = "ring-158-1760206443", KIND = "doorbell",
    TITLE = "Front door", MESSAGE = "Someone is at the door",
    PICTURE = "http://192.168.1.10:47200/notify/ring-158.jpg",
})
```

## Programming

- **Command:** **Show Notification** (`SHOW_NOTIFICATION`), with **Title**, **Message** and an optional **Picture URL**. Shown whatever the kinds, not during Quiet Hours. For example: *When* the gate opens → Show Notification *Gate*, *Opened*, and the gate camera's snapshot address (see [Pictures](#pictures)).
- **Events:** **Notification Shown** · **Notification Failed** (off, not reachable, the app not running, or no answer).
- **Variable:** `LAST_NOTIFICATION` (STRING): the text of the last pop-up shown or failed, as `Title: Message`. Set before the event fires.
- **Several TVs:** add Show Notification for each TV in the same *When*; they run one after the other at once.

## Updating

1. Download the new `DirectorLink-Android-TV.c4z` from the [releases](../../releases).
2. Check that the name is exactly `DirectorLink-Android-TV.c4z`, not `... (1).c4z`.
3. **Driver → Add or Update Driver or Agent**. The driver keeps its settings and the programming.

## Troubleshooting

| What you see | What to do |
|---|---|
| Not reachable | Check **TV IP Address**, that the TV is on, and that the controller and the TV are on the same network. **Find TVs** lists what answers |
| The TV answers, but Notifications for Android TV does not | Install it from Google Play on the TV and open it once; check its permissions (above) |
| *Ready*, but nothing on the screen | Notifications for Android TV: allow *Display over other apps* and *Notification access*, restart the TV. PiPup: run its script again |
| The pop-up shows, without the picture | The TV cannot reach the picture's address: try it in a browser on another device on the TV's network |
| *Ready*, but no pop-ups from DirectorLink | Check the kinds and **Quiet Hours**. **Print Diagnostics** lists the last 10 notifications and why each was skipped or not shown |
| Off, but the TV is on | Notifications for Android TV: the app may have been stopped by the TV; open it once. PiPup: its screen reports off |

For details run **Print Diagnostics**, with **Log Level** set to *Debug*. The output appears in the Lua tab and in the driver log.

## Trying the beta

1. Set up **Notifications for Android TV** on the TV (and, if you can, PiPup too), give the TV a fixed IP address and turn it on.
2. Add **DirectorLink · Android TV Notifications** to the TV's room, set **Log Level** to *Trace*, and pick the TV in **TVs Found** (or type its address).
3. Run **Test Notification**. Then **Show Notification** from programming with a Hebrew title and message and a camera's snapshot address as **Picture URL**.
4. Put the TV in standby and run **Test Notification** again.
5. Set **TV App** to *PiPup* (if installed) and repeat 3 and 4.
6. Run **Print Diagnostics** and send it with the Lua tab output (or `driver_log.log`), the TV's model, and photos of the pop-ups, in an [issue](../../issues).

Every line of the driver carries `Android TV '<name>':` after its time and level. It never shows a login from a picture's address.

## Privacy

The driver talks only to the TV on your home network (and, for **Find TVs**, to the casting devices that answer the search there). It sends nothing to DirectorLink, Google, Amazon, the app makers or anyone else, and collects no usage data. The TV fetches the picture from the address the notification gives, on the home network.

## Support

Community-supported, best effort. Report problems in [Issues](../../issues).

Please include the TV model and its Android / Google TV / Fire OS version, the app and its version, your Control4 OS version, the **Print Diagnostics** output and the log with **Log Level** set to *Debug*. Remove addresses and names you don't want to share. Security problems: see [SECURITY.md](SECURITY.md).

## Building from source

```
pip install lupa pillow
python tools/make_icons.py       # after changing icons
cd tests && python test_static.py && python test_xml.py && python test_protocol.py && python test_driver.py && cd ..
python tools/build.py            # -> dist/DirectorLink-Android-TV.c4z, dist/SHA256SUMS.txt
```

`test_static.py` needs `luac` 5.1 (`apt install lua5.1`). `tests/live_test.py` runs the same driver code against a real TV from a computer on the TV's network (not part of CI): `python tests/live_test.py find`, or `python tests/live_test.py <TV IP> [nfa|pipup] [picture URL]`.

| Path | Contents |
|---|---|
| `src/core.lua` | Logging (a login in an address never logged), timers, variables and events, saved settings, utilities |
| `src/json.lua` | JSON (UTF-8 text through as it is) |
| `src/ssdp.lua` | Find TVs: the SSDP search for casting devices (DIAL) and their descriptions |
| `src/tvapp.lua` | The TV and its app: Notifications for Android TV and PiPup, the checks, the pop-up |
| `src/notify.lua` | Notifications: IDs, kinds, Quiet Hours, one every 5 seconds, a doorbell or the alarm first, the picture's address |
| `src/driver.lua`, `src/driver.xml`, `src/www/` | The driver, its definition, documentation and icons |
| `tools/` | `build.py` (package), `make_icons.py` (icons) |
| `tests/` | `harness.py` (Lua 5.1 with a fake Director and a virtual clock), `fake_apps.py` (the two apps and the search), the tests, and `live_test.py` |
| `VERSION`, `CHANGELOG.md`, `docs/releases/` | The version, the change log, and the notes for each release |

The driver version Composer compares is major·1000000 + minor·10000 + patch·100 + build, where build is the beta number, or 99 for the release: `1.0.0-beta.1` → `1000001`, `1.0.0` → `1000099`.

The tests run the real driver code in Lua 5.1 against a fake Director and `fake_apps.py`. They cover the request to Notifications for Android TV (a strict multipart parse of every field, the icon byte for byte, Hebrew), PiPup's `/state` and `/notify` (the screen off, no overlay permission, an early PiPup without `/state`, never `/power`), the picture's address (127.0.0.1, Pictures Off, not http, a camera login kept out of the log), a TV that is off (3 s), an app not running (refused at once), slow and refusing answers, the checks (every minute; 5 s, 30 s, 2 min, then every 5 min), a restart, the agreement's variables and both ways the command comes in, the kinds, IDs, Quiet Hours, one pop-up every 5 seconds with a doorbell or the alarm first, and Find TVs.

**How it works**

- **Notifications for Android TV:** `POST http://<TV>:7676/` as `multipart/form-data` with `msg`, `title`, `duration`, `position`, `bkgcolor`, `transparency`, `interrupt`, `imageurl` and a small icon as the file part `filename`, the request Home Assistant's integration and FHEM send. `GET /` checks that it answers.
- **PiPup:** `GET http://<TV>:7979/state` (the screen, the overlay permission, the device), then `POST /notify` with JSON (`id`, `duration`, `position`, `title`, `message`, `media.image`).
- **Find TVs:** SSDP `M-SEARCH` for `urn:dial-multiscreen-org:service:dial:1`; each device's description (`friendlyName`) and a quick request to the chosen app's port.

**Rules for new versions**

- `VERSION` is the only place the version is set.
- **Never rename** the `.c4z` file, and **never change or remove** the order of variables, event ids, command and property names. Adding new ones at the end is fine.
- Update `VERSION`, `CHANGELOG.md`, the change log in `src/www/documentation.html`, and `docs/releases/v<version>.md`. Then tag `v<version>`: GitHub Actions tests, builds and publishes the release with `SHA256SUMS.txt` (a pre-release for `-beta` versions). Releases are immutable.

## License and trademarks

[Apache License 2.0](LICENSE). See also [NOTICE](NOTICE).

The requests to Notifications for Android TV follow Home Assistant's [nfandroidtv integration](https://github.com/home-assistant/core/tree/dev/homeassistant/components/nfandroidtv) and [notifications-android-tv](https://github.com/engrbm87/notifications_android_tv), and FHEM; the requests to PiPup follow [PiPup's documentation](https://github.com/mhoogenbosch/PiPup). No code was copied from them. Control4 interfaces follow the public [Snap One DriverWorks documentation](https://snap-one.github.io/docs-driverworks-fundamentals/). DirectorLink's own source code: [github.directorlink.io](https://github.directorlink.io).

Installing third-party drivers or changing a Control4 project can affect compatibility, support, warranty or recovery. Keep a backup of your project.

Apache License 2.0. Copyright 2026 DirectorLink. DirectorLink is an independent project, not affiliated with Control4 or Snap One. Not affiliated with or endorsed by Google, Amazon or the makers of the TV apps it works with. Android TV, Google TV and Fire TV are trademarks of their owners.
