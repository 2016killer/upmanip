--[[
	作者:白狼
	2025 1 1

	假的 GmodLegs3 
	放弃将它作为工具的想法, 随便写吧...
--]]

-- ==============================================================
-- 骨骼代理, 使用静态偏移
-- ==============================================================
local zerovec = Vector(0, 0, 0)
local zeroang = Angle(0, 0, 0)
local diagonalvec = Vector(1, 1, 1)
local unitMat = Matrix()
local emptyTable = {}

g_ProxyLikeGmodLegs3 = {}
g_ProxyLikeGmodLegs3.UsedBones = {
	'ValveBiped.Bip01_Pelvis',
	'ValveBiped.Bip01_Spine',
	'ValveBiped.Bip01_Spine1',
	'ValveBiped.Bip01_Spine2',

	'ValveBiped.Bip01_L_Thigh',
	'ValveBiped.Bip01_L_Calf',
	'ValveBiped.Bip01_L_Foot',
	'ValveBiped.Bip01_L_Toe0',

	'ValveBiped.Bip01_R_Thigh',
	'ValveBiped.Bip01_R_Calf',
	'ValveBiped.Bip01_R_Foot',
	'ValveBiped.Bip01_R_Toe0'
}

function g_ProxyLikeGmodLegs3:GetMatrix(ent, boneName, mode)
	return UPManip.Extend.GetMatrix(ent, boneName, mode)
end

function g_ProxyLikeGmodLegs3:GetParentMatrix(ent, boneName, mode)
	-- 父级设为单位矩阵, 这让
	if boneName == 'SELF' then
		return unitMat
	else
		return UPManip.Extend.GetParentMatrix(ent, boneName, mode)
	end
end
-- ==============================================================
-- 骨骼代理, 使用静态偏移
-- ==============================================================

if g_ManipLegs and isentity(g_ManipLegs.LegEnt) and IsValid(g_ManipLegs.LegEnt) then
	g_ManipLegs.LegEnt:Remove()
	local succ, msg = pcall(g_ManipLegs.UnRegisterVMLegsListener, g_ManipLegs)
	if not succ then print('[UPExt]: LegsManip: UnRegister failed: ' .. msg) end
end
g_ManipLegs = {}



local ManipLegs = g_ManipLegs

ManipLegs.ForwardOffset = -22

ManipLegs.BonesToRemove = {
	['ValveBiped.Bip01_Head1'] = true,
	['ValveBiped.Bip01_L_Hand'] = true,
	['ValveBiped.Bip01_L_Forearm'] = true,
	['ValveBiped.Bip01_L_Upperarm'] = {
		Vector(0, 0, -20)
	},
	['ValveBiped.Bip01_L_Clavicle'] = true,
	['ValveBiped.Bip01_R_Hand'] = true,
	['ValveBiped.Bip01_R_Forearm'] = true,
	['ValveBiped.Bip01_R_Upperarm'] = {
		Vector(0, 0, 20)
	},
	['ValveBiped.Bip01_R_Clavicle'] = true,
	['ValveBiped.Bip01_Spine4'] = true,
}


-- ==============================================================
-- 帧循环钩子：添加
-- 自定义钩子名：UPExtLegsManipFrameContextStart（上下文起始）、UPExtLegsManipFrameContextEnd（上下文结束）
-- ==============================================================
ManipLegs.FRAME_LOOP_HOOK = {
	{
		EVENT_NAME = 'PostDrawOpaqueRenderables',
		IDENTITY = 'LegsManipView',
		CALL = function(self, ...)
			if not IsValid(LocalPlayer()) then
				return
			end

			-- 1. 上下文起始钩子检查：返回true则直接睡眠
			local frameStartSleep = hook.Run('UPExtLegsManipFrameContextStart', self) or false
			if frameStartSleep then
				self:Sleep()
				return
			end

			-- 原有帧循环逻辑
			self:UpdatePosition()
			self:UpdateAnimation(FrameTime())
			local endFlag = self:RunTimeCondition()
			if endFlag then self:Sleep() end

			-- 2. 上下文结束钩子检查：返回true则直接睡眠
			local frameEndSleep = hook.Run('UPExtLegsManipFrameContextEnd', self) or false
			if frameEndSleep then
				self:Sleep()
				return
			end
		end
	},

	{
		EVENT_NAME = 'ShouldDisableLegs',
		IDENTITY = 'LegsManipCompatGmodLegs3',
		CALL = function(self, ...)
			return true
		end
	}
}

ManipLegs.MagicOffset = Vector(0, 0, 5)
ManipLegs.MagicOffsetZ0 = 
ManipLegs.MagicOffsetZ1 = 
ManipLegs.LerpT = 0
ManipLegs.FadeInSpeed = 10
ManipLegs.FadeOutSpeed = 5
ManipLegs.Snapshot = nil       -- 初始快照（由起始实体生成）
ManipLegs.Target = nil         -- 统一目标实体
ManipLegs.LastTarget = nil     -- 上一帧目标实体（用于检测变化）
ManipLegs.FadeInCycle = 0
ManipLegs.FadeOutCycle = 1

-- 统一辅助钩子标识（方便批量移除，提升可维护性）
ManipLegs.VMLegs_EXTRA_HOOK_ID = 'LegsManipVMLegsExtra'

-- 启动函数：参数保留起始实体（仅用于生成快照），淡入/淡出速度
function ManipLegs:StartLerp(startEnt, fadeInSpeed, fadeOutSpeed)
	self.Snapshot = nil
	if IsValid(startEnt) then
		startEnt:SetupBones()
		local snapshot, runtimeflags = startEnt:UPMaSnapshot(self.BoneIterator)
		self.Snapshot = snapshot
	end

	self.FadeInSpeed = fadeInSpeed and tonumber(fadeInSpeed) or 10
	self.FadeOutSpeed = fadeOutSpeed and tonumber(fadeOutSpeed) or 5
	self.LerpT = 0
	self:Wake()
	hook.Run('UPExtLegsManipStartLerp', self, startEnt)
end

function ManipLegs:UpdateAnimation(dt)
	self:RunTimeTargetEmptyCheck()

	if not self:GetRunState() or not self.Snapshot then
		return
	end

	self.LegEnt:SetupBones()
	local targetValid = isentity(self.Target) and IsValid(self.Target)

	if targetValid then
		self.LerpT = math.Clamp(self.LerpT + self.FadeInSpeed * dt, 0, 1)
		self.Target:SetupBones()

		local lerpSnapshot, runtimeflags = self.LegEnt:UPMaLerpBoneBatch(
			self.LerpT,
			self.Snapshot,
			self.Target,
			self.BoneIterator
		)
		local runtimeflag = self.LegEnt:UPManipBoneBatch(
			lerpSnapshot,
			self.BoneIterator,
			UPManip.MANIP_FLAG.MANIP_POSITION
		)
	else
		self.LerpT = math.Clamp(self.LerpT + self.FadeOutSpeed * dt, 0, 1)
		LocalPlayer():SetupBones()

		local lerpSnapshot, runtimeflags = self.LegEnt:UPMaLerpBoneBatch(
			self.LerpT,
			self.Snapshot,
			LocalPlayer(),
			self.BoneIterator
		)
		local runtimeflag = self.LegEnt:UPManipBoneBatch(
			lerpSnapshot,
			self.BoneIterator,
			UPManip.MANIP_FLAG.MANIP_POSITION
		)
	end
end

function ManipLegs:PushFrameLoop()
	for _, v in ipairs(self.FRAME_LOOP_HOOK) do
		hook.Add(v.EVENT_NAME, v.IDENTITY, function(...)
			local succ, result = pcall(v.CALL, self, ...)
			if not succ then
				hook.Remove(v.EVENT_NAME, v.IDENTITY)
				ErrorNoHaltWithStack(result)
			else
				return result
			end
		end)
	end
	
	return true
end

function ManipLegs:PopFrameLoop()
	for _, v in ipairs(self.FRAME_LOOP_HOOK) do
		hook.Remove(v.EVENT_NAME, v.IDENTITY)
	end

	return true
end

function ManipLegs:Init()
	if not IsValid(LocalPlayer()) then
		return false
	end

	local ply = LocalPlayer()
	local LegEnt = self.LegEnt
	local created = false

	if not IsValid(LegEnt) then
		LegEnt = ClientsideModel(ply:GetLegModel(), RENDER_GROUP_OPAQUE_ENTITY)	
		self.LegEnt = LegEnt
		created = true
	else
		LegEnt:SetModel(ply:GetLegModel())
	end

	LegEnt:SetNoDraw(false)

	for k, v in pairs(ply:GetBodyGroups()) do
		local current = ply:GetBodygroup(v.id)
		LegEnt:SetBodygroup(v.id,  current)
	end

	for k, v in ipairs(LocalPlayer():GetMaterials()) do
		LegEnt:SetSubMaterial(k - 1, LocalPlayer():GetSubMaterial(k - 1))
	end

	LegEnt:SetSkin(LocalPlayer():GetSkin())
	LegEnt:SetMaterial(LocalPlayer():GetMaterial())
	LegEnt:SetColor(LocalPlayer():GetColor())
	LegEnt.GetPlayerColor = function()
		return LocalPlayer():GetPlayerColor()
	end

	if created then
		for i = 0, LegEnt:GetBoneCount() do
			LegEnt:ManipulateBoneAngles(i, zeroang)
			LegEnt:ManipulateBonePosition(i, zerovec)
			LegEnt:ManipulateBoneScale(i, diagonalvec)
		end

		for boneName, v in pairs(self.BonesToRemove) do
			local boneId = LegEnt:LookupBone(boneName)
			if not boneId then 
				continue 
			end
			
			local manipVec, manipAng, manipScale = unpack(istable(v) and v or emptyTable)
			manipVec = isvector(manipVec) and manipVec or zerovec
			manipAng = isangle(manipAng) and manipAng or zeroang
			manipScale = isvector(manipScale) and manipScale or zerovec

			LegEnt:ManipulateBonePosition(boneId, manipVec)
			LegEnt:ManipulateBoneAngles(boneId, manipAng)
			LegEnt:ManipulateBoneScale(boneId, manipScale)
		end
	end

	return true
end

function ManipLegs:Wake()
	local succ = self:Init()
	succ = succ and self:PushFrameLoop()

	if not succ then
		return false
	end

	self.LegEnt:SetParent(LocalPlayer())
	self.LegEnt:SetNoDraw(false)
	self.IsWake = true

	hook.Run('UPExtLegsManipWake', self)

	return true
end

function ManipLegs:Sleep()
	local succ = self:Init()
	succ = succ and self:PopFrameLoop()

	if not succ then
		return false
	end

	self.LegEnt:SetParent(nil)
	self.LegEnt:SetNoDraw(true)
	self.IsWake = false

	hook.Run('UPExtLegsManipSleep', self)

	return true
end

-- 原有RunTimeCondition接口完全保留，不修改！
function ManipLegs:RunTimeCondition()
	local baseEndFlag = self:RunTimeSleep()
	-- Target为LocalPlayer且插值完成则结束
	local isTargetLocal = self.Target == LocalPlayer()
	local lerpDone = self.LerpT >= 1
	local targetLocalDone = isTargetLocal and lerpDone
	-- VMLegs Cycle范围检查
	local cycleValid = true
	if IsValid(VMLegs) and VMLegs.Cycle ~= nil then
		cycleValid = VMLegs.Cycle >= self.FadeInCycle and VMLegs.Cycle <= self.FadeOutCycle
	end
	return baseEndFlag or targetLocalDone or not cycleValid
end

function ManipLegs:RunTimeSleep()
	local hasValidSnapshot = istable(self.Snapshot) and next(self.Snapshot) ~= nil
	local endFlag = not hasValidSnapshot or not IsValid(self.LegEnt) or not IsValid(LocalPlayer())
	endFlag = endFlag or hook.Run('UPExtLegsManipRunTimeSleep', self) or false
	return endFlag
end

-- ==============================================================
-- VMLegs监听器：严格按 {IDENTITY/EVENT_NAME/CALL} 结构，无嵌套钩子注册
-- ==============================================================
ManipLegs.VMLegs_LISTENER = {
	{
		IDENTITY = 'LegsManipTrigger',
		EVENT_NAME = 'UPExtLegsManipVMLegsTrigger', -- 自定义ManipLegs钩子名
		CALL = function(self, anim, ...)
			-- 纯业务逻辑，无钩子注册！清爽干净
			if not IsValid(VMLegs.LegModel) or not IsValid(VMLegs.LegParent) then
				print('[UPExt]: LegsManip: VMLegs has not been started yet!')
				return false
			end

			local animData = VMLegs:GetAnim(anim)
			if not istable(animData) then
				print('[UPExt]: LegsManip: VMLegs has no anim data for anim ' .. anim)
				return false
			end

			VMLegs.LegModel:SetNoDraw(true)

			-- 初始化参数
			self.FadeInSpeed = animData.lerp_speed_in or 10
			self.FadeOutSpeed = animData.lerp_speed_out or 5
			self.FadeInCycle = (animData.startcycle or 0)
			self.FadeOutCycle = (animData.endcycle or 1)

			-- 启动插值+设置Target
			self:StartLerp(self.LegEnt, self.FadeInSpeed, self.FadeOutSpeed)
			self:ChangeTarget(VMLegs.LegParent)

			hook.Run('UPExtLegsManipPostPlayAnim', self, animData)
			return true -- 返回需要的业务结果
		end
	}
}

-- ==============================================================
-- 分割线：统一注册/注销（所有钩子在上层管理，无嵌套，可维护性拉满）
-- ==============================================================
function ManipLegs:RegisterVMLegsListener()
	-- 1. 先注册VMLegs_LISTENER核心钩子（原有逻辑，保留）
	for _, v in ipairs(self.VMLegs_LISTENER) do
		hook.Add(v.EVENT_NAME, v.IDENTITY, function(...)
			return v.CALL(self, ...)
		end)
	end

	-- 2. 上层统一注册辅助钩子（Target变化、RunTimeSleep），无嵌套！
	local extraHookId = self.VMLegs_EXTRA_HOOK_ID

	-- Target变化钩子：失效时fallback到LocalPlayer
	hook.Add('UPExtLegsManipTargetChanged', extraHookId, function(legsManip)
		if not IsValid(VMLegs.LegParent) then
			legsManip:ChangeTarget(LocalPlayer())
		end
	end)

	-- RunTimeSleep钩子：VMLegs失效时触发睡眠
	hook.Add('UPExtLegsManipRunTimeSleep', extraHookId, function(legsManip)
		return not IsValid(VMLegs.LegModel) or not IsValid(VMLegs.LegParent)
	end)

	-- 帧循环上下文钩子（可选，如需VMLegs单独控制可添加）
	hook.Add('UPExtLegsManipFrameContextStart', extraHookId, function(legsManip)
		return not IsValid(VMLegs.LegModel) -- VMLegs模型失效则起始就睡眠
	end)
	hook.Add('UPExtLegsManipFrameContextEnd', extraHookId, function(legsManip)
		return not IsValid(VMLegs.LegParent) -- VMLegs父级失效则结束时睡眠
	end)
end

function ManipLegs:UnRegisterVMLegsListener()
	-- 1. 睡眠组件
	self:Sleep()

	-- 2. 注销VMLegs_LISTENER核心钩子
	for _, v in ipairs(self.VMLegs_LISTENER) do
		hook.Remove(v.EVENT_NAME, v.IDENTITY)
	end

	-- 3. 批量注销所有辅助钩子（只需按统一标识移除，无需硬编码！）
	local extraHookId = self.VMLegs_EXTRA_HOOK_ID
	hook.Remove('UPExtLegsManipTargetChanged', extraHookId)
	hook.Remove('UPExtLegsManipRunTimeSleep', extraHookId)
	hook.Remove('UPExtLegsManipFrameContextStart', extraHookId)
	hook.Remove('UPExtLegsManipFrameContextEnd', extraHookId)

	-- 4. 注销帧循环钩子
	self:PopFrameLoop()
end

-- 控制台变量：对应VMLegs监听器
local upext_legsmanip_vmlegs = CreateClientConVar('upext_legsmanip_vmlegs', '1', true, false, '')
-- ==============================================================
-- 动态注册/注销
-- ==============================================================
local function temp_changecall(name, old, new)
	if new == '1' then
		print('[UPExt]: LegsManip: RegisterVMLegsListener')
		ManipLegs:RegisterVMLegsListener()
	else
		print('[UPExt]: LegsManip: UnRegisterVMLegsListener')
		ManipLegs:UnRegisterVMLegsListener()
	end
end
cvars.AddChangeCallback('upext_legsmanip_vmlegs', temp_changecall, 'default')

hook.Add('KeyPress', 'UPExtLegsManip', function()
	hook.Remove('KeyPress', 'UPExtLegsManip')
	temp_changecall(nil, nil, upext_legsmanip_vmlegs:GetBool() and '1' or '0')
	temp_changecall = nil
end)

-- ==============================================================
-- 菜单
-- ==============================================================
UPar.SeqHookAdd('UParExtendMenu', 'LegsManip', function(panel)
	panel:Help('·························· 腿部控制器 ··························')
	panel:CheckBox('#upext.legsmanip', 'upext_legsmanip_vmlegs')
	panel:ControlHelp('#upext.legsmanip.help')
	local help2 = panel:ControlHelp('#upext.legsmanip.help2')
	help2:SetTextColor(Color(255, 170, 0))
end, 1)