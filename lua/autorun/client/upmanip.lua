--[[
	作者:白狼
	2025 12 28

	此方法的使用门槛极高, 首先 ManipulateBonePosition 有距离限制, 限制为 128 个单位,
	所以如果想完成正确插值的话, 则必须在位置更新完成的那一帧, 
	所以想要完成正确插值, 最好单独加一个标志 + 回调来处理, 这样不容易导致混乱。

	由于这些函数常常在帧循环中, 加上计算略显密集 (串行), 所以很多的错误都是无声的, 这极大
	地增加了调试难度, 有点像GPU编程, 操, 我并不推荐使用这些。

	想要完成动作插值需要指定要操作的骨骼列表, 顺序必须正确, 从根骨骼开始往下。

	这里的插值分为两种 世界空间插值 和 局部空间插值
	如果从本质来看, 世界空间的插值可以看做一种特殊的局部空间插值, 只是将所有骨骼的父级都看作是 World.

	同时这里的 API 都是用骨骼名来指向操作的骨骼, 而不是 boneId, 这对编写、调试都有好处, 缺点是不能像
	数字索引那样高效地递归处理外部骨骼 (实体本身的父级等), 如果需要处理外部骨骼详见 UPManip_ext.lua

	操作骨骼前最好先执行 ent:SetupBones(), 确保获取到最新的数据, 避免计算异常。

	同时这里引入了两个概念, 一个是实体代理器 (UPBoneProxy) 和快照 (UPSnapshot), 
	实体代理器可以实现动态扩张骨骼集, 而快照的用处是缓存已有的骨骼矩阵，特别是大量求逆的场景, 
	并且它的数据接口和实体是一样的，这样的话就不需要加入繁琐的类型判断。

	注意: 对于快照, 代理器只在初始化的时候有作用, 插值时无效, 我举个例子就很清晰了，
		假如代理器对快照其他时刻有效:
		我对 cw_hand 生成一个快照, 我传入的是 c_hand 的骨骼名, 然后我使用代理器做一个骨骼映射
		然后插值的时候直接用 c_hand 的骨骼名就能访问数据, 如果使用了代理器反而会错, 这样的话
		开发者必须手动管理好代理器和快照, 这就会导致代码异常混乱, 所以我会让代理器在其他时刻无效

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
    local targetFlag = flag or 1
    local originalFlag = targetFlag

	local succ = false
	for i = 0, 31 do
		if not self.__internal_FLAG_MSG[targetFlag] then
			succ = true
			break
		end
		targetFlag = bit.lshift(targetFlag, 1)
	end

	if not succ then
		error('所有标志位都被占用了, 自己改:' .. msg)
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

local ENTITY = FindMetaTable('Entity')

-- ================================== 操纵层 ===========================
-- 我要说明一点, 快照同样拥有这些方法, 但是会报错, 因为快照是只读的
-- ================================== 操纵层 ===========================
local SUCC_FLAG = UPManip:__internal_ADD_FLAG_MSG('success')
local ERR_FLAG_BONEID = UPManip:__internal_ADD_FLAG_MSG('can not find bone id')
local ERR_FLAG_NO_MATRIX = UPManip:__internal_ADD_FLAG_MSG('can not find Matrix')
local ERR_FLAG_MATRIX_SINGULAR = UPManip:__internal_ADD_FLAG_MSG('Matrix is singular')
local ERR_FLAG_NO_PARENT = UPManip:__internal_ADD_FLAG_MSG('can not find bone parent')
local ERR_FLAG_NO_PARENT_MATRIX = UPManip:__internal_ADD_FLAG_MSG('can not find parent Matrix')
local ERR_FLAG_PARENT_SINGULAR = UPManip:__internal_ADD_FLAG_MSG('parent Matrix is singular')


local ERR_FLAG_NO_INIT_MATRIX = UPManip:__internal_ADD_FLAG_MSG('can not find init Matrix')
local ERR_FLAG_INIT_SINGULAR = UPManip:__internal_ADD_FLAG_MSG('init Matrix is singular')
local ERR_FLAG_NO_INIT_PARENT_MATRIX = UPManip:__internal_ADD_FLAG_MSG('can not find init parent Matrix')
local ERR_FLAG_INIT_PARENT_SINGULAR = UPManip:__internal_ADD_FLAG_MSG('init parent Matrix is singular')


local ERR_FLAG_NO_FINAL_MATRIX = UPManip:__internal_ADD_FLAG_MSG('can not find final Matrix')
local ERR_FLAG_FINAL_SINGULAR = UPManip:__internal_ADD_FLAG_MSG('final Matrix is singular')
local ERR_FLAG_NO_FINAL_PARENT_MATRIX = UPManip:__internal_ADD_FLAG_MSG('can not find final parent Matrix')
local ERR_FLAG_FINAL_PARENT_SINGULAR = UPManip:__internal_ADD_FLAG_MSG('final parent Matrix is singular')


local STACK_FLAG_LERP_WORLD = UPManip:__internal_ADD_FLAG_MSG('call lerp world')
local STACK_FLAG_LERP_LOCAL = UPManip:__internal_ADD_FLAG_MSG('call lerp local')
local STACK_FLAG_SET_POSITION = UPManip:__internal_ADD_FLAG_MSG('call set position')
local STACK_FLAG_SET_POS = UPManip:__internal_ADD_FLAG_MSG('call set position')
local STACK_FLAG_SET_ANG = UPManip:__internal_ADD_FLAG_MSG('call set angle')
local STACK_FLAG_SET_SCALE = UPManip:__internal_ADD_FLAG_MSG('call set scale')
local STACK_FLAG_SET_MATRIX = UPManip:__internal_ADD_FLAG_MSG('call set matrix')


function ENTITY:UPMaSetBonePosition(boneName, posw, angw, proxy) 
	-- 必须传入非奇异矩阵, 如果骨骼或父级的变换是奇异的, 则可能出现问题
	-- 在调用前最好使用 ent:SetupBones(), 否则可能获得错误数据
	-- 一般放在帧循环中
	-- 应该还能再优化

	if proxy and proxy.SetPosition then
		return proxy:SetPosition(self, boneName, posw, angw)
	end

	local boneId = self:LookupBone(boneName)
	if not boneId then return bit.bor(ERR_FLAG_BONEID, STACK_FLAG_SET_POSITION) end
	
	local curTransform = self:GetBoneMatrix(boneId)
	if not curTransform then return bit.bor(ERR_FLAG_NO_MATRIX, STACK_FLAG_SET_POSITION) end
	
	local parentId = self:GetBoneParent(boneId)
	local parentTransform = parentId == -1 and self:GetWorldTransformMatrix() or self:GetBoneMatrix(parentId)
	if not parentTransform then return bit.bor(ERR_FLAG_NO_PARENT, STACK_FLAG_SET_POSITION) end

	local curTransformInvert = curTransform:GetInverse()
	if not curTransformInvert then return bit.bor(ERR_FLAG_MATRIX_SINGULAR, STACK_FLAG_SET_POSITION) end

	local parentTransformInvert = parentTransform:GetInverse()
	if not parentTransformInvert then return bit.bor(ERR_FLAG_PARENT_SINGULAR, STACK_FLAG_SET_POSITION) end


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

	if proxy and proxy.SetPos then
		return proxy:SetPos(self, boneName, posw)
	end

	local boneId = self:LookupBone(boneName)
	if not boneId then return bit.bor(ERR_FLAG_BONEID, STACK_FLAG_SET_POS) end
	
	local curTransform = self:GetBoneMatrix(boneId)
	if not curTransform then return bit.bor(ERR_FLAG_NO_MATRIX, STACK_FLAG_SET_POS) end
	
	local parentId = self:GetBoneParent(boneId)
	local parentTransform = parentId == -1 and self:GetWorldTransformMatrix() or self:GetBoneMatrix(parentId)
	if not parentTransform then return bit.bor(ERR_FLAG_NO_PARENT, STACK_FLAG_SET_POS) end

	local parentTransformInvert = parentTransform:GetInverse()
	if not parentTransformInvert then return bit.bor(ERR_FLAG_PARENT_SINGULAR, STACK_FLAG_SET_POS) end

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

	if proxy and proxy.SetAng then
		return proxy:SetAng(self, boneName, angw)
	end

	local boneId = self:LookupBone(boneName)
	if not boneId then return bit.bor(ERR_FLAG_BONEID, STACK_FLAG_SET_ANG) end
	
	local curTransform = self:GetBoneMatrix(boneId)
	if not curTransform then return bit.bor(ERR_FLAG_NO_MATRIX, STACK_FLAG_SET_ANG) end
	
	local curTransformInvert = curTransform:GetInverse()
	if not curTransformInvert then return bit.bor(ERR_FLAG_MATRIX_SINGULAR, STACK_FLAG_SET_ANG) end

	local curAngManip = Matrix()
	curAngManip:SetAngles(self:GetManipulateBoneAngles(boneId))
	
	local tarRotate = Matrix()
	tarRotate:SetAngles(angw)


	local newManipAng = (curAngManip * curTransformInvert * tarRotate):GetAngles()
	self:ManipulateBoneAngles(boneId, newManipAng)

	return SUCC_FLAG
end

function ENTITY:UPMaSetBoneScale(boneName, scale, proxy)
	if proxy and proxy.SetScale then
		return proxy:SetScale(self, boneName, scale)
	end

	local boneId = self:LookupBone(boneName)
	if not boneId then return bit.bor(ERR_FLAG_BONEID, STACK_FLAG_SET_SCALE) end
	self:ManipulateBoneScale(boneId, scale)
	return SUCC_FLAG
end

local MANIP_POS = 0x01
local MANIP_ANG = 0x02
local MANIP_SCALE = 0x04
local MANIP_POSITION = bit.bor(MANIP_POS, MANIP_ANG)
local MANIP_MATRIX = bit.bor(MANIP_POS, MANIP_ANG, MANIP_SCALE)

UPManip.MANIP_FLAG = {
	MANIP_POS = MANIP_POS,
	MANIP_ANG = MANIP_ANG,
	MANIP_SCALE = MANIP_SCALE,
	MANIP_POSITION = MANIP_POSITION,
	MANIP_MATRIX = MANIP_MATRIX,
}

function ENTITY:UPManipBoneBatch(resultBatch, boneList, manipflag, proxy)
	local runtimeflags = {}

	for _, boneName in ipairs(boneList) do
		local data = resultBatch[boneName]
		if not data then continue end
		local runtimeflag = SUCC_FLAG
		
		local newPos = data:GetTranslation()
		local newAng = data:GetAngles()
		local newScale = data:GetScale()

		if bit.band(manipflag, MANIP_POSITION) == MANIP_POSITION then
			runtimeflag = bit.bor(runtimeflag, self:UPMaSetBonePosition(boneName, newPos, newAng))
		elseif bit.band(manipflag, MANIP_POS) == MANIP_POS then
			runtimeflag = bit.bor(runtimeflag, self:UPMaSetBonePos(boneName, newPos))
		elseif bit.band(manipflag, MANIP_ANG) == MANIP_ANG then
			runtimeflag = bit.bor(runtimeflag, self:UPMaSetBoneAng(boneName, newAng))
		end

		if bit.band(manipflag, MANIP_SCALE) == MANIP_SCALE then
			runtimeflag = bit.bor(runtimeflag, self:UPMaSetBoneScale(boneName, newScale))
		end

		runtimeflags[boneName] = runtimeflag
	end

	return runtimeflags
end
-- ================================== 数据层 ===========================
-- 快照同样拥有这些方法, 但是代理器对快照无效, 具体看开头的注释
-- ================================== 数据层 ===========================
-- 这些标志位将说明获取矩阵的场景
local INIT = 0x01
local FINAL = 0x02
local LERP_WORLD = 0x04
local LERP_LOCAL = 0x08
local SNAPSHOT = 0x10
local CUR = 0x20
local INIT_LERP_WORLD = bit.bor(INIT, LERP_WORLD)
local FINAL_LERP_WORLD = bit.bor(FINAL, LERP_WORLD)
local INIT_LERP_LOCAL = bit.bor(INIT, LERP_LOCAL)
local FINAL_LERP_LOCAL = bit.bor(FINAL, LERP_LOCAL)
// local CUR_LERP_WORLD = bit.bor(CUR, LERP_WORLD)
local CUR_LERP_LOCAL = bit.bor(CUR, LERP_LOCAL)

UPManip.GET_MATRIX_FLAG = {
	INIT = INIT,
	FINAL = FINAL,
	CUR = CUR,
	LERP_WORLD = LERP_WORLD,
	LERP_LOCAL = LERP_LOCAL,
	INIT_LERP_WORLD = INIT_LERP_WORLD,
	FINAL_LERP_WORLD = FINAL_LERP_WORLD,
	INIT_LERP_LOCAL = INIT_LERP_LOCAL,
	FINAL_LERP_LOCAL = FINAL_LERP_LOCAL,

	// CUR_LERP_WORLD = CUR_LERP_WORLD, -- 没有这个场景
	CUR_LERP_LOCAL = CUR_LERP_LOCAL,
	-- 快照
	SNAPSHOT = SNAPSHOT,
}


function ENTITY:UPMaGetBoneMatrix(boneName, proxy, mode)
	if proxy then
		return proxy:GetMatrix(self, boneName, mode)
	else
		local boneId = self:LookupBone(boneName)
		if not boneId then return nil end
		return self:GetBoneMatrix(boneId)
	end
end

function ENTITY:UPMaGetParentMatrix(boneName, proxy, mode)
	if proxy then
		return proxy:GetParentMatrix(self, boneName, mode)
	else
		local boneId = self:LookupBone(boneName)
		if not boneId then return nil end
		local parentId = self:GetBoneParent(boneId)
		if not parentId then return nil end
		return self:GetBoneMatrix(parentId)
	end
end

function ENTITY:UPMaLerpBoneWorld(boneName, t, ent1, ent2, proxy1, proxy2)
	-- 实际上 ent1、ent2 的类型不一定要是实体, 也可以是 UPSnapshot
	-- 一般在 UPMaLerpBoneWorldBatch 中调用, 所以不作验证
	-- 在调用前最好使用 ent:SetupBones(), 否则可能获得错误数据
	-- 每帧都要更新

	local initMatrix = ent1:UPMaGetBoneMatrix(boneName, proxy1, INIT_LERP_WORLD)
	if not initMatrix then return nil, bit.bor(ERR_FLAG_NO_INIT_MATRIX, STACK_FLAG_LERP_WORLD) end

	local finalMatrix = ent2:UPMaGetBoneMatrix(boneName, proxy2, FINAL_LERP_WORLD)
	if not finalMatrix then return nil, bit.bor(ERR_FLAG_NO_FINAL_MATRIX, STACK_FLAG_LERP_WORLD) end

	local result = Matrix()
	result:SetTranslation(LerpVector(t, initMatrix:GetTranslation(), finalMatrix:GetTranslation()))
	result:SetAngles (LerpAngle(t, initMatrix:GetAngles(), finalMatrix:GetAngles()))
	result:SetScale(LerpVector(t, initMatrix:GetScale(), finalMatrix:GetScale()))
	
	return result, SUCC_FLAG
end

function ENTITY:UPMaLerpBoneLocal(boneName, t, ent1, ent2, proxy1, proxy2, proxySelf)
	-- 实际上 ent1、ent2 的类型不一定要是实体, 也可以是 UPSnapshot
	-- 一般在 UPMaLerpBoneLocalBatch 中调用, 所以不作验证
	-- 在调用前最好使用 ent:SetupBones(), 否则可能获得错误数据
	-- 每帧都要更新

	-- 注意, 这里用的是代理父级和 UPMaGetBonexxx 系列不同, 看log的栈来辨别
	local curParentMatrix = self:UPMaGetParentMatrix(boneName, proxySelf, CUR_LERP_LOCAL)
	if not curParentMatrix then return nil, bit.bor(ERR_FLAG_NO_PARENT, STACK_FLAG_LERP_LOCAL) end

	-- 对于快照可以使用缓存
	local initMatrixLocal = ent1.GetBoneMatrixLocal and ent1:GetBoneMatrixLocal(boneName) or nil
	if not initMatrixLocal then
		local initMatrix = ent1:UPMaGetBoneMatrix(boneName, proxy1, INIT_LERP_LOCAL)
		if not initMatrix then return nil, bit.bor(ERR_FLAG_NO_INIT_MATRIX, STACK_FLAG_LERP_LOCAL) end

		local initParentMatrixInvert = ent1:UPMaGetParentMatrix(boneName, proxy1, INIT_LERP_LOCAL)
		if not initParentMatrixInvert then return nil, bit.bor(ERR_FLAG_NO_INIT_PARENT_MATRIX, STACK_FLAG_LERP_LOCAL) end
		local notSingular = initParentMatrixInvert:Invert()
		if not notSingular then return nil, bit.bor(ERR_FLAG_INIT_PARENT_SINGULAR, STACK_FLAG_LERP_LOCAL) end

		initMatrixLocal = initParentMatrixInvert * initMatrix
	end
	
	local finalMatrixLocal = ent2.GetBoneMatrixLocal and ent2:GetBoneMatrixLocal(boneName) or nil
	if not finalMatrixLocal then
		local finalMatrix = ent2:UPMaGetBoneMatrix(boneName, proxy2, FINAL_LERP_LOCAL)
		if not finalMatrix then return nil, bit.bor(ERR_FLAG_NO_FINAL_MATRIX, STACK_FLAG_LERP_LOCAL) end

		local finalParentMatrixInvert = ent2:UPMaGetParentMatrix(boneName, proxy2, FINAL_LERP_LOCAL)
		if not finalParentMatrixInvert then return nil, bit.bor(ERR_FLAG_NO_FINAL_PARENT_MATRIX, STACK_FLAG_LERP_LOCAL) end
		local notSingular = finalParentMatrixInvert:Invert()
		if not notSingular then return nil, bit.bor(ERR_FLAG_FINAL_PARENT_SINGULAR, STACK_FLAG_LERP_LOCAL) end

		finalMatrixLocal = finalParentMatrixInvert * finalMatrix
	end

	-- 起始局部插值可以直接算的, 但是为了数据一致性还是多算一个, 否则局部变换非人类, 外部要改还是要算
	local result = Matrix()
	result:SetTranslation(LerpVector(t, initMatrixLocal:GetTranslation(), finalMatrixLocal:GetTranslation()))
	result:SetAngles (LerpAngle(t, initMatrixLocal:GetAngles(), finalMatrixLocal:GetAngles()))
	result:SetScale(LerpVector(t, initMatrixLocal:GetScale(), finalMatrixLocal:GetScale()))
	result = curParentMatrix * result

	return result, SUCC_FLAG
end

function ENTITY:UPMaLerpBoneWorldBatch(boneList, t, ent1, ent2, proxy, proxy2)
	-- 一般在帧循环中调用, 所以不作太多验证
	-- 在调用前最好使用 ent:SetupBones(), 否则可能获得错误数据
	-- 每帧都要更新
	assert(isnumber(t), 't must be a number')
	assert(istable(boneList), 'boneList must be a table')

	local resultBatch = {}
	local flags = {}

	for _, boneName in ipairs(boneList) do
		local result, flag = self:UPMaLerpBoneWorld(boneName, t, ent1, ent2, proxy, proxy2)
		resultBatch[boneName] = result
		flags[boneName] = flag
	end

	return resultBatch, flags
end

function ENTITY:UPMaLerpBoneLocalBatch(boneList, t, ent1, ent2, proxy, proxy2, proxySelf)
	-- 一般在帧循环中调用, 所以不作太多验证
	-- 在调用前最好使用 ent:SetupBones(), 否则可能获得错误数据
	-- 每帧都要更新
	assert(isnumber(t), 't must be a number')
	assert(istable(boneList), 'boneList must be a table')

	local resultBatch = {}
	local flags = {}

	for _, boneName in ipairs(boneList) do
		local result, flag = self:UPMaLerpBoneLocal(boneName, t, ent1, ent2, proxy, proxy2, proxySelf)
		resultBatch[boneName] = result
		flags[boneName] = flag
	end

	return resultBatch, flags
end


function ENTITY:UPMaPrintLog(runtimeflag, boneName, depth)
	-- 不要使用嵌套表, 这里只做了简单防御
	depth = depth or 0
	if depth > 10 then return end

	if istable(runtimeflag) then
		for boneName, flag in pairs(runtimeflag) do
			self:UPMaPrintLog(flag, boneName, depth + 1)
		end
	elseif isnumber(runtimeflag) then
		local totalmsg = {}
		for flag, msg in pairs(UPManip.__internal_FLAG_MSG) do
			if bit.band(runtimeflag, flag) == flag then table.insert(totalmsg, msg) end
		end
		if #totalmsg == 0 then return end
		print('============UPManip Log===========')
		print('entity:', self)
		print('boneName:', boneName)
		print('code:', runtimeflag)
		print(table.concat(totalmsg, ', '))
	else
		print('Warn: unknown flags type, expect number or table, got', type(runtimeflag))
		return
	end
end
-- ================================== 快照类 ===========================

UPSnapshot = {}
UPSnapshot.__index = UPSnapshot

function UPSnapshot:New(ent, boneList, proxy, withLocal)
	-- 需要在外部调用 ent:SetupBones()
	assert(isbool(withLocal), 'expect withLocal to be a boolean')
	assert(istable(boneList), 'expect boneList to be a table')
	assert(isentity(ent) and ent:IsValid(), 'expect ent to be a valid entity')

    local self = setmetatable({}, UPSnapshot)
    self.MatTbl = {}
	self.MatTblLocal = withLocal and {} or nil
	self.MatParentTbl = {}

	for _, boneName in ipairs(boneList) do
		assert(isstring(boneName), 'expect boneName to be a string')
		self.MatTbl[boneName] = ent:UPMaGetBoneMatrix(boneName, proxy, SNAPSHOT)
		if not withLocal then continue end

		-- 这里直接缓存, 把错误推到奇异去处理
		local curParentMatrix = ent:UPMaGetParentMatrix(boneName, proxy, SNAPSHOT)
		self.MatParentTbl[boneName] = curParentMatrix
		if not curParentMatrix then continue end

		local curParentMatrixInvert = curParentMatrix:GetInverse()
		if not curParentMatrixInvert then continue end
		self.MatTblLocal[boneName] = curParentMatrixInvert * self.MatTbl[boneName]
	end

    return self
end

UPSnapshot.UPMaLerpBoneWorld = ENTITY.UPMaLerpBoneWorld
UPSnapshot.UPMaLerpBoneLocal = ENTITY.UPMaLerpBoneLocal
UPSnapshot.UPMaLerpBoneWorldBatch = ENTITY.UPMaLerpBoneWorldBatch
UPSnapshot.UPMaLerpBoneLocalBatch = ENTITY.UPMaLerpBoneLocalBatch

function UPSnapshot:GetBoneMatrixLocal(boneName)
	if not self.MatTblLocal then
		ErrorNoHaltWithStack('you can not do GetBoneMatrixLocal on a snapshot without local cache')
	else
		return self.MatTblLocal[boneName]
	end
end

function UPSnapshot:UPMaGetBoneMatrix(boneName)
	return self.MatTbl[boneName]
end

function UPSnapshot:UPMaGetParentMatrix(boneName)
	return self.MatParentTbl[boneName]
end

function UPSnapshot:UPMaSetBonePosition() 
	ErrorNoHaltWithStack('you can not do UPMaSetBonePosition on a snapshot')
end

function UPSnapshot:UPMaSetBonePos() 
	ErrorNoHaltWithStack('you can not do UPMaSetBonePos on a snapshot')
end

function UPSnapshot:UPMaSetBoneAng()
	ErrorNoHaltWithStack('you can not do UPMaSetBoneAng on a snapshot')
end

function UPSnapshot:UPMaSetBoneScale()
	ErrorNoHaltWithStack('you can not do UPMaSetBoneScale on a snapshot')
end

-- ================================== 默认代理器 ===========================
-- 这里把根骨骼扩张到实体本身
-- ================================== 默认代理器 ===========================
UPManip.DefaultPlayerProxy = {}
UPManip.DefaultPlayerProxy.Name = '默认玩家骨骼代理'

function UPManip.DefaultPlayerProxy:SetPosition(ent, boneName, posw, angw)
	if boneName == 'SELF' then
		self:SetPos(posw)
		self:SetAngles(angw)
		return SUCC_FLAG
	else
		return ent:UPMaSetBonePosition(boneName, posw, angw)
	end
end

function UPManip.DefaultPlayerProxy:SetPos(ent, boneName, posw)
	if boneName == 'SELF' then
		self:SetPos(posw)
		return SUCC_FLAG
	else
		return ent:UPMaSetBonePos(boneName, posw)
	end
end

function UPManip.DefaultPlayerProxy:SetAng(ent, boneName, angw)
	if boneName == 'SELF' then
		self:SetAngles(angw)
		return SUCC_FLAG
	else
		return ent:UPMaSetBoneAng(boneName, angw)
	end
end

function UPManip.DefaultPlayerProxy:GetMatrix(ent, boneName, mode)
	if boneName == 'SELF' then
		return ent:GetWorldTransformMatrix()
	else
		return ent:UPMaGetBoneMatrix(boneName)
	end
end

function UPManip.DefaultPlayerProxy:GetParentMatrix(ent, boneName, mode)
	if boneName == 'SELF' then
		return nil
	else
		local boneId = ent:LookupBone(boneName)
		if not boneId then return nil end
		local parentId = ent:GetBoneParent(boneId)
		return parentId == -1 and ent:GetWorldTransformMatrix() or ent:GetBoneMatrix(parentId) 
	end
end

-- ================================== 示例 ===========================

concommand.Add('upmanip_test_world', function(ply)
	local pos = ply:GetPos()
	pos = pos + UPar.XYNormal(ply:GetAimVector()) * 100

	local mossman = ClientsideModel('models/mossman.mdl', RENDERGROUP_OTHER)
	local mossman2 = ClientsideModel('models/mossman.mdl', RENDERGROUP_OTHER)

	mossman:SetPos(pos)
	mossman2:SetPos(pos)

	local boneList = {
		'ValveBiped.Bip01_Head1'
	}
	local proxy = UPManip.DefaultPlayerProxy

	local ang = 0
	timer.Create('upmanip_test_world', 0, 0, function()
		if not IsValid(mossman) or not IsValid(mossman2) then 
			timer.Remove('upmanip_test_world')
			return
		end

		mossman2:SetPos(pos + Vector(math.cos(ang) * 100, math.sin(ang) * 100, 0))
		mossman2:SetupBones()
		mossman:SetupBones()

		local resultBatch, runtimeflags = mossman:UPMaLerpBoneWorldBatch(
			boneList,
			0.1, 
			mossman, 
			mossman2)
		mossman:UPMaPrintLog(runtimeflags)

		local runtimeflag = mossman:UPManipBoneBatch(
			resultBatch, 
			boneList, 
			UPManip.MANIP_FLAG.MANIP_MATRIX,
			proxy
		)

		mossman:UPMaPrintLog(runtimeflag)
		
		ang = ang + FrameTime()
	end)

	timer.Simple(5, function()
		if IsValid(mossman) then mossman:Remove() end
		if IsValid(mossman2) then mossman2:Remove() end
	end)
end)

// concommand.Add('upmanip_test_local', function(ply)
// 	local pos = ply:GetPos()
// 	pos = pos + UPar.XYNormal(ply:GetAimVector()) * 100

// 	local pos2 = pos + Vector(0, 100, 0)

// 	local mossman = ClientsideModel('models/mossman.mdl', RENDERGROUP_OTHER)
// 	local mossman2 = ClientsideModel('models/gman_high.mdl', RENDERGROUP_OTHER)

// 	mossman:SetPos(pos)
	
// 	mossman2:SetPos(pos2)
// 	mossman2:ResetSequenceInfo()
// 	mossman2:SetPlaybackRate(1)
// 	mossman2:ResetSequence(mossman2:LookupSequence('crouch_reload_pistol'))

// 	local bones = {
// 		'ValveBiped.Bip01_Spine',
// 		'ValveBiped.Bip01_Spine1',
// 		'ValveBiped.Bip01_Spine2',
// 		'ValveBiped.Bip01_L_Clavicle',
// 		'ValveBiped.Bip01_L_UpperArm',
// 		'ValveBiped.Bip01_L_Forearm',
// 		'ValveBiped.Bip01_L_Hand',
// 		'ValveBiped.Bip01_R_Clavicle',
// 		'ValveBiped.Bip01_R_UpperArm',
// 		'ValveBiped.Bip01_R_Forearm',
// 		'ValveBiped.Bip01_R_Hand',
// 		'ValveBiped.Bip01_Neck1',
// 		'ValveBiped.Bip01_Head1'
// 	}

// 	local boneIterator = {}
// 	for i, boneName in ipairs(bones) do
// 		boneIterator[i] = {bone = boneName}
// 	end

// 	UPManip.InitBoneIterator(boneIterator)

// 	mossman:SetupBones()
// 	mossman2:SetupBones()

// 	local ang = 0
// 	timer.Create('upmanip_test_local', 0, 0, function()
// 		if not IsValid(mossman) or not IsValid(mossman2) then 
// 			timer.Remove('upmanip_test_local')
// 			return
// 		end

// 		mossman2:SetCycle((mossman2:GetCycle() + FrameTime()) % 1)
// 		mossman2:SetupBones()

// 		mossman:SetupBones()

// 		local lerpSnapshot, runtimeflags = mossman:UPMaLerpBoneBatch(
// 			0.1, mossman, mossman2, boneIterator)
// 		mossman:UPMaPrintErr(runtimeflags)
// 		local runtimeflag = mossman:UPManipBoneBatch(lerpSnapshot, 
// 			boneIterator, MANIP_MATRIX)
// 		mossman:UPMaPrintErr(runtimeflag)
		
// 		ang = ang + FrameTime()
// 	end)
		
// 	timer.Simple(5, function()
// 		if IsValid(mossman) then mossman:Remove() end
// 		if IsValid(mossman2) then mossman2:Remove() end
// 	end)
// end)
