# State Bag System

## Overview

pma-voice uses FiveM's **state bags** as the primary mechanism for synchronizing player voice data across server and clients. State bags are key-value stores attached to players that are automatically replicated to all connected clients. Any script (server or client) can read them, and the owning side can write them.

---

## Player State Bags

All state bags are attached to the player entity (`Player(source).state` server-side, `LocalPlayer.state` client-side).

### Initialization

On player join, `handleStateBagInitilization(source)` in `server/main.lua` sets the initial values:

```lua
plyState:set('radio',         voice_defaultRadioVolume, true)  -- broadcast
plyState:set('call',          voice_defaultCallVolume,  true)
plyState:set('submix',        nil,                      true)
plyState:set('proximity',     {},                       true)
plyState:set('callChannel',   0,                        true)
plyState:set('radioChannel',  0,                        true)
plyState:set('voiceIntent',   'speech',                 true)
plyState:set('pmaVoiceInit',  true,                     false) -- not broadcast
plyState:set('assignedChannel', channel,                true)
```

`pmaVoiceInit` is set with `broadcast = false` so it is only readable server-side and doesn't consume network bandwidth. It guards against re-initializing when the resource restarts while a player is connected.

---

## State Bag Reference

| State Bag | Written by | Read by | Type | Description |
|-----------|-----------|---------|------|-------------|
| `assignedChannel` | Server | Client | `number` | The mumble channel number assigned to this player. Used by the client to join the correct channel. |
| `proximity` | Client | All | `table` | `{ index: number, distance: number, mode: string }` — current voice mode. |
| `radioChannel` | Server | All | `number` | Current radio channel. `0` = not on radio. |
| `callChannel` | Server | All | `number` | Current call channel. `0` = not on a call. |
| `radio` | Server (init) / Client (volume) | All | `number` | Radio volume (1–100). |
| `call` | Server (init) / Client (volume) | All | `number` | Call volume (1–100). |
| `submix` | Server (external) | Client | `string\|nil` | Named audio submix to apply to this player. Handled by `client/init/submix.lua`. |
| `voiceIntent` | Client | Server/All | `string` | `'speech'` or `'music'` — affects noise suppression and filtering. |
| `micMuted` | Client | All | `boolean` | `true` when the player has toggled self transmit mute (`NetworkSetVoiceActive`). |
| `disableRadio` | Client | All | `number` | Bitfield of radio disable reasons. `0` = enabled. See [Radio System](radio-system.md). |
| `radioActive` | Client | All | `boolean` | `true` while the player is transmitting on radio. |
| `muted` | Server (mute.js) | All | `boolean` | `true` when an admin has muted the player. |
| `isDead` | External (optional) | Client (radio.lua) | `boolean` | If set to `true` by a death resource, prevents radio transmission. |
| `disableProximity` | External (optional) | Client (proximity.lua) | `boolean` | If `true`, skips adding nearby players to voice targets. |
| `pmaVoiceInit` | Server | Server | `boolean` | Internal guard preventing double-initialization. Not broadcast. |

---

## Writing State Bags

### Server-side

```lua
Player(source).state:set('radioChannel', channel, true)
--                                                ^^^^ broadcast to all clients
```

Third argument `true` = replicate to all clients. `false` = server-only.

### Client-side

```lua
LocalPlayer.state:set('proximity', {
    index = mode,
    distance = distance,
    mode = modeName,
}, true)
```

---

## Reading State Bags

### From Lua (any side)

```lua
-- Server
local channel = Player(source).state.radioChannel

-- Client
local channel = LocalPlayer.state.radioChannel

-- Client reading another player's bag
local channel = Player(serverId).state.radioChannel
```

### From JavaScript (server)

```js
Player(source).state.radioChannel
```

---

## State Bag Change Handlers

pma-voice uses `AddStateBagChangeHandler` in `client/init/submix.lua` to react to submix changes:

```lua
AddStateBagChangeHandler("submix", "", function(bagName, _, value)
    local tgtId = tonumber(bagName:gsub('player:', ''), 10)
    -- apply or remove submix effect for this player
end)
```

The `""` second argument matches all player bags. The `bagName` format is `"player:<serverId>"`.

---

## `proximity` State Bag

The proximity state bag is how third-party resources read the player's current voice range:

```lua
-- Server
local prox = Player(source).state.proximity
-- prox.index    = 1..6  (mode index)
-- prox.distance = stored Mumble talker proximity (see shared.lua / proximity docs)
-- prox.mode     = e.g. "5 m"
```

Updated client-side by `setProximityState` whenever the player cycles modes or an override is applied.

---

## `disableRadio` Bitfield

The radio disable state is a bitfield so multiple independent systems can disable radio simultaneously:

```lua
-- In any client script:
local DEAD_BIT = 1
exports['pma-voice']:addRadioDisableBit(DEAD_BIT)    -- dead, can't use radio
exports['pma-voice']:removeRadioDisableBit(DEAD_BIT) -- alive, remove the block
```

Radio is active only when ALL bits are cleared (`disableRadio == 0`).

---

## Rebuilding This System

1. On player join server-side, initialize all voice-related state bags with `broadcast = true`.
2. Use state bags instead of net events where multiple clients need to observe the same value.
3. Implement a `pmaVoiceInit` guard (non-broadcast) to prevent double-initialization on resource restart.
4. Use a bitfield for composite boolean states (like radio disable) so multiple resources can set their own bit without conflicting.
5. Use `AddStateBagChangeHandler` on the client for reactive updates instead of polling.
6. Assign unique mumble channels per player via `assignedChannel` so the client always knows where to connect.
