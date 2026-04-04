# Radio System

## Overview

The Radio System allows players to communicate across any distance using a designated radio channel number. Players on the same channel hear each other regardless of physical proximity. It is split across client and server modules.

**Files:**
- `client/module/radio.lua` — Client-side radio state, transmit commands, sync handlers
- `server/module/radio.lua` — Server-side channel management, talking sync, channel access control

---

## Architecture

```
Player presses +radiotalk
    └─> TriggerServerEvent('pma-voice:setTalkingOnRadio', true)
            └─> Server iterates radioData[channel]
                    └─> TriggerClientEvent('pma-voice:setTalkingOnRadio', allOtherPlayers, source, true)
                            └─> Client toggleVoice(source, true, 'radio') → MumbleSetVolumeOverrideByServerId
```

---

## Server Side (`server/module/radio.lua`)

### Data Structures

- `radioData[channel][source] = talking` — Maps channel numbers to a table of player sources and their current talking state.
- `voiceData[source].radio` — Tracks which radio channel each player is on (stored in the global `voiceData` table from `server/main.lua`).

### Channel Join (`addPlayerToRadio`)

1. Runs `canJoinChannel(source, radioChannel)` — checks `radioChecks[channel]` if a check function is registered.
2. If rejected, fires `pma-voice:radioChangeRejected` and `pma-voice:removePlayerFromRadio` to the requesting client.
3. Notifies all existing channel members with `pma-voice:addPlayerToRadio`.
4. Syncs the full channel member table to the joining player with `pma-voice:syncRadioData`.
5. Sets `Player(source).state.radioChannel` to the new channel.

### Channel Leave (`removePlayerFromRadio`)

1. Notifies all channel members with `pma-voice:removePlayerFromRadio`.
2. Removes the player from `radioData[channel]`.
3. Sets `voiceData[source].radio = 0`.

### Talking Sync (`setTalkingOnRadio`)

1. Updates `radioData[channel][source] = talking`.
2. Sends `pma-voice:setTalkingOnRadio` to every other member of the channel.

### Channel Access Control (`addChannelCheck`)

Third-party resources can register a callback per channel:

```lua
exports['pma-voice']:addChannelCheck(channelNumber, function(source)
    return true -- or false to deny
end)
```

The callback is cleaned up automatically when the providing resource stops (`onResourceStop` handler).

### Radio Name Override (`overrideRadioNameGetter`)

By default, player names are sourced from `GetPlayerName(source)`. Resources can override this:

```lua
exports['pma-voice']:overrideRadioNameGetter(nil, function(source)
    return MyFramework.GetPlayerName(source)
end)
```

---

## Client Side (`client/module/radio.lua`)

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `radioChannel` | number | Current radio channel (0 = none) |
| `radioData` | table | `{ [serverId] = talking }` for channel members |
| `radioEnabled` | boolean | Whether the player can use radio |
| `radioPressed` | boolean | Whether `+radiotalk` is currently held |
| `disableRadioAnim` | boolean | Whether the shoulder-mic animation is suppressed |

### Transmitting (`+radiotalk` / `-radiotalk`)

`+radiotalk` (default key: Left Alt on FiveM):
1. Guards: radios must be enabled, player must not be dead, radio must not be disabled.
2. Sets `radioPressed = true`, notifies server, plays mic-click ON sound.
3. Calls `addVoiceTargets(radioData, callData)` — adds all channel members and active call participants as mumble voice targets.
4. Starts an animation thread (if `voice_enableRadioAnim` is enabled and not in a vehicle) playing the `random@arrests::generic_radio_enter` animation.
5. Continuously holds `SetControlNormal(_, 249, 1.0)` to suppress the PTT key until released.
6. Fires `pma-voice:radioActive, true` locally and sets `LocalPlayer.state.radioActive = true`.

`-radiotalk`:
1. Sets `radioPressed = false`.
2. Clears voice target players, re-adds only call targets.
3. Fires `pma-voice:radioActive, false` and updates state bag.
4. Plays mic-click OFF sound.
5. Stops the radio animation task.
6. Notifies server via `pma-voice:setTalkingOnRadio, false`.

### Receiving Transmissions

`pma-voice:setTalkingOnRadio(plySource, enabled)`:
- Updates `radioData[plySource]`.
- Calls `toggleVoice(plySource, enabled, 'radio')` which:
  - Sets `MumbleSetVolumeOverrideByServerId` to the radio volume fraction.
  - Applies the radio submix effect (`MumbleSetSubmixForServerId`).
- Plays a mic-click sound.

### Radio Disable Bits

The `LocalPlayer.state.disableRadio` state bag is a **bitfield** controlling why radio is disabled:

```lua
-- DisabledRadioStates
Enabled          = 0   -- no bits set, radio works
IsDead           = 1
IsCuffed         = 2
IsPdCuffed       = 4
IsUnderWater     = 8
DoesntHaveItem   = 16
PlayerDisabledRadio = 32
```

Bits are combined with bitwise OR. Radio fires only when `disableRadio == 0`. Third-party resources can manage these bits via:

```lua
exports['pma-voice']:addRadioDisableBit(bit)
exports['pma-voice']:removeRadioDisableBit(bit)
```

---

## Exports

### Client

| Export | Description | Parameters |
|--------|-------------|------------|
| `setRadioChannel(channel)` | Join or leave a radio channel | `number` |
| `addPlayerToRadio(channel)` | Alias for `setRadioChannel` | `number` |
| `removePlayerFromRadio()` | Leave current radio channel | — |
| `toggleRadioAnim()` | Toggle the shoulder-mic animation | — |
| `setDisableRadioAnim(bool)` | Directly set animation disable state | `boolean` |
| `getRadioAnimState()` | Returns current animation disable state | → `boolean` |
| `setRadioTalkAnim(dict, anim)` | Override the talk animation | `string, string` |
| `addRadioDisableBit(bit)` | Add a disable reason bit | `number` |
| `removeRadioDisableBit(bit)` | Remove a disable reason bit | `number` |
| `setRadioVolume(vol)` | Set radio volume (1–100) | `number` |
| `getRadioVolume()` | Get current radio volume | → `number` |

### Server

| Export | Description | Parameters |
|--------|-------------|------------|
| `setPlayerRadio(source, channel)` | Set a player's radio channel | `number, number` |
| `addChannelCheck(channel, cb)` | Register a join-gate callback | `number, function` |
| `overrideRadioNameGetter(_, cb)` | Override how names are retrieved | `function` |
| `getPlayersInRadioChannel(channel)` | Return `{ [source] = talking }` for a channel | `number` |

---

## Net Events

| Event | Direction | Description |
|-------|-----------|-------------|
| `pma-voice:setPlayerRadio` | Client → Server | Request to join a channel |
| `pma-voice:setTalkingOnRadio` | Client → Server | Report start/stop transmitting |
| `pma-voice:syncRadioData` | Server → Client | Full channel member table sync |
| `pma-voice:addPlayerToRadio` | Server → Client | A new player joined the channel |
| `pma-voice:removePlayerFromRadio` | Server → Client | A player left the channel |
| `pma-voice:setTalkingOnRadio` | Server → Client | A channel member started/stopped transmitting |
| `pma-voice:radioChangeRejected` | Server → Client | Channel join was denied |
| `pma-voice:clSetPlayerRadio` | Server → Client | Server-authoritative channel override |
| `pma-voice:radioActive` | Client (local event) | Fired when radio PTT is pressed/released |

---

## Rebuilding This System

1. Maintain a server-side `radioData[channel][source]` map.
2. On channel join: notify all existing members, sync the member list to the joiner, set a state bag.
3. On transmit start: update the server map and fan-out a "talking" event to all other channel members.
4. On the client: on "talking" event, call the mumble volume override API to route audio, then apply a radio submix effect.
5. For PTT: use `RegisterCommand('+cmd'/-cmd')` with `RegisterKeyMapping` for customizable key bindings.
6. Use a bitfield state bag (`disableRadio`) to allow multiple independent systems to disable the radio without stepping on each other.
