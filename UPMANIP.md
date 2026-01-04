# UPManip 骨骼操纵
使用控制台指令 `upmanip_test_world` 或 `upmanip_test_local` 可以看到演示效果。

```note
注意: 这是一个测试性模块, 不建议在生产环境中使用。

这些都很难用, 简直一坨屎。

此方法的使用门槛极高, 首先 ManipulateBonePosition 有距离限制, 限制为 128 个单位,
所以如果想完成正确插值的话, 则必须在位置更新完成的那一帧, 
所以想要完成正确插值, 最好单独加一个标志 + 回调来处理, 这样不容易导致混乱。

由于这些函数常常在帧循环中, 加上计算略显密集 (串行), 所以很多的错误都是无声的, 这极大
地增加了调试难度, 有点像GPU编程, 操, 我并不推荐使用这些。

插值需要指定骨骼迭代器和其排序, ent:UPMaGetEntBonesFamilyLevel() 可以辅助排序,
完成后再手动编码。为什么不写自动排序? 因为有些骨架虽然骨骼名相同, 但是节点关系混乱,
比如 cw2 的 c_hand。

这里的插值分为两种 世界空间插值（CALL_FLAG_LERP_WORLD） 和 局部空间插值（CALL_FLAG_LERP_LOCAL）
如果从本质来看, 世界空间的插值可以看做一种特殊的局部空间插值, 只是将所有骨骼的父级都看作是 World,

同时这里的 API 都是用骨骼名来指向操作的骨骼, 而不是 boneId, 这对编写、调试都有好处, 缺点是不能像
数字索引那样高效地递归处理外部骨骼 (实体本身的父级等), 当然这里不需要, 又不是要操作机甲...

所以这里不处理实体本身, 因为一旦处理, 为了保证逻辑的一致性就必须要处理外部骨骼, 而这太低效了, 代码
的可读性和可维护性都要差很多, 还不如自行处理, 或者以后给UPManip加个拓展,
如果临时需要, 则在骨骼迭代器中传入自定义处理器。

所有涉及骨骼操纵的方法, 调用前建议执行 ent:SetupBones(), 确保获取到最新的骨骼矩阵数据, 避免计算异常。
```

## 简介
这是一个**纯客户端**的API, 通过 `ent:ManipulateBoneXXX` 等原生方法对骨骼进行直接控制，核心接口封装为 `Entity` 元表方法（前缀 `UPMa`），调用更直观。

优点: 
1.  直接操作骨骼, 无需通过 `ent:AddEffects(EF_BONEMERGE)`、`BuildBonePositions`、`ResetSequence` 等方法。
2.  支持实体/快照双输入（snapshotOrEnt）, 快照功能可减少重复骨骼矩阵获取操作, 提升帧循环运行性能。
3.  骨骼迭代器（boneIterator）配置化, 批量操作骨骼更高效, 支持骨骼偏移（角度/位置/缩放）、父级自定义等个性化配置。
4.  位标志（FLAG）错误处理机制, 无字符串拼接开销, 高效捕获所有异常场景（骨骼不存在、矩阵奇异等）。
5.  递归错误打印功能, 一键输出所有骨骼的异常信息, 大幅降低排错难度。
6.  精细化操纵标志（MANIP_FLAG）, 支持仅位置、仅角度、仅缩放等组合操纵, 灵活性拉满。
7.  根节点自动适配: 局部插值中自动识别根节点, 并强制切换为世界空间插值, 无需手动干预。
8.  支持可插入自定义回调, 动态修改插值行为与目标, 扩展性极强。
9.  骨骼名优先于 boneId 设计, 大幅提升编写效率与调试便捷性, 无需记忆数字索引。

缺点:
1.  运算量较大, 每次都需通过 Lua 进行多次矩阵逆运算和乘法运算, 对性能有一定压力。
2.  需要每帧更新, 持续占用客户端性能, 高骨骼数量场景下消耗明显。
3.  仅能筛选明显奇异矩阵（缩放导致）, 无法处理隐性奇异矩阵, 可能引发运算异常。
4.  可能会和使用了 `ent:ManipulateBoneXXX` 的其他方法冲突, 导致动画姿态异常。
5.  对骨骼排序要求较高, 需按"先父后子"顺序配置骨骼迭代器, 否则子骨骼姿态会异常。
6.  `ManipulateBonePosition` 有128单位距离限制, 超出限制会导致骨骼操纵失效。
7.  不支持实体本身与外部骨骼（父级实体骨骼）的操纵, 需自行拓展。

## 核心概念
### 1.  位标志（FLAG）
分为三类标志，通过 `bit.bor` 组合、`bit.band` 判断，高效传递状态信息，无字符串开销：
-  错误标志（ERR_FLAG_*）：标识异常场景（如 `ERR_FLAG_BONEID` 表示骨骼不存在、`ERR_FLAG_SINGULAR` 表示矩阵奇异、`ERR_FLAG_PARENT` 表示父骨骼不存在等）。
-  调用标志（CALL_FLAG_*）：标识方法调用类型（如 `CALL_FLAG_SET_POSITION` 表示调用骨骼位置+角度设置方法、`CALL_FLAG_SNAPSHOT` 表示调用快照生成方法、`CALL_FLAG_LERP_WORLD` 表示使用世界空间插值等）。
-  操纵标志（MANIP_FLAG_*）：标识骨骼操纵类型（如 `MANIP_POS` 表示仅设置位置、`MANIP_MATRIX` 表示位置+角度+缩放全量设置），对应 `UPManip.MANIP_FLAG` 全局表，支持组合使用。

### 2.  骨骼迭代器（boneIterator）
纯数组格式的配置表，用于批量配置骨骼信息，每个数组元素为单骨骼配置表，迭代器顶层支持全局自定义回调，示例如下：
```lua
local boneIterator = {
    {
        bone = "ValveBiped.Bip01_Head1", -- 必选：目标骨骼名
        tarBone = "ValveBiped.Bip01_Head1", -- 可选：目标实体对应骨骼名，默认与bone一致
        parent = "ValveBiped.Bip01_Neck1", -- 可选：自定义父骨骼名，默认使用骨骼原生父级
        tarParent = "ValveBiped.Bip01_Neck1", -- 可选：目标骨骼自定义父骨骼名，默认与parent一致
        ang = Angle(90, 0, 0), -- 可选：角度偏移
        pos = Vector(0, 0, 10), -- 可选：位置偏移
        scale = Vector(2, 2, 2), -- 可选：缩放偏移
        offset = Matrix(), -- 可选：手动设置偏移矩阵，优先级高于ang/pos/scale
        lerpMethod = CALL_FLAG_LERP_WORLD -- 可选：插值类型，默认 CALL_FLAG_LERP_LOCAL
    },
    -- 其他骨骼配置...
    -- 迭代器顶层支持自定义回调（全局生效，可选）
    UnpackMappingData = nil, -- 可选：动态解包骨骼配置回调
    LerpRangeHandler = nil, -- 可选：插值目标重定向回调
}
```
-  必选字段：`bone`（目标骨骼名，字符串类型）
-  可选字段：`tarBone`、`parent`、`tarParent`、`ang`、`pos`、`scale`、`offset`、`lerpMethod`
-  顶层回调字段：`UnpackMappingData`、`LerpRangeHandler`（全局生效，用于动态扩展插值逻辑）
-  关键特性：
  1.  偏移优先级：手动设置的 `offset` 矩阵（matrix类型）优先级最高，若已存在则不会覆盖；无有效 `offset` 时，自动将 `ang`/`pos`/`scale` 合并为 `offset` 矩阵。
  2.  插值适配：根骨骼会自动强制使用 `CALL_FLAG_LERP_WORLD` 插值模式，无需手动配置。
  3.  初始化要求：必须通过 `UPManip.InitBoneIterator(boneIterator)` 验证类型并生成偏移矩阵，否则可能引发运行时错误。

### 3.  快照（Snapshot）
缓存骨骼变换矩阵的键值对表结构，键为骨骼名（字符串），值为骨骼变换矩阵（matrix），由 `ent:UPMaSnapshot(boneIterator)` 生成。
-  核心用途：减少帧循环中重复调用 `GetBoneMatrix` 的开销，提升运行性能。
-  特性：支持作为 `UPMaLerpBoneBatch` 的初始源/目标源，与实体类型无缝兼容，无需额外类型转换。

### 4.  可插入回调（Insertable Callback）
骨骼迭代器支持两个顶层自定义回调，无需修改UPManip核心逻辑，即可动态扩展插值行为，扩展性极强。

#### 4.1  UnpackMappingData：添加插值行为的动态特性
```note
作用：插值执行前动态解包/修改单个骨骼的配置数据（mappingData），支持根据运行时状态调整骨骼偏移、父级、插值类型等配置。
所属：骨骼迭代器（boneIterator）顶层字段，全局生效。
参数列表：
1.  self：当前执行插值的实体（Entity）
2.  t：插值因子（number，与 UPMaLerpBoneBatch 的 t 参数一致）
3.  snapshotOrEnt：当前实体的骨骼快照或实体本身（table/Entity）
4.  tarSnapshotOrEnt：目标实体或目标骨骼快照（Entity/table）
5.  mappingData：当前骨骼的原始配置数据（table）
返回值：修改后的骨骼配置数据（table），若返回 nil 则使用原始配置。
用途：
-  帧循环中动态调整骨骼偏移（如根据实体状态修改角度偏移量）
-  运行时切换插值类型（如某些场景下临时将局部插值改为世界插值）
-  动态指定自定义父骨骼，实现更灵活的骨骼层级控制
```
示例：
```lua
local boneIterator = {
    { bone = "ValveBiped.Bip01_Head1" },
    -- 动态修改骨骼配置
    UnpackMappingData = function(self, t, snapshotOrEnt, tarSnapshotOrEnt, mappingData)
        -- 根据插值因子动态调整角度偏移
        mappingData.ang = Angle(90 * t, 0, 0)
        -- 根据实体速度切换插值类型
        if self:GetVelocity():Length() > 0 then
            mappingData.lerpMethod = CALL_FLAG_LERP_WORLD
        else
            mappingData.lerpMethod = CALL_FLAG_LERP_LOCAL
        end
        return mappingData
    end
}
```

#### 4.2  LerpRangeHandler：允许重定向插值目标
```note
作用：插值计算前重定向/修改初始矩阵（initMatrix）和目标矩阵（finalMatrix），支持自定义插值范围、修正目标姿态等操作。
所属：骨骼迭代器（boneIterator）顶层字段，全局生效。
参数列表：
1.  self：当前执行插值的实体（Entity）
2.  t：插值因子（number，与 UPMaLerpBoneBatch 的 t 参数一致）
3.  snapshotOrEnt：当前实体的骨骼快照或实体本身（table/Entity）
4.  tarSnapshotOrEnt：目标实体或目标骨骼快照（Entity/table）
5.  initMatrix：当前骨骼的初始变换矩阵（matrix）
6.  finalMatrix：当前骨骼的目标变换矩阵（matrix）
7.  mappingData：当前骨骼的配置数据（table，已通过 UnpackMappingData 处理）
返回值：修改后的初始矩阵（initMatrix）和目标矩阵（finalMatrix），若返回 nil 则使用原始矩阵。
用途：
-  重定向插值目标（如限制骨骼旋转角度范围，避免过度变形）
-  修正目标骨骼姿态（如对异常矩阵进行补偿，解决穿模问题）
-  自定义插值逻辑（如添加缓入缓出效果，替代线性插值）
```
示例：
```lua
local boneIterator = {
    { bone = "ValveBiped.Bip01_Head1" },
    -- 重定向插值目标，限制旋转范围
    LerpRangeHandler = function(self, t, snapshotOrEnt, tarSnapshotOrEnt, initMatrix, finalMatrix, mappingData)
        -- 获取初始和目标角度
        local initAng = initMatrix:GetAngles()
        local finalAng = finalMatrix:GetAngles()
        -- 限制X轴旋转在 -90 ~ 90 之间，避免头部过度翻转
        finalAng.p = math.Clamp(finalAng.p, -90, 90)
        -- 更新目标矩阵
        finalMatrix:SetAngles(finalAng)
        -- 返回修改后的矩阵
        return initMatrix, finalMatrix
    end
}
```

## 可用方法
### 骨骼层级相关
![client](./materials/upgui/client.jpg)
**table** ent:UPMaGetEntBonesFamilyLevel()
```note
获取实体骨骼的父子层级深度表, 键为 boneId（数字）, 值为层级深度（根骨骼层级为0，子骨骼层级逐级递增）。
内部逻辑：调用前会自动执行 ent:SetupBones()，确保骨骼数据最新；递归遍历骨骼父子关系，标记每个骨骼的层级深度。
异常场景：实体无效、无模型（GetModel() 返回空）、无根骨骼（父级为-1的骨骼不存在）时，打印错误日志并返回 nil。
用途：辅助骨骼迭代器排序（按"先父后子"顺序），避免子骨骼姿态异常。
```

### 骨骼矩阵相关
![client](./materials/upgui/client.jpg)
**bool** UPManip.IsMatrixSingularFast(**matrix** mat)
```note
工程化快速判断矩阵是否为奇异矩阵（无法求逆），非数学严谨方法，性能优于行列式计算与直接矩阵求逆。
判断逻辑：检查矩阵的前向（Forward）、向上（Up）、右向（Right）向量的长度平方是否小于阈值（1e-2），任一向量长度过低则判定为奇异矩阵（通常由缩放为0导致）。
返回值：true 表示矩阵奇异（无法使用），false 表示矩阵可用。
用途：骨骼矩阵运算前的前置校验，快速筛选无效矩阵，避免运行时错误。
```

![client](./materials/upgui/client.jpg)
**matrix** UPManip.GetMatrixLocal(**matrix** mat, **matrix** parentMat, **bool** invert)
```note
计算骨骼相对父级的局部变换矩阵，支持正向/反向空间转换。
参数说明：
- mat：目标骨骼矩阵（matrix）
- parentMat：父骨骼矩阵（matrix）
- invert：是否反向计算（bool）
  - false：计算目标骨骼相对父骨骼的局部矩阵（默认）
  - true：计算父骨骼相对目标骨骼的局部矩阵
异常场景：目标矩阵或父矩阵为奇异矩阵时，返回 nil。
用途：局部空间插值的核心辅助方法，用于世界空间与局部空间的坐标系转换。
```

![client](./materials/upgui/client.jpg)
**matrix** UPManip.GetBoneMatrixFromSnapshot(**string** boneName, **entity/table** snapshotOrEnt)
```note
统一从实体或快照中提取指定骨骼的变换矩阵，无需手动区分输入类型。
参数说明：
- boneName：目标骨骼名（string）
- snapshotOrEnt：实体（Entity）或快照（table，键为骨骼名，值为矩阵）
内部逻辑：
  1.  若为快照（table类型），直接返回 snapshotOrEnt[boneName]
  2.  若为实体（Entity类型），先通过 LookupBone 获取 boneId，再通过 GetBoneMatrix 获取矩阵
返回值：骨骼变换矩阵（matrix），骨骼不存在或矩阵无效时返回 nil。
用途：批量插值中快速获取骨骼矩阵，简化代码逻辑，提升开发效率。
```

### 骨骼操纵相关
![client](./materials/upgui/client.jpg)
**int** ent:UPMaSetBonePosition(**string** boneName, **vector** posw, **angle** angw)
```note
同时控制指定骨骼的世界位置和角度，返回位标志（成功返回 SUCC_FLAG，失败返回对应 ERR_FLAG + CALL_FLAG_SET_POSITION）。
限制：新位置与骨骼原始位置的距离不能超过128个单位，否则操纵失效。
内部逻辑：
  1.  通过骨骼名获取 boneId，获取骨骼当前矩阵与父骨骼矩阵
  2.  执行矩阵逆运算，转换操纵空间，规避原生 API 限制
  3.  计算新的操纵位置与角度，调用原生 ManipulateBonePosition/Angles 方法
调用前建议执行 ent:SetupBones()，确保矩阵数据最新。
```

![client](./materials/upgui/client.jpg)
**int** ent:UPMaSetBonePos(**string** boneName, **vector** posw)
```note
仅控制指定骨骼的世界位置，返回位标志（成功返回 SUCC_FLAG，失败返回对应 ERR_FLAG + CALL_FLAG_SET_POS）。
限制：新位置与骨骼原始位置的距离不能超过128个单位，超出则操纵失效。
内部逻辑：简化版 UPMaSetBonePosition，仅处理位置参数，跳过角度计算。
调用前建议执行 ent:SetupBones()，确保矩阵数据最新。
```

![client](./materials/upgui/client.jpg)
**int** ent:UPMaSetBoneAng(**string** boneName, **angle** angw)
```note
仅控制指定骨骼的世界角度，返回位标志（成功返回 SUCC_FLAG，失败返回对应 ERR_FLAG + CALL_FLAG_SET_ANG）。
内部逻辑：简化版 UPMaSetBonePosition，仅处理角度参数，跳过位置计算；通过矩阵逆运算转换角度空间，确保角度设置准确。
调用前建议执行 ent:SetupBones()，确保矩阵数据最新。
```

![client](./materials/upgui/client.jpg)
**int** ent:UPMaSetBoneScale(**string** boneName, **vector** scale)
```note
仅设置指定骨骼的缩放比例，返回位标志（成功返回 SUCC_FLAG，失败返回对应 ERR_FLAG + CALL_FLAG_SET_SCALE）。
限制：不支持实体本身的缩放，仅支持骨骼缩放；骨骼不存在时直接返回错误标志。
注意事项：需与骨骼位置/角度操纵配合使用，单独使用可能导致骨骼姿态异常。
```

![client](./materials/upgui/client.jpg)
**int** ent:UPManipBoneBatch(**table** snapshot, **table** boneIterator, **int** manipflag)
```note
按骨骼迭代器顺序批量操纵骨骼，将插值快照数据落地到实体骨骼上。
参数说明：
- snapshot：插值后的骨骼数据快照（table，key=骨骼名，value=骨骼矩阵）
- boneIterator：骨骼迭代器（table，需提前通过 UPManip.InitBoneIterator 初始化）
- manipflag：操纵标志（int，来自 UPManip.MANIP_FLAG，支持 bit.bor 组合使用）
返回值：骨骼操纵状态表（table，key=骨骼名，value=位标志）
内部逻辑：
  1.  按骨骼迭代器顺序遍历骨骼（保证先父后子）
  2.  从快照中提取骨骼位置、角度、缩放数据
  3.  根据 manipflag 调用对应操纵方法（UPMaSetBonePos/Ang/Scale 等）
  4.  快照数据无效时，跳过当前骨骼，不影响其他骨骼执行
```

### 快照相关
![client](./materials/upgui/client.jpg)
**table, table** ent:UPMaSnapshot(**table** boneIterator)
```note
生成实体骨骼的快照，缓存骨骼变换矩阵，返回快照表和状态标志表。
参数说明：
- boneIterator：骨骼迭代器（table，需提前通过 UPManip.InitBoneIterator 初始化）
返回值：
- snapshot：快照表（table，key=骨骼名，value=骨骼矩阵）
- flags：状态标志表（table，key=骨骼名，value=位标志）
内部逻辑：
  1.  按骨骼迭代器顺序遍历骨骼
  2.  逐个获取骨骼 boneId 与矩阵，缓存到快照表中
  3.  骨骼不存在/矩阵无效时，记录对应错误标志，跳过当前骨骼
用途：减少帧循环中重复调用 GetBoneMatrix 的开销，提升运行性能。
```

### 骨骼插值相关
![client](./materials/upgui/client.jpg)
**table, table** ent:UPMaLerpBoneBatch(**number** t, **entity/table** snapshotOrEnt, **entity/table** tarSnapshotOrEnt, **table** boneIterator)
```note
批量执行骨骼姿态线性插值，仅返回插值结果（不直接设置骨骼状态），返回插值快照和状态标志表。
参数说明：
- t：插值因子（number，建议 0-1，超出范围会触发过度插值）
- snapshotOrEnt：初始源（Entity 实体或 table 快照，必选）
- tarSnapshotOrEnt：目标源（Entity 实体或 table 快照，必选）
- boneIterator：骨骼迭代器（table，需提前通过 UPManip.InitBoneIterator 初始化，支持自定义回调）
返回值：
- lerpSnapshot：插值快照（table，key=骨骼名，value=骨骼矩阵）
- flags：状态标志表（table，key=骨骼名，value=位标志）
内部逻辑：
1.  自动识别根节点，强制将根节点切换为世界空间插值（CALL_FLAG_LERP_WORLD）
2.  支持两种插值模式：
    - 世界空间插值（CALL_FLAG_LERP_WORLD）：以世界坐标系为父级，不依赖骨骼父子关系
    - 局部空间插值（CALL_FLAG_LERP_LOCAL）：以骨骼原生/自定义父级为坐标系，保持骨骼联动
3.  执行 UnpackMappingData 回调，动态处理骨骼配置数据
4.  自动应用骨骼偏移矩阵（offset），处理父级自定义配置
5.  执行 LerpRangeHandler 回调，重定向/修正插值初始矩阵与目标矩阵
6.  对位置、角度、缩放分别执行线性插值（LerpVector/LerpAngle）
7.  插值失败时记录错误标志，跳过当前骨骼，不影响其他骨骼执行
调用前建议执行：当前实体:SetupBones()、目标实体:SetupBones()（传入实体类型时）。
```

### 错误处理相关
![client](./materials/upgui/client.jpg)
**void** ent:UPMaPrintErr(**int/table** runtimeflag, **string** boneName, **number** depth)
```note
递归打印骨骼操纵/插值过程中的错误信息，支持单个位标志和标志表两种输入格式。
参数说明：
- runtimeflag：位标志（number）或标志表（table，key=骨骼名，value=位标志）
- boneName：骨骼名（string，仅单个标志输入时有效，可选）
- depth：递归深度（number，内部使用，默认 0，最大限制 10，防止无限递归）
内部逻辑：
  1.  若为标志表，递归遍历每个骨骼的标志并打印
  2.  若为单个标志，解析标志对应的错误/调用信息，格式化输出
  3.  无异常信息时，不输出任何内容
用途：调试时一键输出所有异常信息，快速定位问题（如骨骼不存在、矩阵奇异、父骨骼无效等）。
```

### 初始化相关
![client](./materials/upgui/client.jpg)
**void** UPManip.InitBoneIterator(**table** boneIterator)
```note
验证骨骼迭代器的有效性，并自动将角度/位置/缩放偏移转换为偏移矩阵（offset）。
#### 校验规则（触发 assert 断言报错）：
1.  骨骼迭代器必须是 table 类型
2.  迭代器元素必须是 table 类型，且必含 `bone` 字段（字符串类型）
3.  偏移配置（ang/pos/scale）必须是 angle/vector 类型或 nil
4.  顶层回调（UnpackMappingData/LerpRangeHandler）必须是 function 类型或 nil
5.  自定义字段（tarBone/parent/tarParent/lerpMethod）必须是 string/number/nil 类型
#### 转换规则：
1.  若已手动设置 `offset` 矩阵（matrix 类型），则跳过自动转换，保留原有配置
2.  若无有效 `offset` 矩阵，将 `ang`（角度）、`pos`（位置）、`scale`（缩放）合并为 `offset` 矩阵
3.  仅传入部分偏移字段（如仅 ang）时，仅转换对应属性，其他属性保持默认
用途：提前规避运行时类型错误，自动生成偏移矩阵，简化用户配置。
```

## 全局常量与表
### 1.  位标志消息表
```lua
UPManip.RUNTIME_FLAG_MSG -- 位标志与描述信息的映射表，key=位标志（number），value=错误/调用描述（string）
```

### 2.  操纵标志表
```lua
UPManip.MANIP_FLAG = {
    MANIP_POS = 0x01, -- 仅设置位置
    MANIP_ANG = 0x02, -- 仅设置角度
    MANIP_SCALE = 0x04, -- 仅设置缩放
    MANIP_POSITION = 0x03, -- 设置位置+角度（MANIP_POS | MANIP_ANG）
    MANIP_MATRIX = 0x07, -- 设置位置+角度+缩放（MANIP_POS | MANIP_ANG | MANIP_SCALE）
}
```

### 3.  插值模式表
```lua
UPManip.LERP_METHOD = {
    LOCAL = 0x2000, -- 局部空间插值（对应 CALL_FLAG_LERP_LOCAL）
    WORLD = 0x1000, -- 世界空间插值（对应 CALL_FLAG_LERP_WORLD）
}
```

### 4.  核心标志常量
```lua
-- 插值类型标志
CALL_FLAG_LERP_WORLD = 0x1000 -- 世界空间插值
CALL_FLAG_LERP_LOCAL = 0x2000 -- 局部空间插值

-- 调用类型标志
CALL_FLAG_SET_POSITION = 0x4000 -- 调用 UPMaSetBonePosition（位置+角度）
CALL_FLAG_SNAPSHOT = 0x8000 -- 调用 UPMaSnapshot（生成快照）
CALL_FLAG_SET_POS = 0x20000 -- 调用 UPMaSetBonePos（仅位置）
CALL_FLAG_SET_ANG = 0x40000 -- 调用 UPMaSetBoneAng（仅角度）
CALL_FLAG_SET_SCALE = 0x80000 -- 调用 UPMaSetBoneScale（仅缩放）

-- 基础错误标志
ERR_FLAG_BONEID = 0x01 -- 骨骼不存在（无法通过骨骼名获取 boneId）
ERR_FLAG_MATRIX = 0x02 -- 骨骼矩阵不存在（无法获取 GetBoneMatrix）
ERR_FLAG_SINGULAR = 0x04 -- 骨骼矩阵奇异（无法求逆）
ERR_FLAG_PARENT = 0x08 -- 父骨骼不存在
ERR_FLAG_PARENT_MATRIX = 0x10 -- 父骨骼矩阵不存在
ERR_FLAG_PARENT_SINGULAR = 0x20 -- 父骨骼矩阵奇异
ERR_FLAG_TAR_BONEID = 0x40 -- 目标骨骼不存在
ERR_FLAG_TAR_MATRIX = 0x80 -- 目标骨骼矩阵不存在
ERR_FLAG_TAR_SINGULAR = 0x100 -- 目标骨骼矩阵奇异
ERR_FLAG_TAR_PARENT = 0x200 -- 目标骨骼父级不存在
ERR_FLAG_TAR_PARENT_MATRIX = 0x400 -- 目标骨骼父级矩阵不存在
ERR_FLAG_TAR_PARENT_SINGULAR = 0x800 -- 目标骨骼父级矩阵奇异
ERR_FLAG_LERP_METHOD = 0x10000 -- 无效插值模式（非 WORLD/LOCAL）
SUCC_FLAG = 0x00 -- 操作成功标志
```

## 完整工作流示例
```lua
-- 1.  创建并初始化骨骼迭代器（包含自定义回调）
local boneIterator = {
    {
        bone = "ValveBiped.Bip01_Head1",
        lerpMethod = UPManip.LERP_METHOD.WORLD -- 使用便捷插值模式表
    },
    {
        bone = "ValveBiped.Bip01_Pelvis",
        pos = Vector(0, 0, 5),
        ang = Angle(0, 0, 0)
    },
    -- 动态修改骨骼配置
    UnpackMappingData = function(self, t, snapshotOrEnt, tarSnapshotOrEnt, mappingData)
        -- 根据插值因子动态调整角度偏移
        mappingData.ang = Angle(90 * t, 0, 0)
        return mappingData
    end,
    -- 重定向插值目标，限制旋转范围
    LerpRangeHandler = function(self, t, snapshotOrEnt, tarSnapshotOrEnt, initMatrix, finalMatrix, mappingData)
        local finalAng = finalMatrix:GetAngles()
        finalAng.p = math.Clamp(finalAng.p, -90, 90) -- 限制X轴旋转范围
        finalMatrix:SetAngles(finalAng)
        return initMatrix, finalMatrix
    end
}
-- 初始化骨骼迭代器（校验类型 + 生成偏移矩阵）
UPManip.InitBoneIterator(boneIterator)

-- 2.  创建客户端模型（目标实体与当前实体）
local ply = LocalPlayer()
local basePos = ply:GetPos() + ply:GetAimVector() * 150
local ent = ClientsideModel("models/mossman.mdl", RENDERGROUP_OTHER)
local tarEnt = ClientsideModel("models/mossman.mdl", RENDERGROUP_OTHER)

-- 设置实体位置，避免重叠
ent:SetPos(basePos)
tarEnt:SetPos(basePos + Vector(100, 0, 0))
-- 初始化骨骼状态
ent:SetupBones()
tarEnt:SetupBones()

-- 3.  帧循环中执行插值与骨骼操纵
local interpolateT = 0
timer.Create("upmanip_demo", 0, 0, function()
    if not IsValid(ent) or not IsValid(tarEnt) then
        timer.Remove("upmanip_demo")
        return
    end

    -- 3.1  更新骨骼状态（必须执行，确保矩阵最新）
    ent:SetupBones()
    tarEnt:SetupBones()

    -- 3.2  动态更新插值因子（0~1循环）
    interpolateT = (interpolateT + FrameTime() * 0.1) % 1

    -- 3.3  批量骨骼插值（自动执行自定义回调）
    local lerpSnapshot, lerpFlags = ent:UPMaLerpBoneBatch(
        interpolateT, ent, tarEnt, boneIterator
    )
    -- 打印插值错误信息
    ent:UPMaPrintErr(lerpFlags)

    -- 3.4  批量操纵骨骼（应用插值结果）
    local manipFlags = ent:UPManipBoneBatch(
        lerpSnapshot, boneIterator, UPManip.MANIP_FLAG.MANIP_MATRIX
    )
    -- 打印操纵错误信息
    ent:UPMaPrintErr(manipFlags)

    -- 3.5  移动目标实体，展示插值效果
    tarEnt:SetPos(basePos + Vector(math.cos(CurTime()), math.sin(CurTime()), 0) * 50)
end)

-- 4.  5秒后自动清理资源
timer.Simple(5, function()
    if IsValid(ent) then ent:Remove() end
    if IsValid(tarEnt) then tarEnt:Remove() end
    timer.Remove("upmanip_demo")
end)
```