# Patched Addon API Behavior

This repo tracks a small set of reviewable fixes to the stock AAClassic addon wrapper. The intent is stability and correctness for the existing public addon API surface only.

## Source Changes

### Addon Loader Lifecycle

The addon root event window setup is centralized so refresh/reload creates a fully registered root window each time.

Addon reload now clears pending `api:DoIn` timers and resets window profiler counts before loading the next addon set.

`addons.txt` loading now skips blank lines and comment lines that start with `#` or `--`.

Addon `main.lua` files must return a table. Invalid return values fail that addon instead of breaking the loader after the protected load call.

Saved addon settings are preserved for addons that are absent or fail to load, instead of rebuilding `addon_settings` only from successfully loaded addons.

### Timer Arguments

`api:DoIn(msec, callback, ...)` now preserves the original callback varargs instead of passing a single packed argument table. Nil values in the middle of the argument list are preserved.

### Settings Lookup

`api.GetSettings(addonId)` now returns `{}` when `addonId` is not a string. String ids are still sanitized before comparing against loaded addon ids.

### Logging

`api.Log:Info(message)` and `api.Log:Err(message)` now tolerate nil and non-string inputs. Tables are serialized, and other values are converted with `tostring`.

`api.Log:WriteEventParameters(event, ...)` now preserves nil argument positions when logging event payloads.

### File Serialization

`api.File:Write(path, tbl)` now uses safer table serialization for mixed table keys and rejects recursive tables instead of writing invalid Lua.

`api.File:Read(path)` and `api.File:Write(path, tbl)` now reject non-string paths.

### Unit Guarding

Existing guarded unit wrappers now avoid calling the underlying client unit API with nil ids:

- `api.Unit:GetUnitInfoById(id)` returns nil for nil/disallowed ids.
- `api.Unit:UnitWorldPosition(unit)` returns nil when the resolved id is nil/disallowed.
- `api.Unit:GetUnitScreenNameTagOffset(unit)` returns nil when the resolved id is nil/disallowed.
- `api.Ability:GetUnitClassName(unit)` returns nil when the resolved id is nil/disallowed.

These are crash/log-spam guards on already exposed calls, not expanded visibility or discovery behavior.

### Equipment

`api.Equipment:GetEquippedItemTooltipText(unit, slotIdx)` now forwards the provided `unit` argument instead of forcing the player unit.

`api.Equipment:GetEquippedSkillsetLunagems(unit)` now skips missing, unnamed, or malformed socket item info before checking item names.

### Item Enchant

`api.ItemEnchant:GetRatioInfos()` and `api.ItemEnchant:GetTargetItemInfo()` now use `X2ItemEnchant`, matching the other item-enchant wrappers.

### Options

`api.Option:SetCustomCloneModelCountSetting(value)` now coerces input with `tonumber(value) or 1` before clamping to the supported `1..5` range.

Boolean-like option setters now coerce numeric strings such as `"0"` and `"1"` before mapping values to `0` or `1`.

### Sandbox

The sandboxed global `CreateItemIconButton` now remains patched and returns an addon-patched widget.

Sandbox proxy no-argument function calls now use `table.unpack` consistently when returning multiple values.

Sandbox `require(name)` now rejects non-string, parent-directory, drive-qualified, and absolute paths. Modules that return nil are cached as `true`, matching standard Lua `require` behavior.

Addon call-stack checks normalize path case and separators before detecting calls from the user addon directory.

## Validation

The patched Lua sources parse with Lua 5.1 syntax checks.

In-game validation confirmed.

Packed SHA256 values:

- `/master/game/scriptsbin/x2ui/addons/api.alb`: `7afd0e490eebb32387f275a2a56905c5989fc4fee63b1edaca21eb0881970fcd`
- `/master/game/scriptsbin/x2ui/addons/sandbox.alb`: `85749e97c75c893ff717ca8d6d2ff4c7eb1c9006aa0ff337b333068cb516479d`
- `/master/game/scriptsbin/x2ui/addons/addons.alb`: `49a106dd298c4a7a122ef043e9e9430530a295410a12d3a346ad9a6a0b4b2d9e`
