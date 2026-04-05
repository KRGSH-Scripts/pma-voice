-- Transmit-only mute: never call NetworkSetVoiceActive(false) — it kills receive. Keep voice active and use
-- MumbleSetTalkerProximity(0). addNearbyPlayers uses LocalPlayer.state.proximity.distance for who you hear.
micMuted = false

function applyMicMuteState()
	NetworkSetVoiceActive(true)
	if micMuted then
		MumbleSetTalkerProximity(0.0)
	else
		local p = LocalPlayer.state.proximity
		local dist = (type(p) == 'table' and type(p.distance) == 'number') and p.distance or Cfg.voiceModes[mode][1]
		MumbleSetTalkerProximity(dist + 0.0)
	end
	LocalPlayer.state:set('micMuted', micMuted, true)
	sendUIMessage({
		micMuted = micMuted
	})
	if MumbleIsConnected() and isInitialized then
		addNearbyPlayers()
	end
end

-- Other scripts or the game can bump talker proximity or flip voice active; re-assert while muted.
CreateThread(function()
	while true do
		Wait(200)
		if not micMuted or not MumbleIsConnected() or not isInitialized then goto skip end
		NetworkSetVoiceActive(true)
		if MumbleGetTalkerProximity() > 0.01 then
			MumbleSetTalkerProximity(0.0)
		end
		::skip::
	end
end)

---@param muted boolean
function setPlayerMicMuted(muted)
	type_check({ muted, "boolean" })
	if micMuted == muted then return end
	micMuted = muted
	applyMicMuteState()
end

exports('setPlayerMicMuted', setPlayerMicMuted)
exports('isPlayerMicMuted', function()
	return micMuted
end)

local function toggleMicMuteCommand()
	if GetConvarInt('voice_enableMicMute', 1) ~= 1 then return end
	setPlayerMicMuted(not micMuted)
end

RegisterCommand('togglemicmute', toggleMicMuteCommand, false)

if shouldRegisterFiveMKeyMappings() then
	RegisterKeyMapping('togglemicmute', 'Toggle Microphone Mute', 'keyboard',
		GetConvar('voice_defaultMicMuteKey', 'M'))
end

if gameVersion == 'redm' then
	local KEY_M = 0x4D

	local function on_mic_mute_up() end

	RegisterRawKeymap("pma-voice_micMuteToggle", on_mic_mute_up, function()
		ExecuteCommand('togglemicmute')
	end, KEY_M, true)
end
