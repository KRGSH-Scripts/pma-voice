-- Mutes your own voice transmission (proximity and radio). Uses NetworkSetVoiceActive; do not fight this from other resources.
micMuted = false

--- After re-enabling transmit, FiveM/Mumble can take several seconds to resume routing unless we re-assert channel and targets.
local function bumpVoiceRoutingAfterUnmute()
	if not MumbleIsConnected() or not isInitialized then return end
	CreateThread(function()
		local voiceModeData = Cfg.voiceModes[mode]
		MumbleSetTalkerProximity(voiceModeData[1] + 0.0)
		local target = MumbleGetVoiceChannelFromServerId(playerServerId)
		if target == -1 then
			target = LocalPlayer.state.assignedChannel
		end
		if type(target) == 'number' and target > 0 then
			MumbleSetVoiceChannel(target)
			for _ = 1, 100 do
				if MumbleGetVoiceChannelFromServerId(playerServerId) == target then break end
				Wait(0)
				MumbleSetVoiceChannel(target)
			end
		end
		addNearbyPlayers()
	end)
end

function applyMicMuteState()
	NetworkSetVoiceActive(not micMuted)
	LocalPlayer.state:set('micMuted', micMuted, true)
	sendUIMessage({
		micMuted = micMuted
	})
	if not micMuted then
		bumpVoiceRoutingAfterUnmute()
	end
end

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
