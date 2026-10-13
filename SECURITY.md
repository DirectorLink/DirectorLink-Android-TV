# Security policy

## Reporting a vulnerability

Please report security problems privately, not in public issues.

Open this repository's **Security** tab and choose **Report a vulnerability**. This uses GitHub's private vulnerability reporting, so only the maintainers see your report.

Include what you found, the driver version (the *Driver* line of **Print Diagnostics**), and the steps to reproduce it. Leave out real tokens, passwords, addresses and names.

We will confirm the report, fix the problem in a new release, and credit you if you wish.

## Supported versions

Only the [newest release](../../releases) gets security fixes.

## Scope

The driver runs on the Control4 controller and talks only to PiPup on the TV whose address is in its properties, to the picture's address a notification gives (the controller, a camera), and, for **Find TVs**, to the casting devices that answer an SSDP search on the home network (their description, and PiPup's `/ping`).

- **PiPup has no login by default.** It shows what any device on the home network sends it, by its design. Its settings can require a token, and can allow only some addresses (an IP allowlist): with either, add the controller (the token in the driver's **PiPup Token**, the controller's address in PiPup's allowlist). Keep the TVs on a network you trust.
- **The token** is kept in the **PiPup Token** property (a masked password field in Composer) and sent only to PiPup on the TV, as `Authorization: Bearer`. It is never written to a log line, a property other than its own, or Print Diagnostics. PiPup speaks plain HTTP, so the token and the pop-ups travel unencrypted on the home network.
- **Pictures.** The driver fetches the picture from the address it is given and sends it to PiPup inside the pop-up. A login in that address (`http://user:password@...`) goes only to that address, and never into a log line or Print Diagnostics.
- **Who can show pop-ups.** Any driver or programming in the Control4 project can send `DIRECTORLINK_NOTIFY` or **Show Notification**, as it can send any command to any device: the project is trusted.
- **Never the TV's power.** The driver never asks PiPup to turn the TV or its screen on or off.

DirectorLink is an independent project, not affiliated with Control4 or Snap One. Not affiliated with or endorsed by Google, Amazon or the makers of the TV apps it works with. Android TV, Google TV and Fire TV are trademarks of their owners.
