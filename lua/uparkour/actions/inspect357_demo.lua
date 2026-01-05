local inspect357_demo = UPAction:Register('inspect357_demo', {
	AAAACreat = '白狼',
	AAADesc = '#inspect357_demo.desc',
	icon = 'upgui/uparkour.jpg',
	label = '#inspect357_demo',
	defaultDisabled = false
})

if SERVER then return end

UPKeyboard.Register('inspect357_demo', '[]')

UPar.SeqHookAdd('UParKeyPress', 'upctrl', function(eventflags)
	if eventflags['inspect357_demo'] then
		eventflags['inspect357_demo'] = UPKeyboard.KEY_EVENT_FLAGS.HANDLED
		UPar.CallPlyUsingEff('inspect357_demo', 'Start', LocalPlayer())
	end
end)