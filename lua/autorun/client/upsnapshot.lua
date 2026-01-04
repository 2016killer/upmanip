
--[[
	作者:白狼
	2025 1 4

    只是一张普通的表, 在 UPManip 中使用, 这样获取数据的时候不需要每次都判断类型
    由于它可能在高频、内部场景调用, 所以对输入边界不作验证
--]]

UPSnapshot = {}
UPSnapshot.__index = UPSnapshot

function UPSnapshot:New()
    local self = setmetatable({}, UPSnapshot)
    self.MatTbl = {}
    self.BoneIdTbl = {}
    self.ParentIdTbl = {}
    self.IsClosure = true
    return self
end

function UPSnapshot:SetBoneMatrix(boneName, mat)
    self.MatTbl[boneName] = mat
end

function UPSnapshot:GetBoneMatrix(boneName)
    return self.MatTbl[boneName]
end

function UPSnapshot:LookupBone(boneName)
    return self.BoneIdTbl[boneName]
end

function UPSnapshot:GetParent(boneName)
    return self.ParentIdTbl[boneName]
end

function UPSnapshot:GetBoneName(boneId)
    for k, v in pairs(self.BoneIdTbl) do
        if v == boneId then return k end
    end
    return nil
end


function ENTITY:UPMaSnapshot(boneMapping, withLocal, boneIterator)
	-- 默认已经初始化验证过了, 这里不再重复验证

	local GetExtendMatrix = boneIterator and boneIterator.GetExtendMatrix
	local SnapshotHandler = boneIterator and boneIterator.SnapshotHandler
	local snapshot = {}
	local flags = {}

	for _, mappingData in ipairs(boneMapping) do
		local boneName = mappingData.bone

		local boneId = self:LookupBone(boneName)
		if not boneId then 
			flags[boneName] = bit.bor(ERR_FLAG_BONEID, CALL_FLAG_SNAPSHOT)
			continue 
		end

		local matrix = self:GetBoneMatrix(boneId)
		if not matrix then 
			flags[boneName] = bit.bor(ERR_FLAG_MATRIX, CALL_FLAG_SNAPSHOT)
			continue 
		end

		snapshot[boneName] = matrix
		flags[boneName] = SUCC_FLAG

		if not withLocal then
			continue
		end




	end

	if isfunction(SnapshotHandler) then
		SnapshotHandler(boneIterator, self, snapshot, flags)
	end

	return snapshot, flags
end
