# SkyridingFrameHider

A World of Warcraft addon that lets you hide any frame while skyriding, flying, or mounted. Frames are made invisible (alpha set to 0) rather than hidden, and mouse interaction is disabled to prevent clicking on invisible elements.

No configuration menu -- everything is controlled via slash commands.

## Commands

| Command | Description |
|---|---|
| `/sfh` | Show help with all available commands |
| `/sfh add <framename>` | Add a frame to the hide list |
| `/sfh remove <framename>` | Remove a frame from the hide list |
| `/sfh list` | List all tracked frames |
| `/sfh mode` | Show current hide mode |
| `/sfh mode skyriding` | Only hide while skyriding (default) |
| `/sfh mode flying` | Hide while flying (skyriding + regular flying) |
| `/sfh mode mounted` | Hide whenever mounted |

## Modes

- **skyriding** (default) -- Frames are only hidden while actively skyriding. Uses `C_PlayerInfo.GetGlidingInfo()` and the Skyriding buff for detection.
- **flying** -- Frames are hidden during any type of flying, including both skyriding and regular flying.
- **mounted** -- Frames are hidden whenever you are on any mount, regardless of whether you are flying.

## Finding Frame Names

To add a frame you need its global name. You can discover frame names using:

- `/fstack` -- WoW's built-in frame stack tooltip (shows frame names on mouse hover)
- Addons like **BugSack** or **DevTools** that help inspect the UI

## Release

1. Tag a version: `git tag v1.0.0`
2. Push the tag: `git push origin v1.0.0`
3. GitHub Actions will automatically package and release via BigWigs Packager

Use `-alpha` or `-beta` suffixes for pre-releases (e.g. `v1.0.0-alpha`).

## License

GNU General Public License v3.0
