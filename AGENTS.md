# SkyridingFrameHider - Agent Instructions

## Project Overview

SkyridingFrameHider is a standalone World of Warcraft addon that makes any user-specified frame invisible while skyriding, flying, or mounted. It has no config UI -- all interaction is via `/sfh` slash commands.

**Target WoW version**: 12.0.0+ (Midnight)
**Lua version**: 5.1 (World of Warcraft uses Lua 5.1 -- see https://www.lua.org/manual/5.1/)
**Interface number**: 120000

## File Structure

```
SkyridingFrameHider/
  SkyridingFrameHider.toc     -- Addon descriptor
  SkyridingFrameHider.lua     -- All addon logic (single file)
  .pkgmeta                    -- BigWigs Packager config
  .github/workflows/release.yml -- Release automation
  .gitignore
  README.md
  AGENTS.md                   -- This file
  wow-ui-source/              -- Gitignored reference clone of Blizzard UI source
```

## API Reference Locations

### Blizzard C_ Namespace APIs (non-widget)

For any Blizzard API that is NOT on a widget (e.g. `C_Item`, `C_PlayerInfo`, `C_UnitAuras`, `C_Timer`, etc.), look up the API signature here:

  https://warcraft.wiki.gg/wiki/World_of_Warcraft_API

Key API systems used by this addon:
- `C_PlayerInfo.GetGlidingInfo()` -- Returns isGliding, canGlide (skyriding detection)
- `C_UnitAuras.GetPlayerAuraBySpellID(spellID)` -- Check for specific buffs
- `C_Timer.NewTicker(interval, callback)` -- Periodic timer
- `IsMounted("player")` -- Check if player is mounted
- `IsFlying("player")` -- Check if player is flying
- `issecretvalue(value)` -- Check if a value is a secret (12.0.0+)

If you cannot understand an API's signature or behavior from the wiki, ask the user rather than guessing.

### Widget APIs (frame methods)

For any widget/frame API (e.g. `frame:GetAlpha()`, `frame:SetAlpha()`, `frame:EnableMouse()`, `frame:IsMouseEnabled()`, etc.), look up the details here:

  https://warcraft.wiki.gg/wiki/Widget_API

Key widget types and hierarchy:
- `FrameScriptObject` -> `Object` -> `ScriptObject` -> `ScriptRegion` -> `Region` -> `Frame`
- `Region:SetAlpha(alpha)` -- Sets opacity (0 = invisible, 1 = fully visible)
- `Region:GetAlpha()` -- Gets current opacity
- `ScriptRegion:EnableMouse([enable])` -- Enable/disable mouse input
- `ScriptRegion:IsMouseEnabled()` -- Check if mouse input is enabled
- `ScriptRegion:Show()` / `ScriptRegion:Hide()` -- Show/hide (we use SetAlpha instead)
- `CreateFrame(frameType, name, parent, template)` -- Create a new frame

Do NOT guess where APIs live in the widget hierarchy. Always verify on the wiki.

### Blizzard Default Frame Annotations

Annotations and source code for Blizzard's default frames are located in the cloned reference repo:

  `wow-ui-source/Interface/AddOns/`

Use this to understand the structure and naming of default UI frames when users want to hide specific Blizzard frames.

### Lua 5.1 Reference

World of Warcraft uses Lua 5.1. Reference manual:

  https://www.lua.org/manual/5.1/

Important WoW-specific Lua notes:
- No `goto` statement (Lua 5.1)
- No bitwise operators (use `bit.band`, `bit.bor`, etc.)
- `table.insert`, `table.remove`, `ipairs`, `pairs` are available
- String library is standard Lua 5.1
- `strtrim()` is a WoW-provided global utility

## Taint and Secrets

### Taint Overview

Taint is WoW's security mechanism that marks code and data from untrusted sources (addons). It prevents addons from automating combat decisions.

**Rules:**
- All addon code starts tainted. Blizzard FrameXML code starts secure.
- Taint spreads: any value created by tainted execution becomes tainted.
- During combat, tainted execution cannot call protected functions (targeting, spell casting, etc.).
- Taint persists until `/reload` or relog.

**Preventing taint spread:**
- Use `hooksecurefunc("FunctionName", handler)` instead of overwriting Blizzard functions.
- Use `frame:HookScript("OnEvent", handler)` instead of `frame:SetScript("OnEvent", handler)` on Blizzard frames.
- Check `InCombatLockdown()` before modifying protected frame attributes.
- Use secure templates (`SecureActionButtonTemplate`) for action buttons.

**Detection:**
- `issecure()` -- Is current execution secure?
- `issecurevariable("name")` / `issecurevariable(table, "key")` -- Is a variable secure?

### Secret Values (12.0.0+)

Secret values are opaque values that tainted code can store and pass but cannot inspect.

**Active during:** encounters (M+ keys, PvP, boss fights), combat (certain APIs), instances (unit identity).

**Cannot do with secrets:** comparisons, arithmetic, use as table keys, indexing, function calls.

**Can do with secrets:** store in variables/tables, pass to functions, concatenate strings, pass to widget APIs (`SetText`, `SetAlpha`, etc.).

**Detection:**
- `issecretvalue(value)` -- Is this a secret value?
- `canaccesssecrets()` -- Can current execution access secrets?
- `canaccessvalue(value)` -- Can we access this specific value?

**Relevance to this addon:** When calling `frame:GetAlpha()`, the return value could be a secret during combat/encounters. The addon already guards against this with `issecretvalue()` checks before storing alpha values.

**Best practices:**
- Always check `issecretvalue()` before performing operations on values that might be secrets.
- Use `frame:SetToDefaults()` to clear secret aspects from objects.
- Focus on visual presentation, not combat logic.
- Store secrets without inspecting them; pass them to appropriate Blizzard APIs.

## Build and Release

### Release Process

1. Tag a version: `git tag v1.0.0` (use `-alpha` or `-beta` suffix for pre-releases)
2. Push the tag: `git push origin v1.0.0`
3. GitHub Actions runs BigWigs Packager, which:
   - Replaces `@project-version@` in the .toc with the tag version
   - Packages the addon (respecting `.pkgmeta` ignore list)
   - Uploads to CurseForge/WoWInterface/Wago (when project IDs are configured)
   - Creates a GitHub release

### .pkgmeta

Controls BigWigs Packager behavior:
- `package-as`: The folder name in the zip
- `externals`: External libraries to download (none for this addon)
- `ignore`: Files excluded from the package

### Version Placeholder

The `.toc` file uses `@project-version@` which is replaced at build time by BigWigs Packager with the git tag.

## Slash Commands

| Command | Description |
|---|---|
| `/sfh` | Show help |
| `/sfh add <frame>` | Add a frame to hide list |
| `/sfh remove <frame>` | Remove a frame from hide list |
| `/sfh list` | List tracked frames |
| `/sfh mode [skyriding\|flying\|mounted]` | Get/set hide mode |

## SavedVariables

`SkyridingFrameHiderDB` is the saved variables table, persisted between sessions:

```lua
SkyridingFrameHiderDB = {
    frameNames = {},       -- Array of global frame name strings
    mode = "skyriding",    -- "skyriding" | "flying" | "mounted"
}
```

## Development Notes

- Frames are made invisible via `SetAlpha(0)` + `EnableMouse(false)`, NOT via `Hide()`. This avoids taint issues with protected frames and preserves layout.
- Original alpha and mouse state are saved before hiding and restored when the condition ends.
- A `C_Timer.NewTicker` at 0.25s is only active while the player is mounted in "flying" or "skyriding" mode, for efficiency. In "mounted" mode the ticker is not needed because mount/dismount is fully captured by events.
- Frame references are resolved from `_G[frameName]` on login and when frames are added/removed.
- The addon registers for `PLAYER_MOUNT_DISPLAY_CHANGED` and `PLAYER_ENTERING_WORLD` events to detect state changes.
