# Call / Phone System

## Overview

The Call System enables private, bidirectional voice communication between players on the same call channel, simulating phone calls. Like the Radio System it operates independently of spatial proximity, but is always-on (no PTT key — both parties always hear each other while in the same call channel).

**Files:**
- `client/module/phone.lua` — Client-side call data sync and channel management
- `server/module/phone.lua` — Server-side call channel management

---

## Architecture

```
External resource sets call channel (server export or client export)
    └─> setPlayerCall(source, channel)           [server/module/phone.lua]
            ├─> addPlayerToCall(source, channel)
            │       ├─> TriggerClientEvent('pma-voice:addPlayerToCall', existingMembers, source)
            │       └─> TriggerClientEvent('pma-voice:syncCallData', source, callData[channel])
            └─> Player(source).state.callChannel = channel
```

---

## Server Side (`server/module/phone.lua`)

### Data Structures

- `callData[channel][source] = true` — Maps call channels to connected player sources.
- `voiceData[source].call` — Tracks which call channel a player is on.

### Adding to Call (`addPlayerToCall`)

1. Creates `callData[channel]` if it doesn't exist.
2. Notifies all **existing** members of the channel with `pma-voice:addPlayerToCall` so they can start hearing the joiner.
3. Inserts the joining player into `callData[channel]`.
4. Syncs the full member table to the joiner via `pma-voice:syncCallData`.
5. Updates `voiceData[source].call = channel`.

### Removing from Call (`removePlayerFromCall`)

1. Notifies all channel members with `pma-voice:removePlayerFromCall`.
2. Removes the player from `callData[channel]`.
3. Sets `voiceData[source].call = 0`.

### Setting Call Channel (`setPlayerCall`)

- If `callChannel != 0` and player has no active call: calls `addPlayerToCall`.
- If `callChannel == 0`: calls `removePlayerFromCall` with the current call.
- If `callChannel != 0` and player already in a call: removes from old call, then adds to new call.
- Always updates `Player(source).state.callChannel`.
- If called from an external resource (via export), also notifies the client with `pma-voice:clSetPlayerCall`.

---

## Client Side (`client/module/phone.lua`)

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `callChannel` | number | Current call channel (0 = none) |
| `callData` | table | `{ [serverId] = true }` for active call members |

### Receiving Call Events

`pma-voice:syncCallData(callTable, channel)`:
- Replaces `callData` with the received table.
- Calls `handleRadioAndCallInit()` (from `client/init/main.lua`) to re-apply voice volume overrides for all call participants.

`pma-voice:addPlayerToCall(plySource)`:
- Calls `toggleVoice(plySource, true, 'call')` — sets volume override + call submix.
- Adds the player to `callData`.

`pma-voice:removePlayerFromCall(plySource)`:
- **If removing self**: clears all call voice overrides, empties `callData`, clears voice targets, re-adds radio targets if active.
- **If removing other**: removes them from `callData`, toggles their voice back to radio state (or off), updates targets if currently transmitting.

### Setting Call Channel (`setCallChannel`)

1. Guards against `voice_enableCalls 0`.
2. Triggers `pma-voice:setPlayerCall` on the server.
3. Stores `callChannel` locally.
4. Sends `callInfo = channel` to the NUI (shows `[Call]` indicator when non-zero).

---

## Key Difference from Radio

| Aspect | Radio | Call |
|--------|-------|------|
| PTT key | Yes (held key) | No (always active) |
| Talking sync | Per-transmission event | Sync on join only |
| Member talking state | `radioData[src] = talking` | `callData[src] = true` |
| Submix effect | Radio FX (bandwidth-limited) | Call FX (phone-like EQ) |
| Disable bits | `disableRadio` bitfield | Not applicable |

---

## Exports

### Client

| Export | Description | Parameters |
|--------|-------------|------------|
| `setCallChannel(channel)` | Join or leave a call channel | `number` |
| `addPlayerToCall(channel)` | Alias for `setCallChannel` | `number` |
| `removePlayerFromCall()` | Leave current call (set channel to 0) | — |
| `setCallVolume(vol)` | Set call volume (1–100) | `number` |
| `getCallVolume()` | Get current call volume | → `number` |
| `SetCallChannel(channel)` | mumble-voip compatibility alias | `number` |

### Server

| Export | Description | Parameters |
|--------|-------------|------------|
| `setPlayerCall(source, channel)` | Set a player's call channel | `number, number` |

---

## Net Events

| Event | Direction | Description |
|-------|-----------|-------------|
| `pma-voice:setPlayerCall` | Client → Server | Request to join a call channel |
| `pma-voice:syncCallData` | Server → Client | Full call member table on join |
| `pma-voice:addPlayerToCall` | Server → Client | Another player joined the active call |
| `pma-voice:removePlayerFromCall` | Server → Client | A player (or self) left the call |
| `pma-voice:clSetPlayerCall` | Server → Client | Server-authoritative channel override |

---

## Rebuilding This System

1. Server maintains `callData[channel][source]` with boolean values.
2. On join: notify existing members, sync full table to joiner, update state bag.
3. On leave: notify all members, clean up data structures.
4. Client has no PTT — just applies persistent volume overrides for all call participants using the mumble volume override API.
5. Integrate with the Submix System to apply a telephone-effect audio filter to call audio.
6. When removing self from a call, explicitly re-evaluate radio targets so radio audio isn't disrupted.
