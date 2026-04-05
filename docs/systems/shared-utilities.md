# Shared Utilities

## Overview

`shared.lua` is the single file loaded on both client and server (via `shared_script 'shared.lua'` in `fxmanifest.lua`). It provides global utilities, type-safe validation, the logger, and platform-specific native polyfills.

**File:** `shared.lua`

---

## Global State

```lua
Cfg = {}          -- Configuration table, populated with voiceModes
voiceTarget = 1   -- The mumble voice target index used by the client
gameVersion = GetGameName()  -- "fivem" or "redm"
```

On the client, `playerServerId` is also set here:
```lua
playerServerId = GetPlayerServerId(PlayerId())
```

---

## Voice Modes

`Cfg.voiceModes` is built at startup from six nominal ranges (1, 3, 5, 10, 25, 50 m). Display names are `"1 m"`, `"3 m"`, etc.

- **Without native audio:** stored distance equals the nominal meters (GTA units ≈ meters).
- **With native audio:** stored distance is `meters / 3` so that the client-side proximity check (`hear distance ≈ stored × 3`) matches the nominal meters.

Each entry is `{ distance, display_name }`. The `mode` variable (1-indexed) selects the active entry.

---

## Logger

A shared `logger` object with four log levels:

```lua
logger = {
    log     = function(msg, ...)  -- always prints
    info    = function(msg, ...)  -- prints when voice_debugMode >= 1
    warn    = function(msg, ...)  -- always prints with [^1WARNING^7] prefix
    error   = function(msg, ...)  -- calls error() (throws)
    verbose = function(msg, ...)  -- prints when voice_debugMode >= 4
}
```

All methods accept `string.format`-style arguments (`message:format(...)`).

| Level | When visible | Use case |
|-------|-------------|----------|
| `log` | Always | Startup messages, connection events |
| `info` | `voice_debugMode >= 1` | Channel joins, state changes |
| `warn` | Always | Misconfiguration, non-fatal issues |
| `error` | Always (throws) | Programming errors, invalid arguments |
| `verbose` | `voice_debugMode >= 4` | Per-tick trace logging, target changes |

---

## `tPrint(tbl, indent)`

Recursive table pretty-printer for debug logging:

```lua
tPrint(radioData)
-- radioData: 
--   12: false
--   34: true
```

Used by the radio module when `voice_debugMode >= 4`.

---

## `type_check(...)`

Type-safe argument validation. Accepts variadic tables of `{ value, expectedType, ... }`:

```lua
type_check({ channel, "number" }, { name, "string" })
```

Each argument is a table where:
- Index 1 is the value to check.
- Indices 2+ are accepted type strings (for union types like `"number|string"`).

If the type doesn't match, it calls `error()` with a message identifying the argument index:

```
Invalid type sent to argument #1, expected number, got string
```

This is used consistently across all exports and internal functions to fail loudly rather than silently misbehaving.

---

## RedM Native Polyfills

When `gameVersion == "redm"` (and on the client), pma-voice polyfills the submix natives that are not exposed in RedM's Lua layer:

```lua
function CreateAudioSubmix(name)
    return Citizen.InvokeNative(0x658d2bc8, name, Citizen.ResultAsInteger())
end

function AddAudioSubmixOutput(submixId, outputSubmixId)
    Citizen.InvokeNative(0xAC6E290D, submixId, outputSubmixId)
end

function MumbleSetSubmixForServerId(serverId, submixId)
    Citizen.InvokeNative(0xFE3A3054, serverId, submixId)
end

function SetAudioSubmixEffectParamFloat(submixId, effectSlot, paramIndex, paramValue)
    Citizen.InvokeNative(0x9A209B3C, ...)
end

function SetAudioSubmixEffectParamInt(submixId, effectSlot, paramIndex, paramValue)
    Citizen.InvokeNative(0x77FAE2B8, ...)
end

function SetAudioSubmixEffectRadioFx(submixId, effectSlot)
    Citizen.InvokeNative(0xAAA94D53, submixId, effectSlot)
end

function SetAudioSubmixOutputVolumes(submixId, outputSlot, ...)
    Citizen.InvokeNative(0x825DC0D1, ...)
end
```

These are only defined when `not IsDuplicityVersion()` (client-side) and `gameVersion == "redm"`. On FiveM they are native Lua globals.

---

## Dummy Lint Stubs

To satisfy Lua LSP linters without runtime errors, `shared.lua` has:

```lua
if not IsDuplicityVersion() then
    LocalPlayer = LocalPlayer
    playerServerId = GetPlayerServerId(PlayerId())
    ...
end
Player = Player
Entity = Entity
```

These are no-ops at runtime but inform the linter that these globals exist.

---

## Rebuilding This System

1. Use a single `shared.lua` loaded on both sides to avoid duplicating constants and utilities.
2. Implement a structured logger with debug levels controlled by a ConVar.
3. Implement a `type_check` helper for all export entry points — export APIs are the boundary between your code and third parties.
4. When supporting multiple game engines (FiveM vs RedM), polyfill missing natives in the shared file conditioned on `GetGameName()`.
5. Put voice mode configuration in `Cfg` so it is accessible to both client and server without duplication.
