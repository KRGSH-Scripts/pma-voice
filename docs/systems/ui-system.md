# UI / HUD System

## Overview

The UI System is a Vue 3 NUI (FiveM's in-game browser overlay) that displays the player's current voice state in the bottom-right corner of the screen. It communicates with the Lua client via `SendNUIMessage` / `window.addEventListener('message')` and signals readiness via a NUI callback.

**Files:**
- `voice-ui/src/App.vue` — Single-file Vue component (template + logic + styles)
- `voice-ui/src/main.js` — Vue app entry point
- `client/utils/Nui.lua` — Lua-side NUI messaging with initialization gate
- `ui/index.html` — Built output served as the `ui_page`
- `ui/js/app.js`, `ui/js/chunk-vendors.js` — Compiled Vue bundles
- `ui/css/app.css` — Compiled styles
- `ui/mic_click_on.ogg`, `ui/mic_click_off.ogg` — Mic click audio files

---

## HUD Display

The UI shows up to three lines in the bottom-right corner:

| Condition | Line shown |
|-----------|------------|
| Player is in a call | `[Call]` (turns white when talking) |
| Radio enabled + on a channel | `<channel> Mhz [Radio]` (turns white when transmitting) |
| Voice modes available | `<distance> [Range]` (turns white when talking) |

Text is normally grey (`rgb(148, 150, 151)`) with a black outline, and turns white (`rgba(255,255,255,0.822)`) via the `.talking` CSS class.

The entire HUD is hidden when `voice.uiEnabled` is `false`.

---

## NUI Initialization Gate (`client/utils/Nui.lua`)

```lua
local uiReady = promise.new()

function sendUIMessage(message)
    Citizen.Await(uiReady)
    SendNUIMessage(message)
end

RegisterNUICallback("uiReady", function(data, cb)
    uiReady:resolve(true)
    cb('ok')
end)
```

On Vue mount, `App.vue` POSTs to `https://<resourceName>/uiReady`, which resolves the promise. All `sendUIMessage` calls will then proceed. This prevents race conditions where Lua tries to send UI state before the browser frame is ready.

---

## Message Protocol

Messages are JSON objects sent from Lua via `SendNUIMessage`. The Vue component handles each key independently:

| Key | Type | Description |
|-----|------|-------------|
| `uiEnabled` | boolean | Show/hide the entire HUD |
| `voiceModes` | string (JSON) | JSON array of `[[distance, name], ...]` — all available voice modes |
| `voiceMode` | number | Index into `voiceModes` for the currently active mode |
| `radioChannel` | number | Current radio channel (0 = none) |
| `radioEnabled` | boolean | Whether radio is enabled for this player |
| `callInfo` | number | Current call channel (0 = none) |
| `usingRadio` | boolean | Whether the player is currently transmitting on radio |
| `talking` | boolean | Whether the player is currently talking (proximity) |
| `micMuted` | boolean | Self transmit mute active; UI shows “Mic muted” next to range |
| `sound` | string | `"audio_on"` or `"audio_off"` — triggers mic click sound |
| `volume` | number | Volume fraction for the mic click sound (0.0–1.0) |

### Mic Click Sounds

When a `sound` message arrives and the player is on a radio channel with radio enabled:
```js
let click = document.getElementById(data.sound); // <audio id="audio_on"> or <audio id="audio_off">
click.load();
click.volume = data.volume;
click.play().catch(e => {});
```

The `.catch` discards `AbortError` from overlapping play calls.

### Voice Mode "Custom" Entry

On initial load, after receiving `voiceModes`, the component appends a synthetic entry:
```js
voiceModes.push([0.0, "Custom"])
```

This is the last entry in the array, so `voiceMode` being set to `voiceModes.length - 1` (i.e. `#Cfg.voiceModes` from Lua) selects it.

---

## Talking State Logic

```js
if ((data.talking !== undefined) && !voice.usingRadio) {
    voice.talking = data.talking;
}
```

When the player is using the radio (`usingRadio == true`), incoming `talking` updates are ignored to prevent the proximity talking indicator from flickering during radio transmission.

---

## Build System

The UI is built with Vue CLI (`voice-ui/`):

| File | Purpose |
|------|---------|
| `vue.config.js` | Vue CLI config (output dir likely `../ui`) |
| `babel.config.js` | Babel transpile config |
| `package.json` | Dependencies: Vue 3, Vue CLI |
| `pnpm-lock.yaml` | Lockfile |

To rebuild:
```sh
cd voice-ui
pnpm install
pnpm build
```

Output goes to `ui/` and is served by FiveM as defined in `fxmanifest.lua`:
```lua
files { 'ui/*.ogg', 'ui/css/*.css', 'ui/js/*.js', 'ui/index.html' }
ui_page 'ui/index.html'
```

---

## Rebuilding This System

1. Create a Vue 3 single-file component with `reactive()` state for all voice properties.
2. Use `window.addEventListener('message', ...)` to receive updates from Lua.
3. POST to the resource's NUI callback endpoint on mount to signal readiness.
4. In Lua, create a `promise` that resolves on the NUI callback, and gate all `SendNUIMessage` calls on it.
5. Embed two `<audio>` elements for mic click sounds and trigger them via messages.
6. Use CSS classes (`.talking`) rather than inline styles to indicate active voice states.
7. Build with Vue CLI and declare the output files in `fxmanifest.lua` under `files` and `ui_page`.
