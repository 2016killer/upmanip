--[[
	作者:白狼
	2025 1 6
	注意: 这只是一个 demo, 只有参考价值, 没有拓展价值
	这个 demo 使用的是固定的检视动作, 来自 YuRaNnNzZZ (TFA作者) 的 hm500 模型.
	这个 demo 将会展示 UPManip 中骨骼代理的用法, 以及 UPManip 的缺点。

	首先 UPManip 对骨骼的控制可以在渲染上下文之外, 不同于 ent:SetBonePosition, 
	这是他的优点也是缺点, 但我还是感觉 ent:SetBonePosition 更好, 因为它不用算那么多逆矩阵,
	也不需要等位姿同步完成那一帧开始，如果使用 ent:SetBonePosition 只要做一个特殊实体, 
	然后重写 Draw 即可。 (操，为什么没早看到它的文档...)

	但 UPManip 依旧具有价值, 那就是关于骨骼代理的概念, 只需要简单写两三个接口就能扩张骨骼集、
	操作集，这里我们统一使用 "WEAPON" 来表示武器, 然后在代理上挂载静态映射, 通过模型路径来找到
	武器对应的骨骼名和偏移矩阵。

	如果想要拓展到任意动作，任意武器，那就需要很多映射，但这总比同个动作每个武器独立弄一个动作好。
	关于检视的镜头晃动, 具体怎么做, 实际上 VManip Base 里面有实例, 直接抄他的就行。
--]]


local hl2inspect_demo = UPAction:Register('hl2inspect_demo', {
	AAAACreat = '白狼',
	AAADesc = '#hl2inspect_demo.desc',
	label = '#hl2inspect_demo',
	defaultDisabled = false
})

local effect = UPEffect:Register('hl2inspect_demo', 'default', {
	label = '#default', 
	AAAACreat = '白狼'
})

if SERVER then 
	hook.Add('PlayerSwitchWeapon', 'hl2inspect_demo', function(ply)
		if IsValid(ply) and ply:IsPlayer() then
			ply:SendLua('RunConsoleCommand("upmanip_hl2inspect_demo_clear")')
		end
	end)

	effect.Start = UPar.emptyfunc
	effect.End = UPar.emptyfunc
	return 
end

local function temp_interrupt()
	UPar.CallPlyUsingEff('hl2inspect_demo', 'Clear', LocalPlayer())
end

concommand.Add('upmanip_hl2inspect_demo_clear', temp_interrupt)

hook.Add('KeyPress', 'hl2inspect_demo_interrupt', function(ply, key)
	if ply ~= LocalPlayer() then
		return
	end

	if key == IN_RELOAD or key == IN_ATTACK then
		temp_interrupt()
	end
end)

local function temp_start()
	UPar.CallPlyUsingEff('hl2inspect_demo', 'Start', LocalPlayer())
end

concommand.Add('upmanip_hl2inspect_demo_start', temp_start)

UPKeyboard.Register('hl2inspect_demo', '[]', '#hl2inspect_demo')
UPar.SeqHookAdd('UParKeyPress', 'hl2inspect_demo', function(eventflags)
	if eventflags['hl2inspect_demo'] then
		eventflags['hl2inspect_demo'] = UPKeyboard.KEY_EVENT_FLAGS.HANDLED
		temp_start()
	end
end)
-- =====================================================  
-- 骨骼代理
-- =====================================================
UPManip.ArmProxyDemo = UPManip.ArmProxyDemo or {}
local ArmProxyDemo = UPManip.ArmProxyDemo

-- 这里指定了要操作的骨骼列表, 'WEAPON' 这个骨骼实际上是一个抽象, 需要通过代理器映射到具体骨骼
local BoneList = {
	'WEAPON',
	'ValveBiped.Bip01_L_UpperArm',
	'ValveBiped.Bip01_L_Forearm',
	'ValveBiped.Bip01_L_Hand',
	'ValveBiped.Bip01_L_Wrist',
	'ValveBiped.Bip01_L_Ulna',
	'ValveBiped.Bip01_L_Finger4',
	'ValveBiped.Bip01_L_Finger41',
	'ValveBiped.Bip01_L_Finger42',
	'ValveBiped.Bip01_L_Finger3',
	'ValveBiped.Bip01_L_Finger31',
	'ValveBiped.Bip01_L_Finger32',
	'ValveBiped.Bip01_L_Finger2',
	'ValveBiped.Bip01_L_Finger21',
	'ValveBiped.Bip01_L_Finger22',
	'ValveBiped.Bip01_L_Finger1',
	'ValveBiped.Bip01_L_Finger11',
	'ValveBiped.Bip01_L_Finger12',
	'ValveBiped.Bip01_L_Finger0',
	'ValveBiped.Bip01_L_Finger01',
	'ValveBiped.Bip01_L_Finger02',

	'ValveBiped.Bip01_R_UpperArm',
	'ValveBiped.Bip01_R_Forearm',
	'ValveBiped.Bip01_R_Hand',
	'ValveBiped.Bip01_R_Wrist',
	'ValveBiped.Bip01_R_Ulna',
	'ValveBiped.Bip01_R_Finger4',
	'ValveBiped.Bip01_R_Finger41',
	'ValveBiped.Bip01_R_Finger42',
	'ValveBiped.Bip01_R_Finger3',
	'ValveBiped.Bip01_R_Finger31',
	'ValveBiped.Bip01_R_Finger32',
	'ValveBiped.Bip01_R_Finger2',
	'ValveBiped.Bip01_R_Finger21',
	'ValveBiped.Bip01_R_Finger22',
	'ValveBiped.Bip01_R_Finger1',
	'ValveBiped.Bip01_R_Finger11',
	'ValveBiped.Bip01_R_Finger12',
	'ValveBiped.Bip01_R_Finger0',
	'ValveBiped.Bip01_R_Finger01',
	'ValveBiped.Bip01_R_Finger02'

}

-- 这里指定了 WEAPON 对应的骨骼名
ArmProxyDemo.BoneWeaponMapping = {
	['models/weapons/c_357.mdl'] = 'Python',
	['models/upmanip_demo/yurie_customs/c_hm500.mdl'] = 'j_gun',
	['models/weapons/c_crossbow.mdl'] = 'ValveBiped.Base',
	['models/weapons/c_irifle.mdl'] = 'Base',
	['models/weapons/c_shotgun.mdl'] = 'ValveBiped.Gun',
	['models/weapons/c_physcannon.mdl'] = 'Base',
	['models/weapons/c_toolgun.mdl'] = 'Base',
	['models/weapons/c_superphyscannon.mdl'] = 'Base',
	['models/weapons/c_smg1.mdl'] = 'ValveBiped.base',
	['models/weapons/c_rpg.mdl'] = 'base',
}

-- 你妈比的?
// local temp = Matrix()
// temp:SetTranslation(Vector(1.999999, -0.000000, 3.249999))
// temp:SetAngles(Angle(-0.000, 90.000, 90.000))
// temp:Rotate(Angle(0, 0, 25))
// local temp2 = Matrix()
// temp2:SetTranslation(Vector(0, 0, 0.5))
// temp = temp * temp2
// print(temp:GetTranslation())
// print(temp:GetAngles())

-- 这里指定了不同模型间需要的偏移矩阵
-- 这里只是为了少写一点, 后续需要初始化成矩阵
ArmProxyDemo.BoneWeaponOffset = {
	['models/weapons/c_357.mdl-->models/upmanip_demo/yurie_customs/c_hm500.mdl'] = {
		Vector(3.218955, -0.071265, 2.476537),
		Angle(2.566, 95.680, 82.198)
	},
	['models/weapons/c_crossbow.mdl-->models/upmanip_demo/yurie_customs/c_hm500.mdl'] = {
		Vector(-17.999994, -1.000000, -14.999996),
		Angle(0, 90, 90)
	},
	['models/weapons/c_irifle.mdl-->models/upmanip_demo/yurie_customs/c_hm500.mdl'] = {
		Vector(-4.999999, -0.000000, 3.000000),
		Angle(-0.000, 90.000, 90.000)
	},
	['models/weapons/c_shotgun.mdl-->models/upmanip_demo/yurie_customs/c_hm500.mdl'] = {
		Vector(14.999995, 0.000001, 4.999999),
		Angle(-0.000, 90.000, 90.000)
	},
	['models/weapons/c_physcannon.mdl-->models/upmanip_demo/yurie_customs/c_hm500.mdl'] = {
		Vector(7.999997, 4.999999, 5.000000),
		Angle(-0.000, 90.000, 90.000)
	},
	['models/weapons/c_toolgun.mdl-->models/upmanip_demo/yurie_customs/c_hm500.mdl'] = {
		Vector(-21.999994, 3.499998, -4.999999),
		Angle(-0.000, 90.000, 90.000)
	},
	['models/weapons/c_superphyscannon.mdl-->models/upmanip_demo/yurie_customs/c_hm500.mdl'] = {
		Vector(7.999997, 4.999999, 5.000000),
		Angle(-0.000, 90.000, 90.000)
	},
	['models/weapons/c_smg1.mdl-->models/upmanip_demo/yurie_customs/c_hm500.mdl'] = {
		Vector(2.453153, 0.000000, 3.038690),
		Angle(-0.000, 90.000, 115.000)
	},
	['models/weapons/c_rpg.mdl-->models/upmanip_demo/yurie_customs/c_hm500.mdl'] = {
		Vector(-9.999997, 0.499998, 7.999998),
		Angle(-0.000, 90.000, 90.000)
	},
}

function ArmProxyDemo:InitBoneWeaponOffset()
	for k, v in pairs(self.BoneWeaponOffset) do
		if ismatrix(v) then continue end
		assert(istable(v), 'expect table, got', type(v))

		local mat = Matrix()
		local pos, ang = unpack(v)
		mat:SetTranslation(pos)
		mat:SetAngles(ang)

		self.BoneWeaponOffset[k] = mat
	end
end

-- 这里实现 WEAPON 的变化矩阵获取
function ArmProxyDemo:GetMatrix(ent, boneName, PROXY_FLAG_GET_MATRIX)
	boneName = boneName == 'WEAPON' and self.BoneWeaponMapping[ent:GetModel()] or boneName
	return ent:UPMaGetBoneMatrix(boneName)
end

-- 这里实现 WEAPON 的位置操作 
function ArmProxyDemo:SetPosition(ent, boneName, posw, angw)
	boneName = boneName == 'WEAPON' and self.BoneWeaponMapping[ent:GetModel()] or boneName
	ent:UPMaSetBonePosition(boneName, posw, angw)
end

-- 这里实现偏移应用
function ArmProxyDemo:AdjustLerpRange(ent, boneName, t, initMatrix, finalMatrix, ent1, ent2, LERP_WORLD)
	if boneName ~= 'WEAPON' then return t, initMatrix, finalMatrix end

	local key = string.format('%s-->%s', ent1:GetModel(), ent2:GetModel())
	local offset = self.BoneWeaponOffset[key]
	if not offset then return t, initMatrix, finalMatrix end

	return t, initMatrix, finalMatrix * offset
end

-- 在这里指定每个骨骼的插值空间
function ArmProxyDemo:GetLerpSpace(ent, boneName, t, ent1, ent2)
	if boneName == 'WEAPON' 
	or boneName == 'ValveBiped.Bip01_R_UpperArm' 
	or boneName == 'ValveBiped.Bip01_L_UpperArm' then 
		return UPManip.LERP_SPACE.LERP_WORLD
	else	
		return UPManip.LERP_SPACE.LERP_LOCAL
	end
end

ArmProxyDemo:InitBoneWeaponOffset()
-- =====================================================
-- 特效
-- =====================================================

local animEnt = nil
local animModel = nil
local finalEnt = nil
local t = 0
local timeout = 10
local isFadeIn = true
local startCycle = 0
local endCycle = 0.8
// local startCycle = 0.78
// local endCycle = 2
local renderT = 0.01


function effect:Start()
	if UPar.IsFrameLoopExist('hl2inspect_demo_eff') then 
		isFadeIn = false
		return 
	end


	local hand = LocalPlayer():GetHands()
	if not IsValid(hand) or not hand:GetModel() then
		print('no hand or hand model')
		return
	end

	local vm = LocalPlayer():GetViewModel()
	if not IsValid(vm) or not vm:GetModel() then
		print('no vm or vm model')
		return
	end

	if not IsValid(finalEnt) then
		finalEnt = ClientsideModel('models/upmanip_demo/yurie_customs/c_hm500.mdl', RENDERGROUP_OTHER)
	end
	
	if not IsValid(animEnt) then
		animEnt = ClientsideModel(vm:GetModel(), RENDERGROUP_OTHER)
	end

	if not IsValid(animModel) then
		animModel = ClientsideModel(hand:GetModel(), RENDERGROUP_OTHER)
	end

	local seqId = finalEnt:LookupSequence('inspect')
	finalEnt:ResetSequenceInfo()
	finalEnt:ResetSequence(seqId)
	finalEnt:SetPlaybackRate(1)
	finalEnt:SetCycle(startCycle)
	finalEnt:SetParent(vm)
	finalEnt:SetNoDraw(true)

	animEnt:SetParent(vm)
	animEnt:SetNoDraw(true)
	
	animModel:SetParent(animEnt)
	animModel:AddEffects(EF_BONEMERGE)
	animModel:SetNoDraw(true)

	for k, v in pairs(hand:GetBodyGroups()) do
		local current = hand:GetBodygroup(v.id)
		animModel:SetBodygroup(v.id,  current)
	end

	for k, v in ipairs(hand:GetMaterials()) do
		animModel:SetSubMaterial(k - 1, hand:GetSubMaterial(k - 1))
	end

	animModel:SetSkin(hand:GetSkin())
	animModel:SetMaterial(hand:GetMaterial())
	animModel:SetColor(hand:GetColor())

	vm:SetColor(Color(255, 255, 255, 100))

	t = 0
	isFadeIn = true
	UPar.PushFrameLoop('hl2inspect_demo_eff', 
		function(...)
			return self:FrameLoop(...)
		end, nil, 
		timeout, 
		function(...)
			return self:FrameLoopClear(...)
		end,
		'PreDrawViewModel'
	)
	hook.Add('PreDrawViewModel', 'hl2inspect_demo_eff', function()
		if t < renderT then return end
		return true
	end)
end



local function DrawCoordinate(mat, pos)
	if not mat then return end
	local pos = pos or mat:GetTranslation()
	local ang = mat:GetAngles()

	render.DrawLine(pos, pos + ang:Forward() * 20, Color(255, 0, 0), true)
	render.DrawLine(pos, pos - ang:Right() * 20, Color(0, 255, 0), true)
	render.DrawLine(pos, pos + ang:Up() * 20, Color(0, 0, 255), true)
end

function effect:FrameLoop(dt, cur, additive)
	local vm = LocalPlayer():GetViewModel()
	local hand = LocalPlayer():GetHands()

	if not LocalPlayer():Alive() then 
		print('player not alive')
		return true 
	end

	if not IsValid(hand) or not hand:GetModel() then
		print('no hand or hand model')
		return true
	end

	if not IsValid(vm) or not vm:GetModel() then
		print('no vm or vm model')
		return true
	end

	if not IsValid(finalEnt) or not IsValid(animEnt) or not IsValid(animModel) then
		print('no finalEnt or animEnt or animModel')
		return true
	end

	finalEnt:SetPos(vm:LocalToWorld(Vector(7, 0, 0)))
	finalEnt:SetAngles(vm:GetAngles())
	finalEnt:SetupBones()

	animEnt:SetPos(vm:GetPos())
	animEnt:SetAngles(vm:GetAngles())
	animEnt:SetupBones()
	
	vm:SetupBones()

	local newCycle = finalEnt:GetCycle() + dt * 0.25
	finalEnt:SetCycle(newCycle)
	isFadeIn = isFadeIn and newCycle <= endCycle

	if isFadeIn then
		t = math.Clamp(t + dt * 5, 0, 1)
	else
		t = math.Clamp(t - dt * 5, 0, 1)
		if t <= 0.01 then return true end
	end


	local debug = GetConVar('developer') and GetConVar('developer'):GetBool()

	local resultBatch, runtimeflags = animEnt:UPMaFreeLerpBatch(
		BoneList, 
		t, 
		vm, 
		finalEnt, 
		ArmProxyDemo
	)
	// if debug then vm:UPMaPrintLog(runtimeflags) end

	runtimeflags = animEnt:UPManipBoneBatch(
		resultBatch, 
		BoneList, 
		UPManip.MANIP_FLAG.MANIP_POSITION,
		ArmProxyDemo
	)
	// if debug then vm:UPMaPrintLog(runtimeflags) end
	if debug then 
		DrawCoordinate(
			resultBatch['WEAPON'], 
			resultBatch['ValveBiped.Bip01_R_Hand'] and resultBatch['ValveBiped.Bip01_R_Hand']:GetTranslation()
		) 
	end

	if t <= renderT then return end

	animModel:DrawModel()
	animEnt:DrawModel()
end

function effect:FrameLoopClear(_, _, _,reason)
	if reason == 'OVERRIDE' then return end

	if IsValid(finalEnt) then finalEnt:Remove() end
	if IsValid(animEnt) then animEnt:Remove() end

	local hand = LocalPlayer():GetHands()
	if IsValid(hand) then hand:SetNoDraw(false) end

	local vm = LocalPlayer():GetViewModel()
	if IsValid(vm) then vm:SetNoDraw(false) end

	print('clear hl2inspect_demo_eff', reason)

	hook.Remove('PreDrawViewModel', 'hl2inspect_demo_eff')
end

function effect:Clear()
	UPar.PopFrameLoop('hl2inspect_demo_eff')
end

concommand.Add('upmanip_vm_bone', function(ply, cmd, args)
	local tarBoneName = args[1]
	local lifeTime = tonumber(args[2]) or 5

	local vm = ply:GetViewModel()
	if not IsValid(vm) then
		print('no vm')
		return
	end
	vm:SetupBones()

	local offset = ply:GetAimVector() * 25
	offset.z = 0

	print('model:', vm:GetModel())
	local function MarkBone(boneId)
		local boneName = vm:GetBoneName(boneId)
		local boneMat = vm:GetBoneMatrix(boneId)
		local parentId = vm:GetBoneParent(boneId)
		local parentMat = parentId == -1 and vm:GetWorldTransformMatrix() or vm:GetBoneMatrix(parentId)

		if boneMat then debugoverlay.Box(boneMat:GetTranslation() + offset, Vector(-0.2, -0.2, -0.2), Vector(0.2, 0.2, 0.2), lifeTime) end
		if boneMat and parentMat then
			debugoverlay.Line(
				boneMat:GetTranslation() + offset,
				parentMat:GetTranslation() + offset, 
				lifeTime, 
				Color(255, 0, 0), 
				true
			)
		end
		if boneMat and boneName ~= '__INVALIDBONE__' then
			print(boneName)
			debugoverlay.Text(
				boneMat:GetTranslation() + offset,
				boneName,
				lifeTime,
				nil,
				true
			)
		end 
	end


	if tarBoneName then
		local boneId = vm:LookupBone(tarBoneName)
		if boneId then
			MarkBone(boneId)
		else
			print('no bone:', tarBoneName)
		end
	else
		for i = 0, vm:GetBoneCount() - 1 do
			MarkBone(i)
		end
	end
end)
