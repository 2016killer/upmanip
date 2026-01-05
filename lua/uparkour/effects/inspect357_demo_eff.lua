
if not GetConVar('developer') or not GetConVar('developer'):GetBool() then return end

local effect = UPEffect:Register('inspect357_demo', 'default', {
	label = '#default', 
	AAAACreat = '白狼'
})

if SERVER then 
	effect.Start = UPar.emptyfunc
	effect.Clear = UPar.emptyfunc
	return 
end

local finalEnt = nil
local t = 0
local timeout = 3

local VMRightArmProxy = {}
VMRightArmProxy.BoneList={
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
	['models/weapons/c_357.mdl'] = 'Python'
}

function VMRightArmProxy:GetMatrix(ent, boneName, mode)
	boneName = boneName == 'WEAPON' and self.WeaponBoneMapping[ent:GetModel()] or boneName
	return ent:UPMaGetBoneMatrix(boneName)
end

function VMRightArmProxy:GetLerpSpace(ent, boneName, mode)
	return UPManip.LERP_SPACE.LERP_WORLD 
end


function effect:Start()
	if not IsValid(finalEnt) then
		finalEnt = ClientsideModel('models/upmanip_demo/yurie_customs/c_hm500.mdl', RENDERGROUP_OTHER)
	end
	
	local vm = LocalPlayer():GetViewModel()
	if not IsValid(vm) then
		print('no vm')
		return
	end
	vm:SetupBones()

	
	local seqId = finalEnt:LookupSequence('inspect')
	finalEnt:ResetSequenceInfo()
	finalEnt:ResetSequence(seqId)
	finalEnt:SetPlaybackRate(1)
	finalEnt:SetCycle(0)
	finalEnt:SetParent(vm)

	t = 0

	UPar.PushFrameLoop('inspect357_demo_eff', 
		function(...)
			return self:FrameLoop(...)
		end, nil, 
		timeout, 
		function(...)
			return self:FrameLoopClear(...)
		end
	)
end


function effect:FrameLoop(dt, cur, additive)
	local vm = LocalPlayer():GetViewModel()

	if not IsValid(finalEnt) or not IsValid(vm) then
		print('no vm or finalEnt')
		return true
	end

	local newCycle = finalEnt:GetCycle() + dt

	finalEnt:SetCycle(newCycle)
	if newCycle > 1 then
		return true
	end

	finalEnt:SetPos(vm:LocalToWorld(Vector(20, 0, 0)))
	finalEnt:SetAngles(vm:GetAngles())
	finalEnt:SetupBones()

	vm:SetupBones()

	t = math.Clamp(t + dt * 5, 0, 1)
	additive.t = t

	local resultBatch, runtimeflags = vm:UPMaFreeLerpBatch(
		VMRightArmProxy.BoneList, 
		t, 
		vm, 
		finalEnt, 
		VMRightArmProxy
	)
	// vm:UPMaPrintLog(runtimeflags)

	runtimeflags = vm:UPManipBoneBatch(
		resultBatch, 
		VMRightArmProxy.BoneList, 
		UPManip.MANIP_FLAG.MANIP_POSITION,
		VMRightArmProxy
	)
	// vm:UPMaPrintLog(runtimeflags)
end

effect.FrameLoopClear = function(_, _, _, reason)
	if IsValid(finalEnt) then finalEnt:Remove() end
	print('clear inspect357_demo_eff', reason)
end

function effect:Clear()
	UPar.PopFrameLoop('inspect357_demo_eff')
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
