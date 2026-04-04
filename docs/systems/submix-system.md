# Submix / Audio Effects System

## Overview

The Submix System applies real-time audio effects to radio and phone call audio streams. It uses FiveM's `CreateAudioSubmix` API to create named audio processing pipelines that are applied per-player via the mumble server's submix routing.

**Files:**
- `client/init/main.lua` — Submix creation, volume management, `toggleVoice`, `resyncVolume`
- `client/init/submix.lua` — State bag handler for server-assigned submixes

---

## How Submixes Work

A **submix** in FiveM is a named audio processing chain. When `MumbleSetSubmixForServerId(serverId, submixId)` is called, all audio from that player is routed through the specified chain before reaching the listener's speakers.

pma-voice creates two default submixes at startup:

### Radio Submix

```lua
local radioEffectId = CreateAudioSubmix('Radio')
SetAudioSubmixEffectRadioFx(radioEffectId, 0)
SetAudioSubmixEffectParamInt(radioEffectId, 0, GetHashKey('default'), 1)
SetAudioSubmixOutputVolumes(radioEffectId, 0,
    1.0,   -- frontLeft
    0.25,  -- frontRight
    0.0,   -- rearLeft
    0.0,   -- rearRight
    1.0,   -- channel5
    1.0    -- channel6
)
AddAudioSubmixOutput(radioEffectId, 0)
```

- Applies the game's built-in radio FX (bandwidth limiting, distortion).
- Pans predominantly to the front-left speaker for realism.
- Output slot `0` routes to the default output chain.

### Call Submix

```lua
local callEffectId = CreateAudioSubmix('Call')
SetAudioSubmixOutputVolumes(callEffectId, 1,
    0.10,  -- frontLeft
    0.50,  -- frontRight
    0.0,   -- rearLeft
    0.0,   -- rearRight
    1.0,   -- channel5
    1.0    -- channel6
)
AddAudioSubmixOutput(callEffectId, 1)
```

- No special radio FX, giving a cleaner phone-call sound.
- Pans to front-right at reduced volume to simulate a phone at the ear.
- Output slot `1`.

### Submix Index Table

Both submixes are stored in `submixIndicies`:

```lua
submixIndicies = {
    radio = radioEffectId,
    call  = callEffectId,
    -- custom entries added via registerCustomSubmix or setEffectSubmix
}
```

---

## Applying Submixes

### `toggleVoice(plySource, enabled, moduleType)`

Called whenever a player starts or stops talking on radio/call:

1. If `mutedPlayers[plySource]` is set, returns immediately.
2. **Enable path** (`enabled == true`):
   - Checks if the player is outside proximity range (`currentTargets[plySource] > 4.0` or not in table).
   - Sets volume override: `MumbleSetVolumeOverrideByServerId(plySource, volumes[moduleType])`.
   - If `voice_enableSubmix` is on:
     - Sets `disableSubmixReset[plySource] = true` (prevents premature reset race condition).
     - Calls `MumbleSetSubmixForServerId(plySource, submixIndicies[moduleType])`.
3. **Disable path** (`enabled == false`):
   - Clears `disableSubmixReset[plySource]`.
   - After 250ms timeout, if `disableSubmixReset[plySource]` is still nil, calls `restoreDefaultSubmix(plySource)`.
   - Resets volume: `MumbleSetVolumeOverrideByServerId(plySource, -1.0)` (-1.0 = default volume).

The 250ms delay on disable prevents the submix from being reset if the player immediately starts talking again (race condition guard).

### `restoreDefaultSubmix(plySource)`

Reads `Player(plySource).state.submix`. If it's set and valid in `submixIndicies`, re-applies that submix. Otherwise calls `MumbleSetSubmixForServerId(plySource, -1)` to remove any active effect.

---

## State Bag Handler (`client/init/submix.lua`)

Listens to changes on the `submix` state bag of any player:

```lua
AddStateBagChangeHandler("submix", "", function(bagName, _, value)
    local tgtId = tonumber(bagName:gsub('player:', ''), 10)
    ...
end)
```

- If `value` is set: applies the corresponding submix from `submixIndicies`.
- If `value` is nil/removed: only resets submix if the player is not currently on radio or call (avoids interrupting active voice effects).
- On player disconnect: same nil-reset logic.

This allows server resources to persistently assign audio effects to specific players (e.g., radio equipment items).

---

## Volume Management

Volumes are stored as fractions (0.0–1.0) in `volumes`:

```lua
volumes = {
    radio    = voice_defaultRadioVolume / 100,   -- default 0.30
    call     = voice_defaultCallVolume  / 100,   -- default 0.60
    click_on = voice_onClickVolume      / 100,   -- default 0.10
    click_off= voice_offClickVolume     / 100,   -- default 0.03
}
```

### `setVolume(volume, volumeType)`

- Converts 1–100 integer to a 0.0–1.0 fraction.
- If `volumeType` is specified: updates only that entry, sets state bag, calls `resyncVolume`.
- If `volumeType` is nil: updates all entries.

### `resyncVolume(volumeType, newVolume)`

Iterates `radioData` or `callData` and updates `MumbleSetVolumeOverrideByServerId` for all active players.

---

## Custom Submix API

### `registerCustomSubmix(callback)`

External resources register a submix created elsewhere:

```lua
exports['pma-voice']:registerCustomSubmix(function()
    local mySubmix = CreateAudioSubmix('MyEffect')
    -- configure...
    return { 'myEffectName', mySubmix }
end)
```

Fires `pma-voice:registerCustomSubmixes` locally before checking exports, so resources can register on that event.

### `setEffectSubmix(type, effectId)`

Replaces the submix ID for `'radio'` or `'call'` with a custom effect:

```lua
exports['pma-voice']:setEffectSubmix('radio', myCustomRadioEffectId)
```

---

## RedM Compatibility

Because RedM does not natively expose these functions, `shared.lua` polyfills them using `Citizen.InvokeNative` with the correct native hashes:

- `CreateAudioSubmix` → `0x658d2bc8`
- `AddAudioSubmixOutput` → `0xAC6E290D`
- `MumbleSetSubmixForServerId` → `0xFE3A3054`
- `SetAudioSubmixEffectParamFloat` → `0x9A209B3C`
- `SetAudioSubmixEffectParamInt` → `0x77FAE2B8`
- `SetAudioSubmixEffectRadioFx` → `0xAAA94D53`
- `SetAudioSubmixOutputVolumes` → `0x825DC0D1`

---

## Rebuilding This System

1. Create named submix effect chains at resource startup using `CreateAudioSubmix`.
2. Configure the radio chain with `SetAudioSubmixEffectRadioFx` + `SetAudioSubmixEffectParamInt`.
3. Configure output volumes to route audio to the appropriate speakers.
4. When a player starts talking on radio/call, call `MumbleSetSubmixForServerId` + `MumbleSetVolumeOverrideByServerId`.
5. When they stop, delay the submix reset slightly (250ms) to prevent race conditions with rapid re-transmissions.
6. Expose `registerCustomSubmix` and `setEffectSubmix` for third-party audio effect integration.
7. Use a state bag (`submix`) to persist assigned effects server-side, synced to all clients.
