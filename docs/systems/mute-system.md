# Mute System

## Overview

The Mute System provides these levels of muting:

1. **Self mic mute (transmit)** — The local player toggles their own microphone output via `/togglemicmute` or the configured key (`voice_defaultMicMuteKey`). Implemented in `client/mic_mute.lua` using `NetworkSetVoiceActive`; also blocks radio transmit while muted. State is exposed as `LocalPlayer.state.micMuted` and reapplied on `mumbleConnected`.
2. **Server-side staff mute** — Administrators silence a player globally via the `/muteply` command. Implemented in JavaScript to leverage `clearTimeout`.
3. **Client-side local mute** — Individual players can locally silence specific players without server involvement.

**Files:**
- `client/mic_mute.lua` — Self transmit mute (`NetworkSetVoiceActive`), key/command, state bag `micMuted`
- `server/mute.js` — Server command handler, timeout-based unmute, state bag sync
- `client/init/main.lua` — `mutedPlayers` table, `toggleMutePlayer`, `toggleVoice` guard

---

## Server-Side Mute (`server/mute.js`)

### Command: `/muteply <playerId> [duration]`

- Protected with ace: resources must grant `command.muteply` to the relevant group.
- `duration` defaults to 900 seconds (15 minutes).

### Logic

```js
RegisterCommand('muteply', (source, args) => {
    const mutePly = parseInt(args[0])
    const duration = parseInt(args[1]) || 900

    if (mutePly && exports[GetCurrentResourceName()].isValidPlayer(mutePly)) {
        const isMuted = !MumbleIsPlayerMuted(mutePly);
        Player(mutePly).state.muted = isMuted;
        MumbleSetPlayerMuted(mutePly, isMuted);
        emit('pma-voice:playerMuted', mutePly, source, isMuted, duration);

        if (mutedPlayers[mutePly]) {
            // Already muted — toggle off and cancel the existing timeout
            clearTimeout(mutedPlayers[mutePly]);
            MumbleSetPlayerMuted(mutePly, isMuted)
            Player(mutePly).state.muted = isMuted;
            return;
        }

        mutedPlayers[mutePly] = setTimeout(() => {
            MumbleSetPlayerMuted(mutePly, !isMuted)
            Player(mutePly).state.muted = !isMuted;
            delete mutedPlayers[mutePly]
        }, duration * 1000)
    }
}, true)
```

**Why JavaScript?** Lua's `SetTimeout` cannot be cancelled. JavaScript's `clearTimeout` allows re-running the command to unmute a player immediately, cancelling the pending auto-unmute.

### State Bag `muted`

`Player(mutePly).state.muted = isMuted` broadcasts the muted state to all clients and other server scripts as a readable state bag entry.

### Event `pma-voice:playerMuted`

Emitted server-side with `(playerId, adminSource, isMuted, duration)` — allows external logging or notification systems to respond.

---

## Client-Side Local Mute (`client/init/main.lua`)

### `mutedPlayers` table

A client-local table `{ [serverId] = true }` storing players silenced by the local user. This is **not** synced to other clients — it only affects what the local player hears.

### `toggleMutePlayer(source)`

```lua
function toggleMutePlayer(source)
    if mutedPlayers[source] then
        mutedPlayers[source] = nil
        MumbleSetVolumeOverrideByServerId(source, -1.0)  -- restore
    else
        mutedPlayers[source] = true
        MumbleSetVolumeOverrideByServerId(source, 0.0)   -- silence
    end
end
exports('toggleMutePlayer', toggleMutePlayer)
```

Uses `MumbleSetVolumeOverrideByServerId(source, 0.0)` to set volume to zero rather than using any mute API, so it works independently of the server state.

### Guard in `toggleVoice`

```lua
function toggleVoice(plySource, enabled, moduleType)
    if mutedPlayers[plySource] then return end
    ...
end
```

If a player is locally muted, all radio/call volume override logic is skipped for them — they remain at 0.0 even when they start transmitting on radio or joining a call.

---

## Exports

| Export | Side | Description | Parameters |
|--------|------|-------------|------------|
| `setPlayerMicMuted(muted)` | Client | Set self transmit mute (`NetworkSetVoiceActive`) | `boolean` |
| `isPlayerMicMuted()` | Client | Returns `true` if self mic is muted | → `boolean` |
| `toggleMutePlayer(source)` | Client | Toggle local mute for a player | `number` |
| `isPlayerMuted(source)` | Client | Returns `true` if locally muted | `number` → `boolean` |
| `getMutedPlayers()` | Client | Returns the full `mutedPlayers` table | → `table` |

---

## Ace Permission

To allow staff to use `/muteply`:

```
add_ace group.admin command.muteply allow
```

Replace `group.admin` with the appropriate ACE group. Without this, the command is server-only (accessible only by the console).

---

## Chat Suggestion

The system registers a `/muteply` suggestion in chat automatically:

```lua
TriggerEvent('chat:addSuggestion', '/muteply', 'Mutes the player with the specified id', {
    { name = "player id", help = "the player to toggle mute" },
    { name = "duration",  help = "(opt) the duration the mute in seconds (default: 900)" }
})
```

---

## Rebuilding This System

1. Implement the admin mute command in JavaScript (not Lua) to use `setTimeout`/`clearTimeout` for timed auto-unmute.
2. Use `MumbleSetPlayerMuted` for server-authoritative muting (all clients hear silence).
3. Write a `muted` state bag entry so external resources and clients can react.
4. On the client, maintain a local `mutedPlayers` table and use `MumbleSetVolumeOverrideByServerId(id, 0.0)` for player-initiated local mutes.
5. Guard all voice activation paths against locally muted players.
6. Expose `toggleMutePlayer`, `isPlayerMuted`, and `getMutedPlayers` exports for third-party integration.
