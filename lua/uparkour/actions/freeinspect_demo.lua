if not GetConVar('developer') or not GetConVar('developer'):GetBool() then return end

local freeinspect_demo = UPAction:Register('freeinspect_demo', {
	AAAACreat = '白狼',
	AAADesc = '#freeinspect_demo.desc',
	icon = 'upgui/uparkour.jpg',
	label = '#freeinspect_demo',
	defaultDisabled = false
})

if SERVER then return end

UPKeyboard.Register('freeinspect_demo', '[]')

UPar.SeqHookAdd('UParKeyPress', 'freeinspect_demo', function(eventflags)
	if eventflags['freeinspect_demo'] then
		eventflags['freeinspect_demo'] = UPKeyboard.KEY_EVENT_FLAGS.HANDLED
		UPar.CallPlyUsingEff('freeinspect_demo', 'Start', LocalPlayer())
	end
end)