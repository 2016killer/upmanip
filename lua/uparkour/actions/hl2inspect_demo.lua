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
	effect.Start = UPar.emptyfunc
	effect.End = UPar.emptyfunc
	return 
end

UPKeyboard.Register('hl2inspect_demo', '[]')

UPar.SeqHookAdd('UParKeyPress', 'hl2inspect_demo', function(eventflags)
	if eventflags['hl2inspect_demo'] then
		eventflags['hl2inspect_demo'] = UPKeyboard.KEY_EVENT_FLAGS.HANDLED
		UPar.CallPlyUsingEff('hl2inspect_demo', 'Start', LocalPlayer())
	end
end)

local animEnt = nil
local animModel = nil
local finalEnt = nil
local t = 0
local timeout = 10


UPManip.VMRightArmProxy = UPManip.VMRightArmProxy or {}
local VMRightArmProxy = UPManip.VMRightArmProxy
local BoneList = {
	'WEAPON',
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

VMRightArmProxy.WeaponBoneMapping = {
	['models/weapons/c_357.mdl'] = 'Python',
	['models/upmanip_demo/yurie_customs/c_hm500.mdl'] = 'j_gun'
}

-- 你妈比的?
// local temp = Matrix()
// temp:Rotate(Angle(90, 0, 0))
// temp:Rotate(Angle(0, 50, 0))
// temp:Rotate(Angle(0, 0, 20))
// temp:Rotate(Angle(0, 20, 0))

// temp:Rotate(Angle(0, 0, -25))
// temp:Rotate(Angle(0, 20, 0))
// temp:Rotate(Angle(10, 0, 0))
// local temp2 = Matrix()
// temp2:SetTranslation(Vector(-0.5, 2, 3.5))
// temp = temp * temp2
VMRightArmProxy.WeaponBoneOffset = {
	['models/weapons/c_357.mdl-->models/upmanip_demo/yurie_customs/c_hm500.mdl'] = {
		Vector(3.218955, -0.071265, 2.476537),
		Angle(2.566, 95.680, 82.198)
	}
}

function VMRightArmProxy:InitWeaponBoneOffset()
	for k, v in pairs(self.WeaponBoneOffset) do
		if ismatrix(v) then continue end
		assert(istable(v), 'expect table, got', type(v))

		local mat = Matrix()
		local pos, ang = unpack(v)
		mat:SetTranslation(pos)
		mat:SetAngles(ang)

		self.WeaponBoneOffset[k] = mat
	end
end

function VMRightArmProxy:GetMatrix(ent, boneName, PROXY_FLAG_GET_MATRIX)
	boneName = boneName == 'WEAPON' and self.WeaponBoneMapping[ent:GetModel()] or boneName
	return ent:UPMaGetBoneMatrix(boneName)
end

function VMRightArmProxy:SetPosition(ent, boneName, posw, angw)
	boneName = boneName == 'WEAPON' and self.WeaponBoneMapping[ent:GetModel()] or boneName
	ent:UPMaSetBonePosition(boneName, posw, angw)
end

function VMRightArmProxy:AdjustLerpRange(ent, boneName, t, initMatrix, finalMatrix, ent1, ent2, LERP_WORLD)
	if boneName ~= 'WEAPON' then return t, initMatrix, finalMatrix end

	local key = string.format('%s-->%s', ent1:GetModel(), ent2:GetModel())
	local offset = self.WeaponBoneOffset[key]
	if not offset then return t, initMatrix, finalMatrix end

	return t, initMatrix, finalMatrix * offset
end

function VMRightArmProxy:GetLerpSpace(ent, boneName, t, ent1, ent2)
	return UPManip.LERP_SPACE.LERP_WORLD 
end

VMRightArmProxy:InitWeaponBoneOffset()

function effect:Start()
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
	finalEnt:SetCycle(0)
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

	vm:SetMaterial('Models/effects/vol_light001')
	hand:SetMaterial('Models/effects/vol_light001')

	t = 0
	UPar.PushFrameLoop('hl2inspect_demo_eff', 
		function(...)
			return self:FrameLoop(...)
		end, nil, 
		timeout, 
		function(...)
			return self:FrameLoopClear(...)
		end,
		'PostDrawViewModel'
	)
end



local function DrawCoordinate(mat)
	if not mat then return end
	local pos = mat:GetTranslation()
	local ang = mat:GetAngles()

	render.DrawLine(pos, pos + ang:Forward() * 20, Color(255, 0, 0), false)
	render.DrawLine(pos, pos + ang:Right() * 20, Color(0, 255, 0), false)
	render.DrawLine(pos, pos + ang:Up() * 20, Color(0, 0, 255), false)
end

function effect:FrameLoop(dt, cur, additive)
	local vm = LocalPlayer():GetViewModel()

	if not IsValid(finalEnt) or not IsValid(animEnt) or not IsValid(animModel) or not IsValid(vm) then
		print('no vm or finalEnt or animEnt or animModel')
		return true
	end

	finalEnt:SetPos(vm:LocalToWorld(Vector(10, 0, 0)))
	finalEnt:SetAngles(vm:GetAngles())
	finalEnt:SetupBones()

	animEnt:SetPos(vm:GetPos())
	animEnt:SetAngles(vm:GetAngles())
	animEnt:SetupBones()
	
	vm:SetupBones()

	local newCycle = finalEnt:GetCycle() + dt * 0.25
	finalEnt:SetCycle(newCycle)
	if newCycle > 0.8 then
		t = math.Clamp(t - dt * 5, 0, 1)
	else
		t = math.Clamp(t + dt * 5, 0, 1)
	end

	local resultBatch, runtimeflags = animEnt:UPMaFreeLerpBatch(
		BoneList, 
		t, 
		vm, 
		finalEnt, 
		VMRightArmProxy
	)
	// vm:UPMaPrintLog(runtimeflags)

	runtimeflags = animEnt:UPManipBoneBatch(
		resultBatch, 
		BoneList, 
		UPManip.MANIP_FLAG.MANIP_POSITION,
		VMRightArmProxy
	)
	// vm:UPMaPrintLog(runtimeflags)

	animModel:DrawModel()
	animEnt:DrawModel()
	DrawCoordinate(VMRightArmProxy:GetMatrix(animEnt, 'WEAPON'))
end

function effect:FrameLoopClear(_, _, _,reason)
	if reason == 'OVERRIDE' then return end

	if IsValid(finalEnt) then finalEnt:Remove() end
	if IsValid(animEnt) then animEnt:Remove() end

	local hand = LocalPlayer():GetHands()
	if IsValid(hand) then hand:SetMaterial('') end

	local vm = LocalPlayer():GetViewModel()
	if IsValid(vm) then vm:SetMaterial('') end

	print('clear hl2inspect_demo_eff', reason)
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

		if boneMat then debugoverlay.Sphere(boneMat:GetTranslation() + offset, 1, lifeTime) end
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
