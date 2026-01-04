--[[
	作者:白狼
	2025 12 29
--]]

-- ==============================================================
-- 修改 VMLegs.PlayAnim 以方便捕获其生命周期
-- 使用延迟注入来兼容其他开发者对其的修改
-- ==============================================================
concommand.Add('upext_vmlegs_inject', function()
	if not VMLegs then
		print('[UPExt]: can not find VMLegs')
		return
	end

	VMLegs.OriginalPlayAnim = isfunction(VMLegs.OriginalPlayAnim) and VMLegs.OriginalPlayAnim or VMLegs.PlayAnim
	VMLegs.PlayAnim = function(self, anim, ...)
		-- 原版返回值只有 false 和 nil, 无法判断是否成功
		-- 我也不知道他这么设计有什么意义, 所以我不确定的修改是否会引起其他问题

		local succ = self:OriginalPlayAnim(anim, ...)
		if succ == false then return succ end

		-- 项目快了结了, 稳一点吧
		succ = not LocalPlayer():ShouldDrawLocalPlayer() 
			and IsValid(self.LegModel)
			and IsValid(self.LegParent)
		
		if succ then 
			self.Duration = self.LegParent:SequenceDuration(self.SeqID)
			hook.Run('VMLegsPostPlayAnim', anim) 
		end

		return succ
	end

	print('[UPExt]: VMLegs.PlayAnim already injected')
end)

concommand.Add('upext_vmlegs_recovery', function()
	if not VMLegs then
		print('[UPExt]: can not find VMLegs')
		return
	end

	VMLegs.PlayAnim = isfunction(VMLegs.OriginalPlayAnim) and VMLegs.OriginalPlayAnim or VMLegs.PlayAnim
	print('[UPExt]: VMLegs.PlayAnim already recovered')
end)


hook.Add('KeyPress', 'UPExtVMLegsInject', function()
	hook.Remove('KeyPress', 'UPExtVMLegsInject')
	timer.Simple(3, function() RunConsoleCommand('upext_vmlegs_inject') end)
end)

-- ==============================================================
-- 菜单
-- ==============================================================
UPar.SeqHookAdd('UParExtendMenu', 'VMLegsInject', function(panel)
	panel:Help('·························· VMLegs ··························')
	panel:ControlHelp('#upext.vmlegs_inject.help')
	panel:Button('#upext.vmlegs_inject', 'upext_vmlegs_inject')
	panel:Button('#upext.vmlegs_recovery', 'upext_vmlegs_recovery')
end, 3)