<p align="center">
  <a href="./README_en.md">English</a> |
  <a href="./README.md">简体中文</a>
</p>

- Author: 白狼 2322012547@qq.com
- Translator: Miss DouBao
- Date: December 10, 2025
- Version: 1.0.0 beta

### Contributors

Name: YuRaNnNzZZ
Link: https://steamcommunity.com/id/yurannnzzz
Contribution: hm500 Animation

Name: Miss Dou  
Link: Doubao AI  
Contribution: Chinese and English documentation

# UPManip Bone Manipulation Library - English Documentation
**Doc Author: Doubao (AI Douxiaojie) | Note: Documentation content unvalidated**

## Quick Start
Test the core functionality directly by entering `upmanip_test` in the game console. The command supports two parameters:
- 1st parameter: Manipulation flag (0x01=position only / 0x02=angle only / 0x04=scale only / 0x03=position+angle / 0x07=full matrix), default 0x07
- 2nd parameter: Any value (enables local space interpolation; omit for world space interpolation)


![client](./materials/upgui/4000_2542.jpg)

## Overview
UPManip is a bone manipulation library for Garry's Mod (GMod), primarily designed to address the 128-unit distance limit and interpolation inaccuracies of the native `ManipulateBonePosition` function. Its core goal is to make bone interpolation more flexible and computationally efficient, while introducing two practical features: Proxies and Snapshots. Debugging is simplified with built-in error logging for quick issue identification.

### Core Features
- Supports bone matrix interpolation (position, angle, scale) in world/local space
- Proxies: Enable static/dynamic bone set expansion, bone operation set expansion, and matrix offset application (e.g., mapping "SELF" to the entity itself)
- Snapshots: Cache bone matrix data at a specific moment to avoid redundant calculations in frame loops, improving performance
- Batch operation interfaces: Process multiple bones simultaneously for higher efficiency than individual operations
- Error flags + logging: Clear visibility into operation status without guesswork

### Critical Prerequisites
- Always call `ent:SetupBones()` before manipulating bones to ensure access to the latest bone data
- `ManipulateBonePosition` has a 128-unit distance limit; interpolation must be executed in the frame where position updates are completed
- Avoid repeated matrix inversions in high-frequency frame loops—use Snapshots for caching whenever possible

## Core Concepts (Key Focus)
### 1. Proxies
Proxies act as "middleware" for bone operations, with core purposes:
- Bone set expansion: Map virtual bone names (e.g., "SELF") to entities, effectively adding a "root bone" to the entity
- Operation set expansion: Customize bone get/set logic (e.g., applying fixed offsets to specific bone matrices)
- Dynamic adjustment: Assign different interpolation spaces or matrix offsets to individual bones for maximum flexibility

Core Proxy Interfaces (all optional—implement only as needed):
| Interface Name | Function Description | Parameter/Return Reference |
|----------------|----------------------|----------------------------|
| GetMatrix | Custom logic for retrieving bone matrices | Params: ent (entity), boneName (string), mode (matrix get mode); Return: Matrix/nil |
| GetParentMatrix | Custom logic for retrieving parent bone matrices | Params: Same as GetMatrix; Return: Matrix/nil |
| AdjustLerpResult | Modify interpolated matrices (e.g., add offsets) | Params: ent, boneName, result (interpolated matrix), lerpSpace (interpolation space); Return: Modified Matrix |
| SetPosition | Custom logic for setting bone position + angle | Params: ent, boneName, posw (world position), angw (world angle); Return: Operation flag |
| SetPos | Custom logic for setting bone position only | Params: ent, boneName, posw; Return: Operation flag |
| SetAng | Custom logic for setting bone angle only | Params: ent, boneName, angw; Return: Operation flag |
| SetScale | Custom logic for setting bone scale | Params: ent, boneName, scale; Return: Operation flag |
| GetLerpSpace | Assign interpolation space (world/local/skip) per bone | Params: proxy (self), ent, boneName, t (interpolation factor), ent1/ent2 (interpolation targets); Return: UPManip.LERP_SPACE.xxx |

### 2. Snapshots
Snapshots "capture and store" bone matrix data of specified bones at a specific moment—they are read-only and cannot be modified.
- Use case: In high-frequency interpolation, retrieve cached matrix data directly from Snapshots instead of recalculating/getting bones matrices every frame. Reduces matrix inversion overhead and improves performance.
- Note: Snapshots only store data—calling Set-type bone manipulation methods (e.g., UPMaSetBonePosition) on Snapshots will throw errors.

## Core Constants/Flags (Copy-Paste Ready)
### 1. Manipulation Flags (UPManip.MANIP_FLAG)
Control the dimensions of bone operations (commonly used in batch operations):
```lua
UPManip.MANIP_FLAG.MANIP_POS = 0x01    -- Position only
UPManip.MANIP_FLAG.MANIP_ANG = 0x02    -- Angle only
UPManip.MANIP_FLAG.MANIP_SCALE = 0x04  -- Scale only
UPManip.MANIP_FLAG.MANIP_POSITION = 0x03  -- Position + Angle
UPManip.MANIP_FLAG.MANIP_MATRIX = 0x07    -- Position + Angle + Scale (Full Matrix)
```

### 2. Matrix Get Modes (UPManip.PROXY_FLAG_GET_MATRIX)
Scene identifiers for proxy matrix retrieval:
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

### 3. Interpolation Spaces (UPManip.LERP_SPACE)
Specify the interpolation space for bones:
```lua
UPManip.LERP_SPACE.LERP_WORLD = 0x04  -- World space interpolation
UPManip.LERP_SPACE.LERP_LOCAL = 0x08  -- Local space interpolation
UPManip.LERP_SPACE.LERP_SKIP = 0x40   -- Skip interpolation for this bone
```

## Basic Utility Functions
### 1. UPManip.IsMatrixSingularFast
**boolean** UPManip:IsMatrixSingularFast(**Matrix** mat)
```note
Function: Quickly check if a matrix is singular (non-invertible). A pragmatic engineering solution, not a rigorous mathematical check.
Logic: Verify if the squared length of the matrix's forward/up/right vectors is less than 1e-4 (primarily detects non-invertibility caused by scaling in bone scenarios).
Params: mat = Matrix to check
Return: true = Matrix is singular (non-invertible); false = Matrix is non-singular (invertible)
```

### 2. UPManip.GetBoneFamilyLevel
**table/nil** UPManip:GetBoneFamilyLevel(**Entity** ent)
```note
Function: Calculate the hierarchical relationship of entity bones (root bone level = 0, child bone levels increment by 1).
Params: ent = Valid entity with a model
Return: Table with bone IDs as keys and levels as values; nil if the entity has no model/root bone
```

## Core Entity Extension Methods (Key Focus)
### 1. UPMaSetBonePosition
**number** Entity:UPMaSetBonePosition(**string** boneName, **Vector** posw, **Angle** angw, **table/nil** proxy)
```note
Function: Set the world space position and angle of a bone. Automatically converts world coordinates to local manipulation values compatible with native GMod APIs.
Params:
- boneName: Bone name (e.g., "ValveBiped.Bip01_Spine")
- posw: Target world position
- angw: Target world angle
- proxy: Bone proxy (optional)
Return: Operation flag (SUCC_FLAG = success; ERR_FLAG_* = error type)
Note: Must call ent:SetupBones() before use
```
Example:
```lua
local ent = LocalPlayer()
ent:SetupBones()
-- Set spine to world position (0,0,0) with zero angles
local flag = ent:UPMaSetBonePosition("ValveBiped.Bip01_Spine", Vector(0,0,0), Angle(0,0,0))
ent:UPMaPrintLog(flag, "ValveBiped.Bip01_Spine")  -- Print operation result log
```

### 2. UPManipBoneBatch
**table** Entity:UPManipBoneBatch(**table** resultBatch, **table** boneList, **number** manipflag, **table/nil** proxy)
```note
Function: Batch manipulate bones. Set position/angle/scale for multiple bones simultaneously based on the specified manipulation flag—more efficient than calling Set methods individually.
Params:
- resultBatch: Table with bone names as keys and interpolated Matrices (containing position/angle/scale) as values
- boneList: Array of bone names to manipulate
- manipflag: Manipulation flag (UPManip.MANIP_FLAG.xxx)
- proxy: Bone proxy (optional)
Return: Table with bone names as keys and corresponding operation flags as values
```
Example:
```lua
local ent = LocalPlayer()
ent:SetupBones()
local boneList = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Head1"}
-- Construct interpolated matrices (example only—use interpolation functions in practice)
local resultBatch = {}
for _, boneName in ipairs(boneList) do
    local mat = Matrix()
    mat:SetTranslation(ent:GetPos() + Vector(0,0,50))
    mat:SetAngles(Angle(0,0,0))
    mat:SetScale(Vector(1,1,1))
    resultBatch[boneName] = mat
end
-- Batch set position + angle
local flags = ent:UPManipBoneBatch(resultBatch, boneList, UPManip.MANIP_FLAG.MANIP_POSITION)
ent:UPMaPrintLog(flags)  -- Print batch operation log
```

### 3. UPMaLerpBoneWorldBatch
**table, table** Entity:UPMaLerpBoneWorldBatch(**table** boneList, **number** t, **Entity/UPSnapshot** ent1, **Entity/UPSnapshot** ent2, **table/nil** proxy1, **table/nil** proxy2)
```note
Function: Batch world space interpolation for multiple bones. Calculate the matrix of each bone at interpolation factor t.
Params:
- boneList: Array of bone names to interpolate
- t: Interpolation factor (0~1; 0 = ent1 state, 1 = ent2 state)
- ent1/ent2: Interpolation start/end targets (can be entities or Snapshots)
- proxy1/proxy2: Proxies for ent1/ent2 (optional)
Return:
- resultBatch: Table with bone names as keys and interpolated Matrices as values
- flags: Table with bone names as keys and interpolation operation flags as values
Note: Call SetupBones() on ent1, ent2, and the current entity before use
```
Example:
```lua
local ent = LocalPlayer()
local targetEnt = ClientsideModel("models/gman_high.mdl")
targetEnt:SetupBones()
ent:SetupBones()
local boneList = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Head1"}
-- Interpolate at factor 0.5 (midway between ent and targetEnt)
local resultBatch, flags = ent:UPMaLerpBoneWorldBatch(boneList, 0.5, ent, targetEnt)
-- Print log and apply interpolation results
ent:UPMaPrintLog(flags)
ent:UPManipBoneBatch(resultBatch, boneList, UPManip.MANIP_FLAG.MANIP_MATRIX)
```

### 4. UPMaLerpBoneLocalBatch
**table, table** Entity:UPMaLerpBoneLocalBatch(**table** boneList, **number** t, **Entity/UPSnapshot** ent1, **Entity/UPSnapshot** ent2, **table/nil** proxy1, **table/nil** proxy2, **table/nil** proxySelf)
```note
Function: Batch local space interpolation (relative to parent bones) for multiple bones. More stable than world space interpolation.
Params: Same as UPMaLerpBoneWorldBatch, plus proxySelf (proxy for the current entity)
Return: Same as UPMaLerpBoneWorldBatch
```

### 5. UPMaLerpBoneWorldBatchEasy
**table, table** Entity:UPMaLerpBoneWorldBatchEasy(**table** boneList, **number** t, **Entity/UPSnapshot** ent1, **Entity/UPSnapshot** ent2, **table/nil** proxy)
```note
Function: Simplified batch world space interpolation. Uses the same proxy for both ent1 and ent2—fewer parameters for daily use.
Params: proxy = Shared proxy (optional)
Return: Same as UPMaLerpBoneWorldBatch
```
Example:
```lua
local ent = LocalPlayer()
local targetEnt = ClientsideModel("models/gman_high.mdl")
targetEnt:SetupBones()
ent:SetupBones()
local boneList = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Head1"}
-- Interpolate with the default proxy
local resultBatch, flags = ent:UPMaLerpBoneWorldBatchEasy(boneList, 0.3, ent, targetEnt, UPManip.ExpandSelfProxy)
```

### 6. UPMaLerpBoneLocalBatchEasy
**table, table** Entity:UPMaLerpBoneLocalBatchEasy(**table** boneList, **number** t, **Entity/UPSnapshot** ent1, **Entity/UPSnapshot** ent2, **table/nil** proxy)
```note
Function: Simplified batch local space interpolation. Uses the same proxy for ent1, ent2, and the current entity—convenient for daily use.
Params: proxy = Shared proxy (optional)
Return: Same as UPMaLerpBoneLocalBatch
```

### 7. UPMaFreeLerpBatch
**table, table** Entity:UPMaFreeLerpBatch(**table** boneList, **number** t, **Entity/UPSnapshot** ent1, **Entity/UPSnapshot** ent2, **table/nil** proxy)
```note
Function: Flexible batch interpolation. Assign different interpolation spaces (world/local/skip) to individual bones.
Requirement: Proxy must implement the GetLerpSpace method to specify interpolation space per bone.
```
Example:
```lua
-- Custom proxy: Local interpolation for head, world interpolation for spine, skip others
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
Function: Create a snapshot of specified bones for the entity. Cache bone matrix data at the current moment for subsequent interpolation—avoids redundant calculations.
Params:
- boneList: Array of bone names to cache
- proxy: Bone proxy (optional)
- withLocal: Whether to cache local matrices (true = cache, accelerates local interpolation)
- drawDebug: Whether to draw debug boxes (true = draw colored boxes at bone positions for 5 seconds, useful for debugging)
Return: UPSnapshot object (read-only—cannot call Set-type methods)
```
Example:
```lua
local ent = LocalPlayer()
ent:SetupBones()
local boneList = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Head1"}
-- Create snapshot with local matrix caching and debug boxes
local snapshot = ent:UPMaSnapshot(boneList, nil, true, true)
-- Use snapshot as the start target for subsequent interpolation
local resultBatch = ent:UPMaLerpBoneWorldBatchEasy(boneList, 0.5, snapshot, ent)
```

### 9. UPMaPrintLog
**void** Entity:UPMaPrintLog(**number/table** runtimeflag, **string/nil** boneName, **number/nil** depth)
```note
Function: Parse bone operation flags and print detailed success/error logs. Pass the flags table directly for batch operations to quickly locate issues.
```
Example:
```lua
local ent = LocalPlayer()
ent:SetupBones()
-- Single bone operation log
local flag = ent:UPMaSetBonePos("ValveBiped.Bip01_Head1", Vector(0,0,0))
ent:UPMaPrintLog(flag, "ValveBiped.Bip01_Head1")

-- Batch operation log
local boneList = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Head1"}
local _, flags = ent:UPMaLerpBoneWorldBatch(boneList, 0.5, ent, ent)
ent:UPMaPrintLog(flags)  -- Print logs for all bones in batch
```

## Default Proxy (UPManip.ExpandSelfProxy)
A built-in proxy that maps the virtual bone name "SELF" to the entity itself, enabling root bone set expansion:
| Method Name | Function |
|-------------|----------|
| SetPosition | If boneName is "SELF", set the entity's position and angle; otherwise call UPMaSetBonePosition |
| SetPos | If boneName is "SELF", set the entity's position; otherwise call UPMaSetBonePos |
| SetAng | If boneName is "SELF", set the entity's angle; otherwise call UPMaSetBoneAng |
| GetMatrix | If boneName is "SELF", return the entity's world matrix; otherwise call UPMaGetBoneMatrix |
| GetParentMatrix | If boneName is "SELF", return nil; otherwise return the parent bone's matrix |

Example:
```lua
local ent = LocalPlayer()
ent:SetupBones()
-- Use default proxy to set the entity's position and angle (boneName = "SELF")
local flag = ent:UPMaSetBonePosition("SELF", Vector(0,0,0), Angle(0,0,0), UPManip.ExpandSelfProxy)
ent:UPMaPrintLog(flag, "SELF")
```

## Summary
1. Test functionality with the `upmanip_test` console command—parameters control manipulation dimensions and interpolation space
2. Proxies are the core of flexibility: Enable bone set/operation set expansion and matrix offsets; implement only required interfaces
3. Snapshots cache bone matrices—critical for high-frequency interpolation to reduce computational overhead
4. Batch operations (UPManipBoneBatch, xxxBatch series) are more efficient than individual operations—prefer these
5. Always call `ent:SetupBones()` before bone manipulation; use `UPMaPrintLog` for debugging. Flags require full namespaces (e.g., UPManip.MANIP_FLAG.MANIP_POS) for proper reference.