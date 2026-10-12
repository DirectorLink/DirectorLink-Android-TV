# Security policy

## Reporting a vulnerability

Please report security problems privately, not in public issues.

Open this repository's **Security** tab and choose **Report a vulnerability**. This uses GitHub's private vulnerability reporting, so only the maintainers see your report.

Include what you found, the driver version (the *Driver* line of **Print Diagnostics**), and the steps to reproduce it. Leave out real passwords, addresses and names.

We will confirm the report, fix the problem in a new release, and credit you if you wish.

## Supported versions

Only the [newest release](../../releases) gets security fixes.

## Scope

The driver runs on the Control4 controller and talks only to the TV whose address is in its properties (and, for **Find TVs**, to the casting devices that answer an SSDP search on the home network, whose description it reads, and to their app's port).

- **The TV apps have no login.** Notifications for Android TV (port 7676) and PiPup (port 7979) show what any device on the home network sends them, by their design. The driver adds no risk to that, and needs nothing secret: it keeps no password or key. Keep the TVs on a network you trust (not a guest network shared with strangers' devices).
- **Plain HTTP.** The requests and the pop-ups' texts travel unencrypted on the home network, as the apps take them.
- **Pictures.** The TV fetches a picture from the address the notification gives. A login in that address (`http://user:password@...`) goes to the TV with the pop-up, as the address does, but never into a log line or Print Diagnostics.
- **Who can show pop-ups.** Any driver or programming in the Control4 project can send `DIRECTORLINK_NOTIFY` or **Show Notification**, as it can send any command to any device: the project is trusted.
- **Never the TV's power.** The driver never asks an app to turn the TV or its screen on or off.

DirectorLink is an independent project, not affiliated with Control4 or Snap One. Not affiliated with or endorsed by Google, Amazon or the makers of the TV apps it works with. Android TV, Google TV and Fire TV are trademarks of their owners.
