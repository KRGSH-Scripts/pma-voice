isInitialized = false

local function applyTalkerProximityAndResetVoiceTarget()
	local voiceModeData = Cfg.voiceModes[mode]
	MumbleSetTalkerProximity(micMuted and (MIC_MUTE_TX_PROXIMITY + 0.0) or (voiceModeData[1] + 0.0))
	MumbleClearVoiceTarget(voiceTarget)
	MumbleSetVoiceTarget(voiceTarget)
end

--- Re-applies channel + voice target when local mumble channel drifted from server-assigned channel
--- (symptom: you still hear others, but they no longer hear you). Also restores radio/call player targets.
---@param reason string|nil
function repairAssignedVoiceChannel(reason)
	local assigned = LocalPlayer.state.assignedChannel
	if type(assigned) ~= 'number' or assigned == 0 then return end

	local current = MumbleGetVoiceChannelFromServerId(playerServerId)
	if current == assigned then return end

	logger.warn('Voice channel desync detected%s: expected %s, got %s. Re-syncing.',
		reason and (' (' .. reason .. ')') or '', assigned, current)

	applyTalkerProximityAndResetVoiceTarget()
	MumbleSetVoiceChannel(assigned)

	local deadline = GetGameTimer() + 10000
	while MumbleGetVoiceChannelFromServerId(playerServerId) ~= assigned do
		if GetGameTimer() > deadline then
			logger.warn('Voice channel re-sync timed out (target channel %s)', assigned)
			addNearbyPlayers()
			addVoiceTargets((radioPressed and isRadioEnabled()) and radioData or {}, callData)
			return
		end
		Wait(100)
		MumbleSetVoiceChannel(assigned)
	end

	MumbleAddVoiceTargetChannel(voiceTarget, assigned)
	addNearbyPlayers()
	addVoiceTargets((radioPressed and isRadioEnabled()) and radioData or {}, callData)
end

function handleInitialState()
	applyTalkerProximityAndResetVoiceTarget()
	MumbleSetVoiceChannel(LocalPlayer.state.assignedChannel)

	while MumbleGetVoiceChannelFromServerId(playerServerId) ~= LocalPlayer.state.assignedChannel do
		Wait(100)
		MumbleSetVoiceChannel(LocalPlayer.state.assignedChannel)
	end

	isInitialized = true

	local assigned = LocalPlayer.state.assignedChannel
	MumbleAddVoiceTargetChannel(voiceTarget, assigned)

	addNearbyPlayers()
end

AddEventHandler('mumbleConnected', function(address, isReconnecting)
	logger.info('Connected to mumble server with address of %s, is this a reconnect %s',
		GetConvarInt('voice_hideEndpoints', 1) == 1 and 'HIDDEN' or address, isReconnecting)

	logger.log('Connecting to mumble, setting targets.')
	-- don't try to set channel instantly, we're still getting data.
	local voiceModeData = Cfg.voiceModes[mode]
	LocalPlayer.state:set('proximity', {
		index = mode,
		distance = voiceModeData[1],
		mode = voiceModeData[2],
	}, true)

	handleInitialState()

	applyMicMuteState()

	logger.log('Finished connection logic')
end)

AddEventHandler('mumbleDisconnected', function(address)
	isInitialized = false
	logger.info('Disconnected from mumble server with address of %s',
		GetConvarInt('voice_hideEndpoints', 1) == 1 and 'HIDDEN' or address)
end)

-- TODO: Convert the last Cfg to a Convar, while still keeping it simple.
AddEventHandler('pma-voice:settingsCallback', function(cb)
	cb(Cfg)
end)
