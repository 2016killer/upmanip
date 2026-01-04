--[[
	作者:白狼
	2025 12 28

	此方法的使用门槛极高, 首先 ManipulateBonePosition 有距离限制, 限制为 128 个单位,
	所以如果想完成正确插值的话, 则必须在位置更新完成的那一帧, 
	所以想要完成正确插值, 最好单独加一个标志 + 回调来处理, 这样不容易导致混乱。

	由于这些函数常常在帧循环中, 加上计算略显密集 (串行), 所以很多的错误都是无声的, 这极大
	地增加了调试难度, 有点像GPU编程, 操, 我并不推荐使用这些。

	想要完成动作插值需要指定要操作的骨骼列表, 顺序必须正确, 从根骨骼开始往下。

	这里的插值分为两种 世界空间插值(CALL_FLAG_LERP_WORLD) 和 局部空间插值(CALL_FLAG_LERP_LOCAL)
	如果从本质来看, 世界空间的插值可以看做一种特殊的局部空间插值, 只是将所有骨骼的父级都看作是 World,

	同时这里的 API 都是用骨骼名来指向操作的骨骼, 而不是 boneId, 这对编写、调试都有好处, 缺点是不能像
	数字索引那样高效地递归处理外部骨骼 (实体本身的父级等), 如果需要处理外部骨骼详见 UPManip_ext.lua

	操作骨骼前最好先执行 ent:SetupBones(), 确保获取到最新的数据, 避免计算异常。

--]]

local zero = 1e-4

UPManip = UPManip or {}

UPManip.GetMatrixLocal = function(mat, parentMat, invert)
	if invert then
		if IsMatrixSingularFast(parentMat) then return nil end
		local matInvert = mat:GetInverse()
		if not matInvert then return nil end
		return matInvert * parentMat
	else
		if IsMatrixSingularFast(mat) then return nil end
		local parentMatInvert = parentMat:GetInverse()
		if not parentMatInvert then return nil end
		return parentMatInvert * mat
	end
end

UPManip.IsMatrixSingularFast = function(mat)
	-- 这个方法并不严谨, 只是工程化方案, 比直接求逆快很多
	-- 如果它底层是先算行列式的话
	-- 注意: 此方案只是筛选明显的奇异矩阵, 因为在骨骼相关场景中, 大部分奇异是缩放导致的
	-- 当然, 完全有理由认为加了这个会更慢, 因为在两种混合比例达到一定程度时, 这是没必要的
	-- 优化还是得考虑场景的
	
	local forward = mat:GetForward()
	local up = mat:GetUp()
	local right = mat:GetRight()

	return forward:LengthSqr() < zero or up:LengthSqr() < zero
	or right:LengthSqr() < zero
end


UPManip.__internal_FLAG_MSG = {}
UPManip.__internal_ADD_FLAG_MSG = function(self, msg, flag)
    local targetFlag = flag or 0
    local originalFlag = targetFlag

    while self.__internal_FLAG_MSG[targetFlag] do
        targetFlag = bit.lshift(targetFlag, 1)

        if targetFlag > 0xFFFFFFFFFFFFFFFF then
            error('溢出了, 自己改:' .. msg)
        end
    end

    self.__internal_FLAG_MSG[targetFlag] = msg
    return targetFlag
end

local function __internal_MarkBoneFamilyLevel(boneId, currentLevel, family, familyLevel, cached)
	cached = cached or {}

	if cached[boneId] then 
		print('')
		return
	end
	cached[boneId] = true

	familyLevel[boneId] = currentLevel

	if not family[boneId] then
		return
	end
	
	for childIdx, _ in pairs(family[boneId]) do
		__internal_MarkBoneFamilyLevel(childIdx, currentLevel + 1, family, familyLevel, cached)
	end
end

UPManip.GetBoneFamilyLevel = function(ent)
    assert(isentity(ent) and IsValid(ent), string.format('Invalid ent "%s" (not a entity)', ent))

	if not ent:GetModel() then
		print('[UPBonesProxy:SortByEnt]: ent no model')
		return
	end

	ent:SetupBones()

    local boneCount = ent:GetBoneCount()
    local family = {} 
    local familyLevel = {}

    for boneIdx = 0, boneCount - 1 do
        local parentIdx = ent:GetBoneParent(boneIdx)
        
        if not family[parentIdx] then
            family[parentIdx] = {}
        end
        family[parentIdx][boneIdx] = true
    end

	if not family[-1] then
		print(string.format('[UPBonesProxy:SortByEnt]: ent "%s" no root bone', ent))
		return
	end

    __internal_MarkBoneFamilyLevel(-1, 0, family, familyLevel)


	return familyLevel
end

UPManip.PrintLog = function(self, ent, runtimeflag, boneName, depth)
	-- 不要使用嵌套表, 这里只做了简单防御
	depth = depth or 0
	if depth > 10 then return end

	if istable(runtimeflag) then
		for boneName, flag in pairs(runtimeflag) do
			self.PrintLog(ent, flag, boneName, depth + 1)
		end
	elseif isnumber(runtimeflag) then
		local totalmsg = {}
		for flag, msg in pairs(self.__internal_FLAG_MSG) do
			if bit.band(runtimeflag, flag) == flag then 
				table.insert(totalmsg, msg) 
			end
		end
		if #totalmsg == 0 then return end
		print('============UPManip Log===========')
		print('entity:', ent)
		print('boneName:', boneName)
		print('code:', runtimeflag)
		print(table.concat(totalmsg, ', '))
	else
		print('Warn: unknown flags type, expect number or table, got', type(runtimeflag))
		return
	end
end


UPManip.BoneProxy = {}
UPManip.BoneProxy.__index = UPManip.BoneProxy


function UPManip.BoneProxy:LookupBone(ent, boneName)
	return ent:LookupBone(boneName)
end

function UPManip.BoneProxy:GetBoneMatrix(ent, boneName)
	local boneId = ent:LookupBone(boneName)
	if not boneId then return end
	return ent:GetBoneMatrix(boneId)
end

function UPManip.BoneProxy:LookupBone(boneName)

end

function UPManip.BoneProxy:GetParent(boneName)

end

function UPManip.BoneProxy:GetBoneName(boneId)
 
end


local ENTITY = FindMetaTable('Entity')

-- =========================== 实体骨骼操纵 ===========================

local SUCC_FLAG = 0x00
local ERR_FLAG_BONEID = 0x01
local ERR_FLAG_MATRIX = 0x02
local ERR_FLAG_SINGULAR = 0x04
local ERR_FLAG_PARENT = 0x08
local ERR_FLAG_PARENT_MATRIX = 0x10
local ERR_FLAG_PARENT_SINGULAR = 0x20
local CALL_FLAG_SET_POSITION = 0x40
local CALL_FLAG_SET_ANG = 0x80
local CALL_FLAG_SET_POS = 0x100
local CALL_FLAG_SET_SCALE = 0x200


local SUCC_FLAG = UPManip:__internal_ADD_FLAG_MSG('success')
local ERR_FLAG_MATRIX = UPManip:__internal_ADD_FLAG_MSG('can not find Matrix')
local ERR_FLAG_SINGULAR = UPManip:__internal_ADD_FLAG_MSG('Matrix is singular')

local ERR_FLAG_PARENT = UPManip:__internal_ADD_FLAG_MSG('can not find bone parent')
local ERR_FLAG_PARENT_MATRIX = UPManip:__internal_ADD_FLAG_MSG('can not find parent Matrix')
local ERR_FLAG_PARENT_SINGULAR = UPManip:__internal_ADD_FLAG_MSG('parent Matrix is singular')

function ENTITY:UPMaGetBoneMatrix(boneName, proxy)
	if proxy then
		return proxy:LookupBone(self, boneName)
	else
		local boneId = self:LookupBone(boneName)
		if not boneId then return nil, ERR_FLAG_BONEID end
		local mat = self:GetBoneMatrix(boneId)
		if not mat then return nil, ERR_FLAG_MATRIX end
		return mat, SUCC_FLAG
	end
end

function ENTITY:UPMaSetBonePosition(boneName, posw, angw, proxy) 
	-- 必须传入非奇异矩阵, 如果骨骼或父级的变换是奇异的, 则可能出现问题
	-- 在调用前最好使用 ent:SetupBones(), 否则可能获得错误数据
	-- 一般放在帧循环中
	-- 应该还能再优化

	if proxy and proxy.SetBonePosition then
		return proxy:SetBonePosition(self, boneName, posw, angw)
	end

	local boneId = self:LookupBone(boneName)
	if not boneId then return bit.bor(ERR_FLAG_BONEID, CALL_FLAG_SET_POSITION) end
	
	local curTransform = self:GetBoneMatrix(boneId)
	if not curTransform then return bit.bor(ERR_FLAG_MATRIX, CALL_FLAG_SET_POSITION) end
	
	local parentId = self:GetBoneParent(boneId)
	local parentTransform = parentId == -1 and self:GetWorldTransformMatrix() or self:GetBoneMatrix(parentId)
	if not parentTransform then return bit.bor(ERR_FLAG_PARENT, CALL_FLAG_SET_POSITION) end

	local curTransformInvert = curTransform:GetInverse()
	if not curTransformInvert then return bit.bor(ERR_FLAG_SINGULAR, CALL_FLAG_SET_POSITION) end

	local parentTransformInvert = parentTransform:GetInverse()
	if not parentTransformInvert then return bit.bor(ERR_FLAG_PARENT_SINGULAR, CALL_FLAG_SET_POSITION) end


	local curAngManip = Matrix()
	curAngManip:SetAngles(self:GetManipulateBoneAngles(boneId))
	
	local tarRotate = Matrix()
	tarRotate:SetAngles(angw)


	local newManipAng = (curAngManip * curTransformInvert * tarRotate):GetAngles()
	local newManipPos = parentTransformInvert
		* (posw - curTransform:GetTranslation() + parentTransform:GetTranslation())
		+ self:GetManipulateBonePosition(boneId)

	self:ManipulateBoneAngles(boneId, newManipAng)
	self:ManipulateBonePosition(boneId, newManipPos)

	return SUCC_FLAG
end

function ENTITY:UPMaSetBonePos(boneName, posw, proxy) 
	-- 必须传入非奇异矩阵, 如果骨骼或父级的变换是奇异的, 则可能出现问题
	-- 在调用前最好使用 ent:SetupBones(), 否则可能获得错误数据
	-- 一般放在帧循环中
	-- 应该还能再优化

	local boneId = self:LookupBone(boneName)
	if not boneId then return bit.bor(ERR_FLAG_BONEID, CALL_FLAG_SET_POS) end
	
	local curTransform = self:GetBoneMatrix(boneId)
	if not curTransform then return bit.bor(ERR_FLAG_MATRIX, CALL_FLAG_SET_POS) end
	
	local parentId = self:GetBoneParent(boneId)
	local parentTransform = parentId == -1 and self:GetWorldTransformMatrix() or self:GetBoneMatrix(parentId)
	if not parentTransform then return bit.bor(ERR_FLAG_PARENT, CALL_FLAG_SET_POS) end

	local parentTransformInvert = parentTransform:GetInverse()
	if not parentTransformInvert then return bit.bor(ERR_FLAG_PARENT_SINGULAR, CALL_FLAG_SET_POS) end

	local newManipPos = parentTransformInvert
		* (posw - curTransform:GetTranslation() + parentTransform:GetTranslation())
		+ self:GetManipulateBonePosition(boneId)

	self:ManipulateBonePosition(boneId, newManipPos)

	return SUCC_FLAG
end

function ENTITY:UPMaSetBoneAng(boneName, angw, proxy)
	-- 必须传入非奇异矩阵, 如果骨骼或父级的变换是奇异的, 则可能出现问题
	-- 在调用前最好使用 ent:SetupBones(), 否则可能获得错误数据
	-- 一般放在帧循环中
	-- 应该还能再优化

	local boneId = self:LookupBone(boneName)
	if not boneId then return bit.bor(ERR_FLAG_BONEID, CALL_FLAG_SET_ANG) end
	
	local curTransform = self:GetBoneMatrix(boneId)
	if not curTransform then return bit.bor(ERR_FLAG_MATRIX, CALL_FLAG_SET_ANG) end
	
	local curTransformInvert = curTransform:GetInverse()
	if not curTransformInvert then return bit.bor(ERR_FLAG_SINGULAR, CALL_FLAG_SET_ANG) end

	local curAngManip = Matrix()
	curAngManip:SetAngles(self:GetManipulateBoneAngles(boneId))
	
	local tarRotate = Matrix()
	tarRotate:SetAngles(angw)


	local newManipAng = (curAngManip * curTransformInvert * tarRotate):GetAngles()
	self:ManipulateBoneAngles(boneId, newManipAng)

	return SUCC_FLAG
end

function ENTITY:UPMaSetBoneScale(boneName, scale, proxy)
	local boneId = self:LookupBone(boneName)
	if not boneId then return bit.bor(ERR_FLAG_BONEID, CALL_FLAG_SET_SCALE) end
	self:ManipulateBoneScale(boneId, scale)
	return SUCC_FLAG
end

local CALL_FLAG_LERP_WORLD = 0x1000
local CALL_FLAG_LERP_LOCAL = 0x2000
local CALL_FLAG_SET_POSITION = 0x4000
local CALL_FLAG_SNAPSHOT = 0x8000
local ERR_FLAG_LERP_METHOD = 0x10000
local CALL_FLAG_SET_POS = 0x20000
local CALL_FLAG_SET_ANG = 0x40000
local CALL_FLAG_SET_SCALE = 0x80000