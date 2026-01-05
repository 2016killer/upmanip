<p align="center">
  <a href="./README_en.md">English</a> |
  <a href="./README.md">简体中文</a>
</p>

- 作者：白狼 2322012547@qq.com
- 翻译: 豆小姐
- 日期：2025 1 5
- 版本: 1.0.0 beta

### 贡献者

名字: YuRaNnNzZZ
链接: https://steamcommunity.com/id/yurannnzzz
贡献: hm500 动画

名字: 豆小姐
贡献: 中文、英文文档   

# UPManip 骨骼操作库 - 中文文档
**文档作者：豆包（AI豆小姐） | 注：本文档内容尚未验证**
![client](./materials/upgui/client.jpg)

## 快速上手
直接在游戏控制台输入 `upmanip_test` 就能测试本库的核心效果，指令支持两个参数：
- 第一个参数：操作标志位（0x01=仅坐标/0x02=仅角度/0x04=仅缩放/0x03=坐标+角度/0x07=完整矩阵），默认0x07
- 第二个参数：任意值（代表启用局部空间插值，不填则用世界空间插值）


![client](./materials/upgui/4000_2542.jpg)

## 概述
UPManip 是给 Garry's Mod 写的骨骼操作库，主要解决原生 `ManipulateBonePosition` 有128单位距离限制、插值不准的问题。核心就是让骨骼插值更灵活、计算更高效，还加了代理器和快照这两个实用的东西，调试也方便，内置了错误日志能快速定位问题。

### 核心亮点
- 支持世界/局部空间的骨骼矩阵插值（位置、角度、缩放都能插）
- 代理器：能静态/动态扩张骨骼集、骨骼操作集，还能给骨骼矩阵加偏移，比如把“SELF”映射到实体本身
- 快照：缓存某一时刻的骨骼矩阵，不用在每帧循环里重复算，省性能
- 批量操作接口：一次处理多个骨骼，比逐个操作效率高
- 错误标志位+日志：哪里错了能直接看，不用瞎猜

### 必看前置要求
- 操作骨骼前一定要先调 `ent:SetupBones()`，不然拿到的骨骼数据可能是错的
- `ManipulateBonePosition` 有128单位距离限制，插值要在位置更新完成的那一帧做
- 别在高频帧循环里反复算矩阵求逆，能用快照缓存就用

## 核心概念（重点）
### 1. 代理器
代理器说白了就是给骨骼操作加一层“中间件”，核心作用是：
- 扩张骨骼集：比如把“SELF”这个虚拟骨骼名映射到实体本身，相当于给实体加了个“根骨骼”
- 扩张操作集：自定义骨骼的设置/获取逻辑，比如给某类骨骼的矩阵加固定偏移
- 动态调整：不同骨骼用不同的插值空间、不同的矩阵偏移，灵活性拉满

代理器的核心接口（都是可选实现，按需写）：
| 接口名 | 功能说明 | 入参/返回值参考 |
|--------|----------|----------------|
| GetMatrix | 自定义获取骨骼矩阵的逻辑 | 入参：ent（实体）、boneName（骨骼名）、mode（矩阵获取模式）；返回值：Matrix/nil |
| GetParentMatrix | 自定义获取骨骼父级矩阵的逻辑 | 入参同上；返回值：Matrix/nil |
| AdjustLerpResult | 插值后调整矩阵（比如加偏移） | 入参：ent、boneName、result（插值后的矩阵）、lerpSpace（插值空间）；返回值：调整后的Matrix |
| SetPosition | 自定义设置骨骼位置+角度的逻辑 | 入参：ent、boneName、posw（世界位置）、angw（世界角度）；返回值：操作标志位 |
| SetPos | 自定义仅设置骨骼位置的逻辑 | 入参：ent、boneName、posw；返回值：操作标志位 |
| SetAng | 自定义仅设置骨骼角度的逻辑 | 入参：ent、boneName、angw；返回值：操作标志位 |
| SetScale | 自定义设置骨骼缩放的逻辑 | 入参：ent、boneName、scale；返回值：操作标志位 |
| GetLerpSpace | 给每个骨骼指定插值空间（世界/局部/跳过） | 入参：proxy（代理器自身）、ent、boneName、t（插值因子）、ent1/ent2（插值对象）；返回值：UPManip.LERP_SPACE.xxx |

### 2. 快照
快照就是把某一时刻实体指定骨骼的矩阵数据“拍下来存起来”，是只读的，不能改。
- 用处：高频插值时，不用每帧都去获取/计算骨骼矩阵，直接读快照里的缓存就行，能少算很多矩阵求逆，提升性能
- 注意：快照只存数据，不能对快照调用Set类的骨骼操作方法（比如UPMaSetBonePosition），会直接报错

## 核心常量/标志位（可直接复制）
### 1. 操作标志位（UPManip.MANIP_FLAG）
控制骨骼操作的维度，批量操作时常用：
```lua
UPManip.MANIP_FLAG.MANIP_POS = 0x01    -- 仅操作位置
UPManip.MANIP_FLAG.MANIP_ANG = 0x02    -- 仅操作角度
UPManip.MANIP_FLAG.MANIP_SCALE = 0x04  -- 仅操作缩放
UPManip.MANIP_FLAG.MANIP_POSITION = 0x03  -- 位置+角度
UPManip.MANIP_FLAG.MANIP_MATRIX = 0x07    -- 位置+角度+缩放（完整矩阵）
```

### 2. 矩阵获取模式（UPManip.PROXY_FLAG_GET_MATRIX）
代理器获取矩阵时的场景标识：
```lua
UPManip.PROXY_FLAG_GET_MATRIX.INIT = 0x01
UPManip.PROXY_FLAG_GET_MATRIX.FINAL = 0x02
UPManip.PROXY_FLAG_GET_MATRIX.CUR = 0x20
UPManip.PROXY_FLAG_GET_MATRIX.LERP_WORLD = 0x04
UPManip.PROXY_FLAG_GET_MATRIX.LERP_LOCAL = 0x08
UPManip.PROXY_FLAG_GET_MATRIX.INIT_LERP_WORLD = 0x05
UPManip.PROXY_FLAG_GET_MATRIX.FINAL_LERP_WORLD = 0x06
UPManip.PROXY_FLAG_GET_MATRIX.INIT_LERP_LOCAL = 0x09
UPManip.PROXY_FLAG_GET_MATRIX.FINAL_LERP_LOCAL = 0x0A
UPManip.PROXY_FLAG_GET_MATRIX.CUR_LERP_LOCAL = 0x28
UPManip.PROXY_FLAG_GET_MATRIX.SNAPSHOT = 0x10
```

### 3. 插值空间（UPManip.LERP_SPACE）
指定骨骼用哪种空间插值：
```lua
UPManip.LERP_SPACE.LERP_WORLD = 0x04  -- 世界空间插值
UPManip.LERP_SPACE.LERP_LOCAL = 0x08  -- 局部空间插值
UPManip.LERP_SPACE.LERP_SKIP = 0x40   -- 跳过该骨骼插值
```

## 基础工具函数
### 1. UPManip.IsMatrixSingularFast
**boolean** UPManip:IsMatrixSingularFast(**Matrix** mat)
```note
功能：快速判断矩阵是不是奇异矩阵（不可逆），不是严谨的数学判断，是工程上的快捷方法。
原理：检查矩阵的前向/向上/右向向量长度平方是否小于1e-4（骨骼里主要是缩放导致不可逆）。
参数：mat = 要检测的矩阵
返回值：true=矩阵奇异（不可逆）；false=非奇异（可逆）。
```

### 2. UPManip.GetBoneFamilyLevel
**table/nil** UPManip:GetBoneFamilyLevel(**Entity** ent)
```note
功能：算出实体骨骼的层级关系，根骨骼层级是0，子骨骼层级依次+1。
参数：ent = 有效的、带模型的实体
返回值：键是骨骼ID，值是层级的表；如果实体没模型/无根骨骼，返回nil。
```

## 核心实体扩展方法（重点）
### 1. UPMaSetBonePosition
**number** Entity:UPMaSetBonePosition(**string** boneName, **Vector** posw, **Angle** angw, **table/nil** proxy)
```note
功能：设置骨骼的世界空间位置和角度，会自动把世界坐标转成适配原生API的局部操作量。
参数：
- boneName：骨骼名（比如"ValveBiped.Bip01_Spine"）
- posw：目标世界位置
- angw：目标世界角度
- proxy：骨骼代理器（可选）
返回值：操作标志位（SUCC_FLAG=成功；ERR_FLAG_*=错误类型）。
注意：调用前必须先执行ent:SetupBones()。
```
示例：
```lua
local ent = LocalPlayer()
ent:SetupBones()
-- 把脊柱设置到世界坐标(0,0,0)，角度归零
local flag = ent:UPMaSetBonePosition("ValveBiped.Bip01_Spine", Vector(0,0,0), Angle(0,0,0))
ent:UPMaPrintLog(flag, "ValveBiped.Bip01_Spine")  -- 打印操作结果日志
```

### 2. UPManipBoneBatch
**table** Entity:UPManipBoneBatch(**table** resultBatch, **table** boneList, **number** manipflag, **table/nil** proxy)
```note
功能：批量操作骨骼，根据指定的操作标志位，一次性设置多个骨骼的位置/角度/缩放，效率比逐个调Set方法高。
参数：
- resultBatch：键是骨骼名，值是插值后的Matrix（包含位置/角度/缩放）
- boneList：要操作的骨骼名列表（数组）
- manipflag：操作标志位（UPManip.MANIP_FLAG.xxx）
- proxy：骨骼代理器（可选）
返回值：键是骨骼名，值是对应操作标志位的表。
```
示例：
```lua
local ent = LocalPlayer()
ent:SetupBones()
local boneList = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Head1"}
-- 构造插值后的矩阵（实际用插值函数获取，这里仅示例）
local resultBatch = {}
for _, boneName in ipairs(boneList) do
    local mat = Matrix()
    mat:SetTranslation(ent:GetPos() + Vector(0,0,50))
    mat:SetAngles(Angle(0,0,0))
    mat:SetScale(Vector(1,1,1))
    resultBatch[boneName] = mat
end
-- 批量设置位置+角度
local flags = ent:UPManipBoneBatch(resultBatch, boneList, UPManip.MANIP_FLAG.MANIP_POSITION)
ent:UPMaPrintLog(flags)  -- 打印批量操作日志
```

### 3. UPMaLerpBoneWorldBatch
**table, table** Entity:UPMaLerpBoneWorldBatch(**table** boneList, **number** t, **Entity/UPSnapshot** ent1, **Entity/UPSnapshot** ent2, **table/nil** proxy1, **table/nil** proxy2)
```note
功能：批量对多个骨骼做世界空间插值，算出每个骨骼在插值因子t下的矩阵。
参数：
- boneList：要插值的骨骼名列表（数组）
- t：插值因子（0~1，0=ent1的状态，1=ent2的状态）
- ent1/ent2：插值的起始/结束对象（可以是实体，也可以是快照）
- proxy1/proxy2：ent1/ent2对应的代理器（可选）
返回值：
- resultBatch：键是骨骼名，值是插值后的Matrix
- flags：键是骨骼名，值是插值操作的标志位
注意：调用前要给ent1/ent2/当前实体都执行SetupBones()。
```
示例：
```lua
local ent = LocalPlayer()
local targetEnt = ClientsideModel("models/gman_high.mdl")
targetEnt:SetupBones()
ent:SetupBones()
local boneList = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Head1"}
-- 插值因子0.5，取ent和targetEnt的中间状态
local resultBatch, flags = ent:UPMaLerpBoneWorldBatch(boneList, 0.5, ent, targetEnt)
-- 打印插值日志，然后应用插值结果
ent:UPMaPrintLog(flags)
ent:UPManipBoneBatch(resultBatch, boneList, UPManip.MANIP_FLAG.MANIP_MATRIX)
```

### 4. UPMaLerpBoneLocalBatch
**table, table** Entity:UPMaLerpBoneLocalBatch(**table** boneList, **number** t, **Entity/UPSnapshot** ent1, **Entity/UPSnapshot** ent2, **table/nil** proxy1, **table/nil** proxy2, **table/nil** proxySelf)
```note
功能：批量对多个骨骼做局部空间插值（相对于父骨骼），稳定性比世界空间插值好。
参数：比UPMaLerpBoneWorldBatch多了proxySelf（当前实体的代理器），其他一致。
返回值：和UPMaLerpBoneWorldBatch一致。
```

### 5. UPMaLerpBoneWorldBatchEasy
**table, table** Entity:UPMaLerpBoneWorldBatchEasy(**table** boneList, **number** t, **Entity/UPSnapshot** ent1, **Entity/UPSnapshot** ent2, **table/nil** proxy)
```note
功能：简化版的世界空间批量插值，ent1和ent2用同一个代理器，少传一个参数，日常用这个更方便。
参数：proxy = 共用的代理器（可选）
返回值：和UPMaLerpBoneWorldBatch一致。
```
示例：
```lua
local ent = LocalPlayer()
local targetEnt = ClientsideModel("models/gman_high.mdl")
targetEnt:SetupBones()
ent:SetupBones()
local boneList = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Head1"}
-- 用默认代理器做插值
local resultBatch, flags = ent:UPMaLerpBoneWorldBatchEasy(boneList, 0.3, ent, targetEnt, UPManip.ExpandSelfProxy)
```

### 6. UPMaLerpBoneLocalBatchEasy
**table, table** Entity:UPMaLerpBoneLocalBatchEasy(**table** boneList, **number** t, **Entity/UPSnapshot** ent1, **Entity/UPSnapshot** ent2, **table/nil** proxy)
```note
功能：简化版的局部空间批量插值，ent1、ent2、当前实体共用同一个代理器，日常使用更便捷。
参数：proxy = 共用的代理器（可选）
返回值：和UPMaLerpBoneLocalBatch一致。
```

### 7. UPMaFreeLerpBatch
**table, table** Entity:UPMaFreeLerpBatch(**table** boneList, **number** t, **Entity/UPSnapshot** ent1, **Entity/UPSnapshot** ent2, **table/nil** proxy)
```note
功能：更灵活的批量插值，能给每个骨骼指定不同的插值空间（世界/局部/跳过）。
要求：代理器要实现GetLerpSpace方法，用来指定每个骨骼的插值空间。
```
示例：
```lua
-- 自定义代理器：头部用局部插值，脊柱用世界插值，其他跳过
local customProxy = setmetatable({}, {__index = UPManip.ExpandSelfProxy})
function customProxy:GetLerpSpace(proxy, ent, boneName)
    if boneName == "ValveBiped.Bip01_Head1" then
        return UPManip.LERP_SPACE.LERP_LOCAL
    elseif boneName == "ValveBiped.Bip01_Spine" then
        return UPManip.LERP_SPACE.LERP_WORLD
    end
    return UPManip.LERP_SPACE.LERP_SKIP
end

local ent = LocalPlayer()
local targetEnt = ClientsideModel("models/gman_high.mdl")
targetEnt:SetupBones()
ent:SetupBones()
local boneList = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_L_Hand"}
local resultBatch, flags = ent:UPMaFreeLerpBatch(boneList, 0.5, ent, targetEnt, customProxy)
```

### 8. UPMaSnapshot
**UPSnapshot** Entity:UPMaSnapshot(**table** boneList, **table/nil** proxy, **boolean/nil** withLocal, **boolean/nil** drawDebug)
```note
功能：创建实体指定骨骼的快照，把当前时刻的骨骼矩阵缓存起来，后续插值直接用，不用重复计算。
参数：
- boneList：要缓存的骨骼名列表（数组）
- proxy：骨骼代理器（可选）
- withLocal：是否缓存局部矩阵（true=缓存，能加速局部插值）
- drawDebug：是否绘制调试框（true=在骨骼位置画彩色盒子，持续5秒，方便调试）
返回值：UPSnapshot对象（只读，不能调用Set类方法）。
```
示例：
```lua
local ent = LocalPlayer()
ent:SetupBones()
local boneList = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Head1"}
-- 创建快照，缓存局部矩阵，同时绘制调试框
local snapshot = ent:UPMaSnapshot(boneList, nil, true, true)
-- 后续插值可以直接用这个快照当起始对象
local resultBatch = ent:UPMaLerpBoneWorldBatchEasy(boneList, 0.5, snapshot, ent)
```

### 9. UPMaPrintLog
**void** Entity:UPMaPrintLog(**number/table** runtimeflag, **string/nil** boneName, **number/nil** depth)
```note
功能：解析骨骼操作的标志位，打印详细的错误/成功日志，批量操作时直接传flags表就行，能快速定位问题。
```
示例：
```lua
local ent = LocalPlayer()
ent:SetupBones()
-- 单骨骼操作日志
local flag = ent:UPMaSetBonePos("ValveBiped.Bip01_Head1", Vector(0,0,0))
ent:UPMaPrintLog(flag, "ValveBiped.Bip01_Head1")

-- 批量操作日志
local boneList = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Head1"}
local _, flags = ent:UPMaLerpBoneWorldBatch(boneList, 0.5, ent, ent)
ent:UPMaPrintLog(flags)  -- 批量打印所有骨骼的操作日志
```

## 默认代理器（UPManip.ExpandSelfProxy）
这个是库自带的默认代理器，核心作用是把“SELF”这个虚拟骨骼名映射到实体本身，实现根骨骼集的扩张：
| 方法名 | 功能 |
|--------|------|
| SetPosition | 如果骨骼名是"SELF"，就设置实体的位置和角度；否则调用UPMaSetBonePosition |
| SetPos | 如果骨骼名是"SELF"，就设置实体的位置；否则调用UPMaSetBonePos |
| SetAng | 如果骨骼名是"SELF"，就设置实体的角度；否则调用UPMaSetBoneAng |
| GetMatrix | 如果骨骼名是"SELF"，就返回实体的世界矩阵；否则调用UPMaGetBoneMatrix |
| GetParentMatrix | 如果骨骼名是"SELF"，返回nil；否则返回骨骼父级的矩阵 |

示例：
```lua
local ent = LocalPlayer()
ent:SetupBones()
-- 用默认代理器设置实体本身的位置和角度（骨骼名填SELF）
local flag = ent:UPMaSetBonePosition("SELF", Vector(0,0,0), Angle(0,0,0), UPManip.ExpandSelfProxy)
ent:UPMaPrintLog(flag, "SELF")
```

## 总结
1. 测试效果直接用控制台 `upmanip_test` 指令，参数可以控制操作维度和插值空间；
2. 代理器是核心灵活点，能扩张骨骼集/操作集、加矩阵偏移，自定义接口按需实现就行；
3. 快照用来缓存骨骼矩阵，高频插值场景一定要用，能大幅减少计算量；
4. 批量操作（UPManipBoneBatch、xxxBatch系列）比逐个操作高效，优先用；
5. 所有骨骼操作前必须调 `ent:SetupBones()`，出问题用 `UPMaPrintLog` 看日志，标志位要带完整命名空间（比如UPManip.MANIP_FLAG.MANIP_POS）。