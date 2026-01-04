--[[
	作者:白狼
	2025 12 28

	此方法的使用门槛极高, 首先 ManipulateBonePosition 有距离限制, 限制为 128 个单位,
	所以如果想完成正确插值的话, 则必须在位置更新完成的那一帧, 
	所以想要完成正确插值, 最好单独加一个标志 + 回调来处理, 这样不容易导致混乱。

	由于这些函数常常在帧循环中, 加上计算略显密集 (串行), 所以很多的错误都是无声的, 这极大
	地增加了调试难度, 有点像GPU编程, 操, 我并不推荐使用这些。

	插值需要指定骨骼迭代器和其排序, ent:UPMaGetEntBonesFamilyLevel() 可以辅助排序,
	完成后再手动编码。为什么不写自动排序? 因为有些骨架虽然骨骼名相同, 但是节点关系混乱,
	比如 cw2 的 c_hand。

	这里的插值分为两种 世界空间插值(CALL_FLAG_LERP_WORLD) 和 局部空间插值(CALL_FLAG_LERP_LOCAL)
	如果从本质来看, 世界空间的插值可以看做一种特殊的局部空间插值, 只是将所有骨骼的父级都看作是 World,

	同时这里的 API 都是用骨骼名来指向操作的骨骼, 而不是 boneId, 这对编写、调试都有好处, 缺点是不能像
	数字索引那样高效地递归处理外部骨骼 (实体本身的父级等), 当然这里不需要, 又不是要操作机甲...

	所以这里不处理实体本身, 因为一旦处理, 为了保证逻辑的一致性就必须要处理外部骨骼, 而这太低效了, 代码
	的可读性和可维护性都要差很多, 还不如自行处理, 或者以后给UPManip加个拓展,
	如果临时需要, 则在骨骼迭代器中传入自定义处理器。

	所有涉及骨骼操纵的方法, 调用前建议执行 ent:SetupBones(), 确保获取到最新的骨骼矩阵数据, 避免计算异常。

--]]

local ENTITY = FindMetaTable('Entity')
local emptyTable = UPar.emptyTable
local zero = 1e-2

UPManip = UPManip or {}

local SUCC_FLAG = 0x00
local ERR_FLAG_BONEID = 0x01
local ERR_FLAG_MATRIX = 0x02
local ERR_FLAG_SINGULAR = 0x04

local ERR_FLAG_PARENT = 0x08
local ERR_FLAG_PARENT_MATRIX = 0x10
local ERR_FLAG_PARENT_SINGULAR = 0x20

local ERR_FLAG_TAR_BONEID = 0x40
local ERR_FLAG_TAR_MATRIX = 0x80
local ERR_FLAG_TAR_SINGULAR = 0x100

local ERR_FLAG_TAR_PARENT = 0x200
local ERR_FLAG_TAR_PARENT_MATRIX = 0x400
local ERR_FLAG_TAR_PARENT_SINGULAR = 0x800

local CALL_FLAG_LERP_WORLD = 0x1000
local CALL_FLAG_LERP_LOCAL = 0x2000
local CALL_FLAG_SET_POSITION = 0x4000
local CALL_FLAG_SNAPSHOT = 0x8000
local ERR_FLAG_LERP_METHOD = 0x10000
local CALL_FLAG_SET_POS = 0x20000
local CALL_FLAG_SET_ANG = 0x40000
local CALL_FLAG_SET_SCALE = 0x80000

local RUNTIME_FLAG_MSG = {
	[SUCC_FLAG] = nil,
	[ERR_FLAG_BONEID] = 'can not find boneId',
	[ERR_FLAG_MATRIX] = 'can not find Matrix',
	[ERR_FLAG_SINGULAR] = 'matrix is singular',

	[ERR_FLAG_PARENT] = 'can not find parent',
	[ERR_FLAG_PARENT_MATRIX] = 'can not find parent Matrix',
	[ERR_FLAG_PARENT_SINGULAR] = 'parent matrix is singular',
	
	[ERR_FLAG_TAR_BONEID] = 'can not find tarBoneId',
	[ERR_FLAG_TAR_MATRIX] = 'can not find tarBone Matrix',
	[ERR_FLAG_TAR_SINGULAR] = 'target matrix is singular',

	[ERR_FLAG_TAR_PARENT] = 'can not find tarBone parent',
	[ERR_FLAG_TAR_PARENT_MATRIX] = 'can not find tarBone parent Matrix',
	[ERR_FLAG_TAR_PARENT_SINGULAR] = 'target parent matrix is singular',
	[CALL_FLAG_LERP_LOCAL] = 'call: lerp in local space',
	[CALL_FLAG_LERP_WORLD] = 'call: lerp in world space',
	[CALL_FLAG_SET_POSITION] = 'call: set position',
	[CALL_FLAG_SNAPSHOT] = 'call: snapshot',
	[ERR_FLAG_LERP_METHOD] = 'invalid lerp method',
	[CALL_FLAG_SET_POS] = 'call: set pos',
	[CALL_FLAG_SET_ANG] = 'call: set angle',
	[CALL_FLAG_SET_SCALE] = 'call: set scale',
}

local function IsMatrixSingularFast(mat)
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

local function GetMatrixLocal(mat, parentMat, invert)
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


LocalPlayer().LookupBone = function(self, boneId)
	print(8888888)
end
LocalPlayer():LookupBone('sss')

function ENTITY:UPMaSetBonePosition(boneName, posw, angw) 
	-- 必须传入非奇异矩阵, 如果骨骼或父级的变换是奇异的, 则可能出现问题
	-- 在调用前最好使用 ent:SetupBones(), 否则可能获得错误数据
	-- 一般放在帧循环中
	-- 应该还能再优化

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

function ENTITY:UPMaSetBonePos(boneName, posw) 
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

function ENTITY:UPMaSetBoneAng(boneName, angw)
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

function ENTITY:UPMaSetBoneScale(boneName, scale)
	local boneId = self:LookupBone(boneName)
	if not boneId then return bit.bor(ERR_FLAG_BONEID, CALL_FLAG_SET_SCALE) end
	self:ManipulateBoneScale(boneId, scale)
	return SUCC_FLAG
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

local function GetBoneMatrixFromSnapshot(boneName, snapshotOrEnt)
	-- 一般在帧循环中调用, 所以不作验证
	if istable(snapshotOrEnt) then
		return snapshotOrEnt[boneName]
	end

	local boneId = snapshotOrEnt:LookupBone(boneName)
	if not boneId then return nil end
	return snapshotOrEnt:GetBoneMatrix(boneId)
end

function ENTITY:UPMaLerpBoneBatch(t, snapshotOrEnt, tarSnapshotOrEnt, boneMapping, boneIterator)
	-- 一般在帧循环中调用, 所以不作验证
	-- 在调用前最好使用 ent:SetupBones(), 否则可能获得错误数据
	-- 每帧都要更新

	local resultBatch = {}
	local flags = {}

	-- 还是搞点拦截吧，外部不好重算
	local UnpackMappingData = boneIterator and boneIterator.UnpackMappingData
	local LerpRangeAdjust = boneIterator and boneIterator.LerpRangeAdjust

	for _, mappingData in ipairs(boneMapping) do
		-- 添加一些动态特性吧
		mappingData = UnpackMappingData
			and UnpackMappingData(self, t, snapshotOrEnt, tarSnapshotOrEnt, mappingData) 
			or mappingData

		local boneName = mappingData.bone
		local tarBoneName = mappingData.tarBone or boneName
		local offsetMatrix = mappingData.offset
		local lerpMethod = mappingData.lerpMethod or CALL_FLAG_LERP_LOCAL

		-- 根节点只能使用世界空间插值
		local boneId = self:LookupBone(boneName)
		if not boneId then 
			flags[boneName] = bit.bor(ERR_FLAG_BONEID, lerpMethod)
			continue 
		end
		local parentId = self:GetBoneParent(boneId)
		lerpMethod = parentId == -1 and CALL_FLAG_LERP_WORLD or lerpMethod


		local initMatrix = GetBoneMatrixFromSnapshot(boneName, snapshotOrEnt)
		if not initMatrix then 
			flags[boneName] = bit.bor(ERR_FLAG_MATRIX, lerpMethod)
			continue
		end

		local finalMatrix = GetBoneMatrixFromSnapshot(tarBoneName, tarSnapshotOrEnt)
		if not finalMatrix then 
			flags[boneName] = bit.bor(ERR_FLAG_TAR_BONEID, lerpMethod)
			continue
		end

		if lerpMethod == CALL_FLAG_LERP_WORLD then	
			finalMatrix = offsetMatrix and finalMatrix * offsetMatrix or finalMatrix
			if LerpRangeAdjust then
				initMatrix, finalMatrix = LerpRangeAdjust(self, t, snapshotOrEnt, tarSnapshotOrEnt, initMatrix, finalMatrix, mappingData)
			end

			local result = Matrix()
			result:SetTranslation(LerpVector(t, initMatrix:GetTranslation(), finalMatrix:GetTranslation()))
			result:SetAngles(LerpAngle(t, initMatrix:GetAngles(), finalMatrix:GetAngles()))
			result:SetScale(LerpVector(t, initMatrix:GetScale(), finalMatrix:GetScale()))
			resultBatch[boneName] = result
			flags[boneName] = SUCC_FLAG

		elseif lerpMethod == CALL_FLAG_LERP_LOCAL then
			local parentName = mappingData.parent and mappingData.parent or self:GetBoneName(parentId)
			local tarParentName = mappingData.tarParent or parentName

			local parentMatrix = GetBoneMatrixFromSnapshot(parentName, snapshotOrEnt)
			if not parentMatrix then 
				flags[boneName] = bit.bor(ERR_FLAG_PARENT_MATRIX, lerpMethod)
				continue 
			end

			local tarParentMatrix = GetBoneMatrixFromSnapshot(tarParentName, tarSnapshotOrEnt)
			if not tarParentMatrix then 
				flags[boneName] = bit.bor(ERR_FLAG_TAR_PARENT_MATRIX, lerpMethod)
				continue 
			end

			if IsMatrixSingularFast(parentMatrix) then 
				flags[boneName] = bit.bor(ERR_FLAG_PARENT_SINGULAR, lerpMethod)
				continue 
			end

			local tarParentMatrixInvert = tarParentMatrix:GetInverse()
			if not tarParentMatrixInvert then 
				flags[boneName] = bit.bor(ERR_FLAG_TAR_PARENT_SINGULAR, lerpMethod)
				continue 
			end

			finalMatrix = parentMatrix * tarParentMatrixInvert * finalMatrix
			finalMatrix = offsetMatrix and finalMatrix * offsetMatrix or finalMatrix

			if LerpRangeAdjust then
				initMatrix, finalMatrix = LerpRangeAdjust(self, t, snapshotOrEnt, tarSnapshotOrEnt, initMatrix, finalMatrix, mappingData)
			end

			local result = Matrix()
			result:SetTranslation(LerpVector(t, initMatrix:GetTranslation(), finalMatrix:GetTranslation()))
			result:SetAngles(LerpAngle(t, initMatrix:GetAngles(), finalMatrix:GetAngles()))
			result:SetScale(LerpVector(t, initMatrix:GetScale(), finalMatrix:GetScale()))
			resultBatch[boneName] = result

			flags[boneName] = SUCC_FLAG
		else
			flags[boneName] = ERR_FLAG_LERP_METHOD
			continue
		end
	end

	return resultBatch, flags
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

function ENTITY:UPManipBoneBatch(snapshot, boneMapping, manipflag)
	-- 可以从 UPMaLerpBoneBatch 中获取插值后的快照, 
	-- 必须使用迭代器来遍历, 因为顺序有要求

	local runtimeflags = {}
	for _, mappingData in ipairs(boneMapping) do
		local boneName = mappingData.bone
		local data = snapshot[boneName]
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

function ENTITY:UPMaPrintErr(runtimeflag, boneName, depth)
	-- 不要使用嵌套表, 这里只做了简单防御
	depth = depth or 0
	if depth > 10 then return end

	if istable(runtimeflag) then
		for boneName, flag in pairs(runtimeflag) do
			self:UPMaPrintErr(flag, boneName, depth + 1)
		end
	elseif isnumber(runtimeflag) then
		local totalmsg = {}
		for flag, msg in pairs(RUNTIME_FLAG_MSG) do
			if bit.band(runtimeflag, flag) == flag then 
				table.insert(totalmsg, msg) 
			end
		end
		if #totalmsg == 0 then return end
		print('============UPManip Err===========')
		print('entity:', self)
		print('boneName:', boneName)
		print('errcode:', runtimeflag)
		print(table.concat(totalmsg, ', '))
	else
		print('Warn: unknown flags type, expect number or table, got', type(runtimeflag))
		return
	end
end

UPManip.LERP_METHOD = {LOCAL = CALL_FLAG_LERP_LOCAL, WORLD = CALL_FLAG_LERP_WORLD}
UPManip.RUNTIME_FLAG_MSG = RUNTIME_FLAG_MSG
UPManip.GetBoneMatrixFromSnapshot = GetBoneMatrixFromSnapshot
UPManip.GetMatrixLocal = GetMatrixLocal
UPManip.IsMatrixSingularFast = IsMatrixSingularFast
UPManip.InitBoneMapping = function(boneMapping)
	-- 主要是验证参数类型和初始化偏移矩阵
	-- parent 和 tarParent 字段仅对局部空间插值有效

	assert(istable(boneMapping), string.format('invalid boneMapping, expect table, got %s', type(boneMapping)))

	for _, mappingData in ipairs(boneMapping) do
		assert(istable(mappingData), string.format('boneMapping value is invalid, expect table, got %s', type(mappingData)))
		assert(isstring(mappingData.bone), string.format('field "bone" is invalid, expect string, got %s', type(mappingData.bone)))
		assert(isstring(mappingData.tarBone) or mappingData.tarBone == nil, string.format('field "tarBone" is invalid, expect (string or nil), got %s', type(mappingData.tarBone)))
		assert(isstring(mappingData.parent) or mappingData.parent == nil, string.format('field "parent" is invalid, expect (string or nil), got %s', type(mappingData.parent)))
		assert(isstring(mappingData.tarParent) or mappingData.tarParent == nil, string.format('field "tarParent" is invalid, expect (string or nil), got %s', type(mappingData.tarParent)))
		assert(isnumber(mappingData.lerpMethod) or mappingData.lerpMethod == nil, string.format('field "lerpMethod" is invalid, expect (number or nil), got %s', type(mappingData.lerpMethod)))

		if ismatrix(mappingData.offset) then
			continue
		end

		local offsetMatrix = nil
		local offsetAng = mappingData.ang
		local offsetPos = mappingData.pos
		local offsetScale = mappingData.scale

		assert(isangle(offsetAng) or offsetAng == nil, string.format('field "ang" is invalid, expect (angle or nil), got %s', type(offsetAng)))
		assert(isvector(offsetPos) or offsetPos == nil, string.format('field "pos" is invalid, expect (vector or nil), got %s', type(offsetPos)))
		assert(isvector(offsetScale) or offsetScale == nil, string.format('field "scale" is invalid, expect (vector or nil), got %s', type(offsetScale)))

		if isangle(offsetAng) then
			offsetMatrix = offsetMatrix or Matrix()
			offsetMatrix:SetAngles(offsetAng)
		end

		if isvector(offsetPos) then
			offsetMatrix = offsetMatrix or Matrix()
			offsetMatrix:SetTranslation(offsetPos)
		end

		if isvector(offsetScale) then
			offsetMatrix = offsetMatrix or Matrix()
			offsetMatrix:SetScale(offsetScale)
		end

		if offsetMatrix then
			mappingData.offset = offsetMatrix
		end
	end
end

concommand.Add('upmanip_test_world', function(ply)
	local pos = ply:GetPos()
	pos = pos + UPar.XYNormal(ply:GetAimVector()) * 100

	local mossman = ClientsideModel('models/mossman.mdl', RENDERGROUP_OTHER)
	local mossman2 = ClientsideModel('models/mossman.mdl', RENDERGROUP_OTHER)

	mossman:SetPos(pos)
	mossman2:SetPos(pos)

	local boneMapping = {
		{
			bone = 'Throw_Err_Example'
		},
		
		{
			bone = 'ValveBiped.Bip01_Pelvis',
			ang = Angle(0, 0, 90),
			lerpMethod = CALL_FLAG_LERP_WORLD,
		},

		{
			bone = 'ValveBiped.Bip01_Head1',
			ang = Angle(90, 10, 0),
			scale = Vector(2, 2, 2),
			lerpMethod = CALL_FLAG_LERP_WORLD,
		}
	}
	UPManip.InitBoneMapping(boneMapping)

	mossman:SetupBones()
	mossman2:SetupBones()

	local ang = 0
	timer.Create('upmanip_test_world', 0, 0, function()
		if not IsValid(mossman) or not IsValid(mossman2) then 
			timer.Remove('upmanip_test_world')
			return
		end

		mossman2:SetPos(pos + Vector(math.cos(ang) * 100, math.sin(ang) * 100, 0))
		mossman2:SetupBones()
		mossman:SetupBones()

		local lerpSnapshot, runtimeflags = mossman:UPMaLerpBoneBatch(
			0.1, mossman, mossman2, boneMapping)
		mossman:UPMaPrintErr(runtimeflags)
		local runtimeflag = mossman:UPManipBoneBatch(lerpSnapshot, 
			boneMapping, MANIP_MATRIX)
		mossman:UPMaPrintErr(runtimeflag)
		
		ang = ang + FrameTime()
	end)

	timer.Simple(5, function()
		if IsValid(mossman) then mossman:Remove() end
		if IsValid(mossman2) then mossman2:Remove() end
	end)
end)

concommand.Add('upmanip_test_local', function(ply)
	local pos = ply:GetPos()
	pos = pos + UPar.XYNormal(ply:GetAimVector()) * 100

	local pos2 = pos + Vector(0, 100, 0)

	local mossman = ClientsideModel('models/mossman.mdl', RENDERGROUP_OTHER)
	local mossman2 = ClientsideModel('models/gman_high.mdl', RENDERGROUP_OTHER)

	mossman:SetPos(pos)
	
	mossman2:SetPos(pos2)
	mossman2:ResetSequenceInfo()
	mossman2:SetPlaybackRate(1)
	mossman2:ResetSequence(mossman2:LookupSequence('crouch_reload_pistol'))

	local bones = {
		'ValveBiped.Bip01_Spine',
		'ValveBiped.Bip01_Spine1',
		'ValveBiped.Bip01_Spine2',
		'ValveBiped.Bip01_L_Clavicle',
		'ValveBiped.Bip01_L_UpperArm',
		'ValveBiped.Bip01_L_Forearm',
		'ValveBiped.Bip01_L_Hand',
		'ValveBiped.Bip01_R_Clavicle',
		'ValveBiped.Bip01_R_UpperArm',
		'ValveBiped.Bip01_R_Forearm',
		'ValveBiped.Bip01_R_Hand',
		'ValveBiped.Bip01_Neck1',
		'ValveBiped.Bip01_Head1'
	}

	local boneMapping = {}
	for i, boneName in ipairs(bones) do
		boneMapping[i] = {bone = boneName}
	end

	UPManip.InitBoneMapping(boneMapping)

	mossman:SetupBones()
	mossman2:SetupBones()

	local ang = 0
	timer.Create('upmanip_test_local', 0, 0, function()
		if not IsValid(mossman) or not IsValid(mossman2) then 
			timer.Remove('upmanip_test_local')
			return
		end

		mossman2:SetCycle((mossman2:GetCycle() + FrameTime()) % 1)
		mossman2:SetupBones()

		mossman:SetupBones()

		local lerpSnapshot, runtimeflags = mossman:UPMaLerpBoneBatch(
			0.1, mossman, mossman2, boneMapping)
		mossman:UPMaPrintErr(runtimeflags)
		local runtimeflag = mossman:UPManipBoneBatch(lerpSnapshot, 
			boneMapping, MANIP_MATRIX)
		mossman:UPMaPrintErr(runtimeflag)
		
		ang = ang + FrameTime()
	end)
		
	timer.Simple(5, function()
		if IsValid(mossman) then mossman:Remove() end
		if IsValid(mossman2) then mossman2:Remove() end
	end)
end)
