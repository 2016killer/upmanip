--[[
	作者:白狼
	2025 1 1

	假的 GmodLegs3 
	放弃将它作为工具的想法, 随便写吧...
--]]

-- ==============================================================
-- 骨骼代理定义, 位置需要偏移
-- ==============================================================
local zerovec = Vector(0, 0, 0)
local zeroang = Angle(0, 0, 0)
local diagonalvec = Vector(1, 1, 1)
local unitMat = Matrix()
local emptyTable = {}


UPManip.GmodLegs3ToVMLegsProxyDemo = {}

local GmodLegs3ToVMLegsProxyDemo = UPManip.GmodLegs3ToVMLegsProxyDemo
GmodLegs3ToVMLegsProxyDemo.PlyPelvisOffset = -22

function GmodLegs3ToVMLegsProxyDemo:GetMatrix(ent, boneName, PROXY_FLAG_GET_MATRIX)
	if boneName == 'ValveBiped.Bip01_Pelvis' and ent == LocalPlayer() then
		local mat = ent:UPMaGetBoneMatrix(boneName)
		if not mat then return nil end
		local pos = mat:GetTranslation()
		local offsetDir = LocalPlayer():GetAimVector()
		offsetDir.z = 0
		offsetDir:Normalize()
		pos = pos + offsetDir * self.PlyPelvisOffset
		mat:SetTranslation(pos)

		return mat
	else
		return ent:UPMaGetBoneMatrix(boneName)
	end
end

function GmodLegs3ToVMLegsProxyDemo:GetLerpSpace(ent, boneName, t, ent1, ent2)
	if boneName == 'ValveBiped.Bip01_Pelvis' then
		return UPManip.LERP_SPACE.LERP_WORLD
	else
		return UPManip.LERP_SPACE.LERP_LOCAL
	end
end
-- ==============================================================
-- 腿部动画插值, 从GmodLegs3到VMLegs
-- ==============================================================

if g_ManipLegs and isentity(g_ManipLegs.LegEnt) and IsValid(g_ManipLegs.LegEnt) then
	g_ManipLegs.LegEnt:Remove()
	local succ, msg = pcall(g_ManipLegs.UnRegisterVMLegsListener, g_ManipLegs)
	if not succ then error(msg) end
end
g_ManipLegs = {}


local ManipLegs = g_ManipLegs

ManipLegs.BoneList = {
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

ManipLegs.BonesToRemove = {
	['ValveBiped.Bip01_Head1'] = true,
	['ValveBiped.Bip01_L_Hand'] = true,
	['ValveBiped.Bip01_L_Forearm'] = true,
	['ValveBiped.Bip01_L_Upperarm'] = {
		Vector(0, 0, 0),
		Angle(50, 50, 0)
	},
	['ValveBiped.Bip01_L_Clavicle'] = true,
	['ValveBiped.Bip01_R_Hand'] = true,
	['ValveBiped.Bip01_R_Forearm'] = true,
	['ValveBiped.Bip01_R_Upperarm'] = {
		Vector(0, 0, 0),
		Angle(-50, 50, 0)
	},
	['ValveBiped.Bip01_R_Clavicle'] = true,
	['ValveBiped.Bip01_Spine4'] = true,
}

ManipLegs.FRAME_LOOP = {
	{
		// eventName = 'PostDrawOpaqueRenderables',
		eventName = 'Think',
		identity = 'LegsManipView',
		timeout = 20,
		iterator = function(dt, cur, self)
			if not IsValid(LocalPlayer()) then
				return
			end

			local frameStartSleep = hook.Run('UPExtLegsManipFrameContextStart', self) or self:FrameContextStartCheck()
			if frameStartSleep then
				// print('frameStartSleep')
				self:Sleep()
				return
			end

			self:UpdateAnimation(dt)
	
			local frameEndSleep = hook.Run('UPExtLegsManipFrameContextEnd', self) or self:FrameContextEndCheck()
			if frameEndSleep then
				// print('frameEndSleep')
				self:Sleep()
				return
			end
		end
	},

	{
		eventName = 'ShouldDisableLegs',
		identity = 'DisableGmodLegs3',
		timeout = 20,
		call = function(self, ...)
			return true
		end
	}
}

ManipLegs.t = 0
ManipLegs.FadeInSpeed = 1
ManipLegs.FadeOutSpeed = 1
ManipLegs.Proxy = nil
ManipLegs.Snapshot = nil


function ManipLegs:FrameContextStartCheck()
	return not IsValid(LocalPlayer()) or not LocalPlayer():Alive() or not IsValid(self.LegEnt)
end

function ManipLegs:FrameContextEndCheck()
	return self:FrameContextStartCheck() or (not IsValid(self.FinalEnt) and self.t <= 0.01)
end

function ManipLegs:UpdateAnimation(dt)
	local debug = GetConVar('developer') and GetConVar('developer'):GetBool()

	local ang = LocalPlayer():GetAngles()
	ang.p = 0
	ang.r = 0

	self.LegEnt:SetPos(LocalPlayer():GetPos())
	self.LegEnt:SetAngles(ang)

	self.LegEnt:SetupBones()
	LocalPlayer():SetupBones()

	if IsValid(self.FinalEnt) then
		self.FinalEnt:SetupBones()
		self.t = math.Clamp(self.t + math.abs(self.FadeInSpeed) * dt, 0, 1)	
	else
		self.FinalEnt = nil
		self.t = math.Clamp(self.t - math.abs(self.FadeOutSpeed) * dt, 0, 1)

		if not self.Snapshot then
			self.Snapshot = self.LegEnt:UPMaSnapshot(self.BoneList, self.Proxy, true, true)
		end
	end

	local resultBatch, runtimeflags = self.LegEnt:UPMaFreeLerpBatch(
		self.BoneList,
		self.t,
		LocalPlayer(),
		self.FinalEnt or self.Snapshot or self.LegEnt,
		self.Proxy
	)

	if debug then self.LegEnt:UPMaPrintLog(runtimeflags) end

	runtimeflags = self.LegEnt:UPManipBoneBatch(
		resultBatch,
		self.BoneList,
		UPManip.MANIP_FLAG.MANIP_POSITION,
		self.Proxy
	)
	if debug then self.LegEnt:UPMaPrintLog(runtimeflags) end

	self.LegEnt:DrawModel()
end

function ManipLegs:PushFrameLoop()
	for _, v in ipairs(self.FRAME_LOOP) do
		if v.iterator then
			UPar.PushFrameLoop(v.identity, v.iterator, self, v.timeout, v.clear, v.eventName)
		end

		if v.call then
			hook.Add(v.eventName, v.identity, function(...)
				return v.call(self, ...)
			end)
			timer.Create(string.format('%s_%s_timeout', v.eventName, v.identity), v.timeout, 1, function() 
				hook.Remove(v.eventName, v.identity)
			end)
		end
	end
	
	return true
end

function ManipLegs:PopFrameLoop()
	for _, v in ipairs(self.FRAME_LOOP) do
		if v.iterator then
			UPar.PopFrameLoop(v.identity)
		end

		if v.call then
			timer.Remove(string.format('%s_%s_timeout', v.eventName, v.identity))
			hook.Remove(v.eventName, v.identity)
		end
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

	self.LegEnt:SetNoDraw(true)
	self.IsWake = false

	hook.Run('UPExtLegsManipSleep', self)

	return true
end

-- ==============================================================
-- VMLegs监听器
-- ==============================================================
ManipLegs.VMLegs_LISTENER = {
	{
		eventName = 'VMLegsPostPlayAnim',
		identity = 'LegsManipTrigger',
		call = function(self, anim, ...)
			if not IsValid(VMLegs.LegModel) or not IsValid(VMLegs.LegParent) then
				print('[UPExt]: LegsManip: VMLegs has not been started yet!')
				return
			end

			local animData = VMLegs:GetAnim(anim)
			if not istable(animData) then
				print('[UPExt]: LegsManip: VMLegs has no anim data for anim ', anim)
				return
			end

			VMLegs.LegModel:SetNoDraw(true)

			self.FadeInSpeed = animData.lerp_speed_in or 10
			self.FadeOutSpeed = animData.lerp_speed_out or 5
			self.FadeInCycle = (animData.startcycle or 0)
			self.FadeOutCycle = (animData.endcycle or 0.8)
			self.FinalEnt = VMLegs.LegParent
			self.Proxy = GmodLegs3ToVMLegsProxyDemo
			self.t = 0
			self.Snapshot = nil


			VMLegs.LegParent:SetCycle(self.FadeInCycle)
			
			self:Wake()	

			self.LegEnt:SetParent(VMLegs.LegParent)
		end
	},
	{
		eventName = 'UPExtLegsManipFrameContextEnd',
		identity = 'LegsManipCycle',
		call = function(self)
			if not IsValid(VMLegs.LegModel) or not IsValid(VMLegs.LegParent) then
				return
			end

			if VMLegs.LegParent:GetCycle() >= self.FadeOutCycle then
				VMLegs.Remove()
			end
		end
	}
}

function ManipLegs:RegisterVMLegsListener()
	for _, v in ipairs(self.VMLegs_LISTENER) do
		hook.Add(v.eventName, v.identity, function(...)
			return v.call(self, ...)
		end)
	end

	return true
end

function ManipLegs:UnRegisterVMLegsListener()
	for _, v in ipairs(self.VMLegs_LISTENER) do
		hook.Remove(v.eventName, v.identity)
	end

	return self:Sleep()
end

// ManipLegs:Init()


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
	local help = panel:ControlHelp('#upext.legsmanip.help')
	help:SetTextColor(Color(255, 170, 0))
end, 1)

hook.Add('UParkourInitialized', 'VMLegsAnimSlideFix', function()
	if not VMLegs then return end
	local slide = VMLegs:GetAnim('slide')
	if not slide then return end
	slide.endcycle = 0.5
	print('VMLegs anim "slide" fixed by UPExtLegsManip')
end)