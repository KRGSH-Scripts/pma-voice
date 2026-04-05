local wasProximityDisabledFromOverride = false
disableProximityCycle = false
RegisterCommand('setvoiceintent', function(source, args)
	if GetConvarInt('voice_allowSetIntent', 1) == 1 then
		local intent = args[1]
		if intent == 'speech' then
			MumbleSetAudioInputIntent(`speech`)
		elseif intent == 'music' then
			MumbleSetAudioInputIntent(`music`)
		end
		LocalPlayer.state:set('voiceIntent', intent, true)
	end
end)
TriggerEvent('chat:addSuggestion', '/setvoiceintent', 'Sets the players voice intent', {
	{
		name = "intent",
		help = "speech is default and enables noise suppression & high pass filter, music disables both of these."
	},
})

-- TODO: Better implementation of this?
RegisterCommand('vol', function(_, args)
	if not args[1] then return end
	setVolume(tonumber(args[1]))
end)
TriggerEvent('chat:addSuggestion', '/vol', 'Sets the radio/phone volume', {
	{ name = "volume", help = "A range between 1-100 on how loud you want them to be" },
})

exports('setAllowProximityCycleState', function(state)
	type_check({ state, "boolean" })
	disableProximityCycle = state
end)

function setProximityState(proximityRange, isCustom)
	local voiceModeData = Cfg.voiceModes[mode]
	local txRange = micMuted and (MIC_MUTE_TX_PROXIMITY + 0.0) or (proximityRange + 0.0)
	MumbleSetTalkerProximity(txRange)
	LocalPlayer.state:set('proximity', {
		index = mode,
		distance = proximityRange,
		mode = isCustom and "Custom" or voiceModeData[2],
	}, true)
	sendUIMessage({
		-- JS expects this value to be - 1, "custom" voice is on the last index
		voiceMode = isCustom and #Cfg.voiceModes or mode - 1
	})
end

exports("overrideProximityRange", function(range, disableCycle)
	type_check({ range, "number" })
	setProximityState(range, true)
	if disableCycle then
		disableProximityCycle = true
		wasProximityDisabledFromOverride = true
	end
end)

exports("clearProximityOverride", function()
	local voiceModeData = Cfg.voiceModes[mode]
	setProximityState(voiceModeData[1], false)
	if wasProximityDisabledFromOverride then
		disableProximityCycle = false
	end
end)

-- Hot pink #FF69B4 — flat ring on ground while cycling voice range (MarkerTypeHorizontalCircleSkinny).
local RING_R, RING_G, RING_B = 255, 105, 180
local proximityRingPreviewGen = 0

local function startProximityCycleRingPreview(rangeMeters)
	proximityRingPreviewGen = proximityRingPreviewGen + 1
	local myGen = proximityRingPreviewGen
	local durationMs = 2000
	local endAt = GetGameTimer() + durationMs
	local diameter = rangeMeters * 2.0
	CreateThread(function()
		while GetGameTimer() < endAt and myGen == proximityRingPreviewGen do
			local ped = PlayerPedId()
			local c = GetEntityCoords(ped)
			local z = c.z - 0.98
			DrawMarker(
				25,
				c.x, c.y, z,
				0.0, 0.0, 0.0,
				0.0, 0.0, 0.0,
				diameter, diameter, 0.35,
				RING_R, RING_G, RING_B, 175,
				false, false, 2, false, nil, nil, false
			)
			Wait(0)
		end
	end)
end

RegisterCommand('cycleproximity', function()
	-- Proximity is either disabled, or manually overwritten.
	if GetConvarInt('voice_enableProximityCycle', 1) ~= 1 or disableProximityCycle then return end
	local newMode = mode + 1

	-- If we're within the range of our voice modes, allow the increase, otherwise reset to the first state
	if newMode <= #Cfg.voiceModes then
		mode = newMode
	else
		mode = 1
	end

	local range = Cfg.voiceModes[mode][1]
	setProximityState(range, false)
	startProximityCycleRingPreview(range)
	TriggerEvent('pma-voice:setTalkingMode', mode)
end, false)
if shouldRegisterFiveMKeyMappings() then
	RegisterKeyMapping('cycleproximity', 'Cycle Proximity', 'keyboard', GetConvar('voice_defaultCycle', 'F11'))
end
