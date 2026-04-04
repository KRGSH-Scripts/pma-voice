# Proximity System

## Overview

The Proximity System manages how players hear each other based on spatial distance. It is the core voice routing mechanism of pma-voice, handling channel assignment, nearby player detection, talking-mode cycling, and spectator/listener overrides.

**Files:**
- `client/init/proximity.lua` — Core proximity loop, channel management, spectator mode
- `client/commands.lua` — `cycleproximity` command, `setProximityState`, proximity overrides

---

## How It Works

### Voice Channels

FiveM's mumble server uses numeric channels to route audio. Each player is assigned a unique **assigned channel** by the server on join (`handleStateBagInitilization` in `server/main.lua`). The channel pool goes up to 2048; the first free slot is allocated per player.

On the client, voice is routed via a **voice target** (`voiceTarget = 1`). The target defines which channels the local player's microphone transmits to.

### Initialization Flow

1. `mumbleConnected` fires when the client connects to the mumble server.
2. `handleInitialState()` is called:
   - Sets talker proximity (`MumbleSetTalkerProximity`) to the current voice mode distance.
   - Clears and sets the voice target (`MumbleClearVoiceTarget`, `MumbleSetVoiceTarget`).
   - Sets the voice channel to `LocalPlayer.state.assignedChannel`.
   - Waits until the channel assignment is confirmed via polling.
   - Adds the assigned channel to the voice target.
   - Calls `addNearbyPlayers()` to populate initial targets.
3. `isInitialized` is set to `true`, allowing the main loop to proceed.

### Main Loop (`CreateThread` in proximity.lua)

Runs every `voice_refreshRate` ms (default 200ms):
1. Waits until `MumbleIsConnected()` and `isInitialized` are both true.
2. If UI is enabled, sends current talking status and radio status to the NUI.
3. If `voiceState == "proximity"`:
   - Calls `addNearbyPlayers()` to rebuild voice targets.
   - Checks spectator/camera mode and toggles listener mode accordingly.
   - Retries failed channel listeners via `tryListeningToFailedListeners()`.

### `addNearbyPlayers()`

1. Updates `plyCoords` (local player position) and `proximity` (current mumble proximity).
2. Clears all voice target channels (`MumbleClearVoiceTargetChannels`).
3. Re-adds the player's own assigned channel as both a listen channel and voice target.
4. Iterates all active call participants and adds their channels.
5. Iterates all active players:
   - Calls `addProximityCheck(ply)` which returns `(shouldAdd, distance)`.
   - If `shouldAdd`, retrieves the player's mumble channel via `MumbleGetVoiceChannelFromServerId` and adds it to the voice target.

---

## Proximity Modes (Voice Modes)

Voice modes are defined in `shared.lua` under `Cfg.voiceModes`:

| Mode    | Standard Distance | Native Audio Distance |
|---------|------------------|-----------------------|
| Whisper | 3.0 GTA units    | 1.5 GTA units         |
| Normal  | 7.0 GTA units    | 3.0 GTA units         |
| Shout   | 15.0 GTA units   | 6.0 GTA units         |

Native audio distances are smaller because the engine's 3D audio applies additional attenuation.

### Cycling Proximity

The `cycleproximity` command (default key: `F11`) increments `mode` through the voice modes table and calls `setProximityState(distance, false)`:
- Updates `MumbleSetTalkerProximity`.
- Updates `LocalPlayer.state.proximity` state bag with `{ index, distance, mode }`.
- Sends `voiceMode` to the NUI for display.
- Fires `pma-voice:setTalkingMode` event with the new mode index.

Can be disabled via `voice_enableProximityCycle 0` or programmatically via `setAllowProximityCycleState(false)`.

---

## Exports

| Export | Side | Description |
|--------|------|-------------|
| `overrideProximityCheck(fn)` | Client | Replace the default distance check with a custom function `fn(ply) → (bool, distance)` |
| `resetProximityCheck()` | Client | Restore the default proximity check |
| `setListenerOverride(enabled)` | Client | Force spectator/listener mode on/off |
| `overrideProximityRange(range, disableCycle)` | Client | Lock proximity to a fixed range |
| `clearProximityOverride()` | Client | Restore the mode-based proximity range |
| `setAllowProximityCycleState(state)` | Client | Enable/disable the F11 proximity cycling key |
| `addVoiceMode(distance, name)` | Client | Add a new voice mode to the cycle |
| `removeVoiceMode(name)` | Client | Remove a named voice mode from the cycle |
| `setVoiceState(state, channel)` | Client | Switch between `"proximity"` and `"channel"` routing modes |

---

## Voice States

The system supports two voice states controlled via `setVoiceState`:

- **`"proximity"`** — Default. Nearby players are detected geometrically and added each tick.
- **`"channel"`** — Static channel mode. The player is placed on a fixed mumble channel (`channel + 65535` to avoid overlap with player-assigned channels). The proximity loop stops adding nearby players.

---

## Spectator / Listener Mode

When `NetworkIsInSpectatorMode()` returns true or `GetRenderingCam()` is active, the system activates `setSpectatorMode(true)`:
- Iterates all active players and calls `addChannelListener(serverId)` on each.
- `addChannelListener` calls `MumbleAddVoiceChannelListen(channel)` so the local player hears all channels without transmitting.

When spectator mode ends, `removeChannelListener` is called for all players and the `listeners` table is cleared.

Failed listeners (where the mumble channel was `-1` at the time of registration) are retried each tick via `tryListeningToFailedListeners()`.

---

## Proximity Check Customization

The default `orig_addProximityCheck` calculates Euclidean distance from local player coords to the target ped. Returns `true` if within `proximity` (scaled ×3 for native audio).

Third-party resources can inject a custom check via `overrideProximityCheck(fn)`. The override is automatically reset if the providing resource stops (`onClientResourceStop` handler).

---

## Rebuilding This System

1. Assign each player a unique numeric mumble channel on join (server side, pool of ~2048).
2. On client connect, set the voice channel and talker proximity, then start a polling loop.
3. Each tick: clear target channels, re-add own channel, add call channels, iterate nearby players by distance and add their channels.
4. Expose a way to cycle through preconfigured distance presets, writing to a state bag for cross-resource access.
5. Support spectator mode by listening to all channels passively.
6. Allow proximity check overrides for custom game logic (e.g. walls, interiors).
