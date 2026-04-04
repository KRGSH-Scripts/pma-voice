# Configuration System

## Overview

pma-voice is configured entirely through FiveM **ConVars** (server-side configuration variables). There is no config file. ConVars are set in `server.cfg` and are either replicated to clients (`setr`) or server-only (`set`).

All ConVars are declared in `fxmanifest.lua` under `convar_category 'PMA-Voice'`, which makes them visible in the FiveM ConVar UI.

---

## Setting ConVars

```
# In server.cfg
setr voice_useNativeAudio true
setr voice_defaultVoiceMode 2
setr voice_enableRadios 1
```

- Use `setr` for values that clients need to read.
- Values read at startup are cached; some changes require a resource restart.
- **Do not set a ConVar if you want the default value** — defaults are built-in.

---

## Audio Engine Options

These are mutually exclusive. Only enable one:

| ConVar | Type | Default | Description |
|--------|------|---------|-------------|
| `voice_useNativeAudio` | bool | `false` | Uses the game's native 3D audio engine. Adds reverb, echo, distance attenuation. **Required for submixs.** Voice mode distances are divided by 3 when this is active. |
| `voice_use2dAudio` | bool | `false` | Flat volume regardless of distance until out of range. |
| `voice_use3dAudio` | bool | `false` | Standard 3D positional audio without the extra native effects. |

If none of these are set, the server automatically enables `voice_useNativeAudio` (handled in `server/main.lua`).

### Sending Range

| ConVar | Type | Default | Description |
|--------|------|---------|-------------|
| `voice_useSendingRangeOnly` | bool | `false` | Clients only hear players within their configured send/hear range. Prevents external mumble connections from being audible to everyone. Recommended. |

---

## General Voice Settings

| ConVar | Type | Default | Description |
|--------|------|---------|-------------|
| `voice_enableUi` | int | `1` | Enables the built-in HUD overlay. |
| `voice_enableProximityCycle` | int | `1` | Allows players to cycle proximity with the configured key. `0` locks players to `voice_defaultVoiceMode`. |
| `voice_defaultCycle` | string | `"F11"` | Key binding for proximity cycling. See [FiveM key IDs](https://docs.fivem.net/docs/game-references/input-mapper-parameter-ids/keyboard/). |
| `voice_defaultVoiceMode` | int | `2` | Starting voice mode index on join. `1` = Whisper, `2` = Normal, `3` = Shouting. |
| `voice_defaultRadioVolume` | int | `30` | Default radio volume (1–100). Must be an integer, not a float. New joins only. |
| `voice_defaultCallVolume` | int | `60` | Default call volume (1–100). New joins only. |
| `voice_refreshRate` | int | `200` | Milliseconds between each proximity update tick. |

---

## Radio & Call

| ConVar | Type | Default | Description |
|--------|------|---------|-------------|
| `voice_enableRadios` | int | `1` | Enables the entire radio subsystem. |
| `voice_enableCalls` | int | `1` | Enables the entire call subsystem. |
| `voice_enableSubmix` | int | `1` | Applies the audio submix effect to radio/call. Requires `voice_useNativeAudio`. |
| `voice_enableRadioAnim` | int | `0` (fxmanifest) / `1` (README) | Plays the shoulder-mic grab animation while transmitting. |
| `voice_defaultRadio` | string | `"LMENU"` | Key binding for the radio PTT key. |

> **Note:** `voice_enableRadioAnim` defaults differ between the README (1) and the fxmanifest (0). The fxmanifest value is authoritative.

---

## External Mumble Server

| ConVar | Type | Default | Description |
|--------|------|---------|-------------|
| `voice_externalAddress` | string | `""` | Address of an external mumble server. When set, clients connect here instead of the local FXServer. |
| `voice_externalPort` | int | `0` | Port for the external mumble server. |
| `voice_externalDisallowJoin` | int | `0` | Prevents players from connecting to the server at all. Intended for FXServer instances used solely as external mumble hosts. |
| `voice_hideEndpoints` | int | `1` | Hides the mumble server address in client logs. Useful when using a private external server. |

The client polls these values every 500ms and reconnects if they change at runtime:

```lua
CreateThread(function()
    while true do
        Wait(500)
        if GetConvar('voice_externalAddress', '') ~= externalAddress or
           GetConvarInt('voice_externalPort', 0) ~= externalPort then
            externalAddress = ...
            MumbleSetServerAddress(externalAddress, externalPort)
        end
    end
end)
```

---

## Miscellaneous

| ConVar | Type | Default | Description |
|--------|------|---------|-------------|
| `voice_allowSetIntent` | int | `1` | Allows players to use `/setvoiceintent` to switch between `speech` and `music` audio processing modes. |
| `voice_debugMode` | int | `0` | `1` = basic logs, `4` = verbose logs. Used by the shared `logger` object. |
| `voice_syncPlayerNames` | int | `0` | When enabled, syncs player names with radio member tables. |
| `voice_disableVehicleRadioAnim` | int | `0` | Disables the radio animation while in a vehicle. |
| `voice_disableAutomaticListenerOnCamera` | int | `0` | Prevents the spectator listener from activating when a rendering camera is active. |
| `voice_onClickVolume` | int | `10` | Volume of the mic-click-on sound (1–100). |
| `voice_offClickVolume` | int | `3` | Volume of the mic-click-off sound (1–100). |

---

## Volume ConVar Notes

`voice_defaultRadioVolume` and `voice_defaultCallVolume` must be set as integers in the range 2–100. Setting `0` or `1` is detected by the server as a misconfigured float cast and automatically reset to defaults (30 and 60 respectively), with a repeated warning for 25 seconds:

```lua
if radioVolume == 0 or radioVolume == 1 or callVolume == 0 or callVolume == 1 then
    SetConvarReplicated("voice_defaultRadioVolume", 30)
    ...
end
```

---

## Ace Permissions

```
# Allow a group to use /muteply
add_ace group.superadmin command.muteply allow
```

---

## Rebuilding This System

1. Declare all ConVars in `fxmanifest.lua` under `convar_category` for discoverability in the FiveM UI.
2. Read ConVars with `GetConvar` (string), `GetConvarInt` (integer), or compare against `'true'/'false'` for booleans.
3. Do not cache ConVars that need live updates — poll them in a thread (e.g., external server address).
4. Provide sane defaults inside every `GetConvar` call so the resource works without any configuration.
5. Detect common misconfiguration (e.g., float values where integers are expected) and auto-correct with warnings.
