# UPManip Bone Manipulation
Use the console commands `upmanip_test_world` or `upmanip_test_local` to view the demo effects.

```note
Note: This is a test module and is not recommended for use in production environments.

These are all very hard to use; they're basically a piece of shit.

The threshold for using this method is extremely high. First, `ManipulateBonePosition` has a distance limit of 128 units.
Therefore, to achieve correct interpolation, the operation must be performed in the frame where the position update is completed.
For accurate interpolation, it is best to use a separate flag plus callback for handling, which reduces the chance of confusion.

Since these functions are often executed in the frame loop and the calculations are relatively intensive (serial execution), many errors are silent, which greatly
increases debugging difficulty—it's a bit like GPU programming, damn it. I do not recommend using these functions.

Interpolation requires specifying a bone iterator and its sorting order. The method `ent:UPMaGetEntBonesFamilyLevel()` can assist with sorting,
after which manual coding is required. Why not implement automatic sorting? Because some skeletons share the same bone names but have chaotic node
hierarchies, such as the `c_hand` in CW2.

There are two types of interpolation here: World-Space Interpolation (`CALL_FLAG_LERP_WORLD`) and Local-Space Interpolation (`CALL_FLAG_LERP_LOCAL`).
Essentially, world-space interpolation can be regarded as a special type of local-space interpolation, with the parent of all bones treated as the World.

Additionally, the APIs here use bone names (instead of boneIds) to target bones for manipulation. This simplifies writing and debugging, but the downside
is that it cannot efficiently recursively process external bones (such as the parent of the entity itself) like numeric indices can. Of course, this is unnecessary here—
we're not manipulating mecha skeletons, after all.

Entity self-manipulation is not supported here. Once enabled, maintaining logical consistency would require handling external bones, which is inefficient
and would severely reduce code readability and maintainability. It is better to handle this scenario manually or add an extension to UPManip in the future.
If temporary support is needed, you can pass a custom processor in the bone iterator.

For all methods involving bone manipulation, it is recommended to execute `ent:SetupBones()` before calling to ensure access to the latest bone matrix data and avoid calculation anomalies.
```

## Introduction
This is a **pure client-side** API that directly controls bones via native methods such as `ent:ManipulateBoneXXX`. Core interfaces are encapsulated as `Entity` metatable methods (prefixed with `UPMa`) for more intuitive calls.

### Advantages:
1. Directly manipulates bones without relying on methods like `ent:AddEffects(EF_BONEMERGE)`, `BuildBonePositions`, or `ResetSequence`.
2. Supports dual inputs (entity/snapshot, referred to as `snapshotOrEnt`). The snapshot feature reduces redundant bone matrix retrieval operations and improves frame loop performance.
3. Configurable bone iterators enable efficient batch bone operations, with support for personalized configurations such as bone offsets (angle/position/scale) and custom parent bones.
4. Bit flag-based error handling mechanism (no string concatenation overhead) efficiently captures all exception scenarios (e.g., non-existent bones, singular matrices).
5. Recursive error printing functionality outputs all bone exception information with one click, significantly reducing debugging effort.
6. Granular manipulation flags (`MANIP_FLAG`) support combined operations (position-only, angle-only, scale-only, etc.) for maximum flexibility.
7. Automatic root node adaptation: Automatically identifies root nodes during local-space interpolation and forces a switch to world-space interpolation without manual intervention.
8. Supports insertable custom callbacks to dynamically modify interpolation behavior and targets, providing extremely strong extensibility.
9. Bone name-first design (prioritizing bone names over boneIds) greatly improves writing efficiency and debugging convenience, eliminating the need to memorize numeric indices.

### Disadvantages:
1. High computational overhead: Each call requires multiple matrix inverse and multiplication operations via Lua, imposing certain performance pressure.
2. Requires per-frame updates, which continuously consumes client-side performance resources with significant overhead in high bone count scenarios.
3. Only able to filter obvious singular matrices (caused by zero scaling), unable to handle latent singular matrices, which may trigger calculation anomalies.
4. May conflict with other methods that use `ent:ManipulateBoneXXX`, leading to abnormal animation postures.
5. Strict requirements for bone sorting: Bone iterators must be configured in the "parent first, child second" order; otherwise, child bone postures will be abnormal.
6. `ManipulateBonePosition` has a 128-unit distance limit—exceeding this limit will cause bone manipulation to fail.
7. Does not support manipulation of the entity itself and external bones (parent entity bones); manual extension is required for such scenarios.

## Core Concepts
### 1. Bit Flags
Three categories of flags are supported, combined via `bit.bor` and checked via `bit.band` for efficient state information transmission with no string overhead:
- Error Flags (`ERR_FLAG_*`): Identify exception scenarios (e.g., `ERR_FLAG_BONEID` for non-existent bones, `ERR_FLAG_SINGULAR` for singular matrices, `ERR_FLAG_PARENT` for non-existent parent bones).
- Call Flags (`CALL_FLAG_*`): Identify method call types (e.g., `CALL_FLAG_SET_POSITION` for bone position + angle setting, `CALL_FLAG_SNAPSHOT` for snapshot generation, `CALL_FLAG_LERP_WORLD` for world-space interpolation).
- Manipulation Flags (`MANIP_FLAG_*`): Identify bone manipulation types (e.g., `MANIP_POS` for position-only setting, `MANIP_MATRIX` for full position/angle/scale setting), corresponding to the global `UPManip.MANIP_FLAG` table and supporting combined usage.

### 2. Bone Iterator
A pure array-based configuration table for batch bone configuration. Each array element is a single bone configuration table, with top-level global custom callbacks supported. Example as follows:
```lua
local boneIterator = {
    {
        bone = "ValveBiped.Bip01_Head1", -- Required: Target bone name
        tarBone = "ValveBiped.Bip01_Head1", -- Optional: Corresponding bone name in target entity (defaults to `bone` if not specified)
        parent = "ValveBiped.Bip01_Neck1", -- Optional: Custom parent bone name (defaults to the bone's native parent if not specified)
        tarParent = "ValveBiped.Bip01_Neck1", -- Optional: Custom parent bone name for target bone (defaults to `parent` if not specified)
        ang = Angle(90, 0, 0), -- Optional: Angle offset
        pos = Vector(0, 0, 10), -- Optional: Position offset
        scale = Vector(2, 2, 2), -- Optional: Scale offset
        offset = Matrix(), -- Optional: Manually set offset matrix (higher priority than ang/pos/scale)
        lerpMethod = CALL_FLAG_LERP_WORLD -- Optional: Interpolation type (defaults to `CALL_FLAG_LERP_LOCAL` if not specified)
    },
    -- Additional bone configurations...
    -- Top-level callback fields (globally effective, optional)
    UnpackMappingData = nil, -- Optional: Callback for dynamically unpacking bone configuration
    LerpRangeHandler = nil, -- Optional: Callback for redirecting interpolation targets
}
```
- Required Field: `bone` (target bone name, string type)
- Optional Fields: `tarBone`, `parent`, `tarParent`, `ang`, `pos`, `scale`, `offset`, `lerpMethod`
- Top-Level Callback Fields: `UnpackMappingData`, `LerpRangeHandler` (globally effective for extending interpolation logic dynamically)
- Key Features:
  1. Offset Priority: Manually set `offset` matrix (matrix type) has the highest priority and will not be overwritten if it exists; if no valid `offset` is present, `ang`/`pos`/`scale` are automatically merged into an `offset` matrix.
  2. Interpolation Adaptation: Root bones are automatically forced to use `CALL_FLAG_LERP_WORLD` interpolation mode with no manual configuration required.
  3. Initialization Requirement: Must be initialized via `UPManip.InitBoneIterator(boneIterator)` to validate types and generate offset matrices, otherwise runtime errors may occur.

### 3. Snapshot
A key-value table structure that caches bone transformation matrices, with bone names as keys and bone transformation matrices as values. Generated via `ent:UPMaSnapshot(boneIterator)`.
- Core Purpose: Reduces the overhead of repeated `GetBoneMatrix` calls in the frame loop to improve runtime performance.
- Feature: Seamlessly compatible with entity types as the initial/target source for `UPMaLerpBoneBatch`, with no additional type conversion required.

### 4. Insertable Callbacks
The bone iterator supports two top-level custom callbacks for dynamically extending interpolation behavior without modifying the core UPManip logic, providing strong extensibility.

#### 4.1 UnpackMappingData: Add Dynamic Features to Interpolation Behavior
```note
Purpose: Dynamically unpack/modify the configuration data (`mappingData`) of a single bone before interpolation execution, supporting adjustments to bone offsets, parent nodes, interpolation types, etc., based on runtime states.
Scope: Top-level field of the bone iterator, globally effective.
Parameter List:
1.  self: The entity currently executing interpolation (Entity)
2.  t: Interpolation factor (number, consistent with the `t` parameter of `UPMaLerpBoneBatch`)
3.  snapshotOrEnt: init entity or init bone snapshot
4.  tarSnapshotOrEnt: Target entity or target bone snapshot (Entity/table)
5.  mappingData: Original configuration data of the current bone (table)
Return Value: Modified bone configuration data (table). If `nil` is returned, the original configuration will be used.
Use Cases:
-  Dynamically adjust bone offsets in the frame loop (e.g., modify angle offset based on entity state)
-  Switch interpolation types at runtime (e.g., temporarily switch from local interpolation to world interpolation in certain scenarios)
-  Dynamically specify custom parent bones to achieve more flexible bone hierarchy control
```
Example:
```lua
local boneIterator = {
    { bone = "ValveBiped.Bip01_Head1" },
    -- Dynamically modify bone configuration
    UnpackMappingData = function(self, t, snapshotOrEnt, tarSnapshotOrEnt, mappingData)
        -- Dynamically adjust angle offset based on interpolation factor
        mappingData.ang = Angle(90 * t, 0, 0)
        -- Switch interpolation type at runtime based on entity velocity
        if self:GetVelocity():Length() > 0 then
            mappingData.lerpMethod = CALL_FLAG_LERP_WORLD
        else
            mappingData.lerpMethod = CALL_FLAG_LERP_LOCAL
        end
        return mappingData
    end
}
```

#### 4.2 LerpRangeHandler: Allow Redirecting Interpolation Targets
```note
Purpose: Redirect/modify the initial matrix (`initMatrix`) and target matrix (`finalMatrix`) before interpolation calculation, supporting custom interpolation ranges, target posture correction, and other operations.
Scope: Top-level field of the bone iterator, globally effective.
Parameter List:
1.  self: The entity currently executing interpolation (Entity)
2.  t: Interpolation factor (number, consistent with the `t` parameter of `UPMaLerpBoneBatch`)
3.  snapshotOrEnt: Bone snapshot or the entity itself of the current entity (table/Entity)
4.  tarSnapshotOrEnt: Target entity or target bone snapshot (Entity/table)
5.  initMatrix: Initial transformation matrix of the current bone (matrix)
6.  finalMatrix: Target transformation matrix of the current bone (matrix)
7.  mappingData: Configuration data of the current bone (table, already processed by `UnpackMappingData`)
Return Value: Modified initial matrix (`initMatrix`) and target matrix (`finalMatrix`). If `nil` is returned, the original matrices will be used.
Use Cases:
-  Redirect interpolation targets (e.g., limit bone rotation angle range to avoid excessive deformation)
-  Correct target bone postures (e.g., compensate for abnormal matrices to solve clipping issues)
-  Custom interpolation logic (e.g., add ease-in/ease-out effects to replace linear interpolation)
```
Example:
```lua
local boneIterator = {
    { bone = "ValveBiped.Bip01_Head1" },
    -- Redirect interpolation targets and limit rotation range
    LerpRangeHandler = function(self, t, snapshotOrEnt, tarSnapshotOrEnt, initMatrix, finalMatrix, mappingData)
        -- Get initial and target angles
        local initAng = initMatrix:GetAngles()
        local finalAng = finalMatrix:GetAngles()
        -- Limit X-axis rotation between -90 and 90 degrees to avoid excessive head flipping
        finalAng.p = math.Clamp(finalAng.p, -90, 90)
        -- Update target matrix
        finalMatrix:SetAngles(finalAng)
        -- Return modified matrices
        return initMatrix, finalMatrix
    end
}
```

## Available Methods
### Bone Hierarchy Related
![client](./materials/upgui/client.jpg)
**table** ent:UPMaGetEntBonesFamilyLevel()
```note
Retrieves the parent-child hierarchy depth table of the entity's bones. Keys are boneIds (numbers), and values are hierarchy depths (root bones have a depth of 0, with child bone depths increasing incrementally).
Internal Logic: Automatically executes `ent:SetupBones()` before calling to ensure the latest bone data is used; recursively traverses bone parent-child relationships to mark the hierarchy depth of each bone.
Exception Scenarios: Prints an error log and returns `nil` if the entity is invalid, has no model (GetModel() returns empty), or no root bone (no bone with parent -1 exists).
Use Case: Assists with bone iterator sorting (parent first, child second) to avoid abnormal child bone postures.
```

### Bone Matrix Related
![client](./materials/upgui/client.jpg)
**bool** UPManip.IsMatrixSingularFast(**matrix** mat)
```note
Engineered fast method to determine if a matrix is singular (non-invertible). Not a mathematically rigorous method, but more performant than determinant calculation and direct matrix inversion.
Judgment Logic: Checks if the squared length of the matrix's Forward, Up, or Right vectors is less than the threshold (1e-2). If any vector length is too low, the matrix is judged as singular (usually caused by zero scaling).
Return Value: `true` indicates the matrix is singular (unusable); `false` indicates the matrix is valid.
Use Case: Pre-validation before bone matrix operations to quickly filter invalid matrices and avoid runtime errors.
```

![client](./materials/upgui/client.jpg)
**matrix** UPManip.GetMatrixLocal(**matrix** mat, **matrix** parentMat, **bool** invert)
```note
Calculates the local transformation matrix of a bone relative to its parent, supporting forward and reverse coordinate system conversion.
Parameter Descriptions:
- mat: Target bone matrix (matrix)
- parentMat: Parent bone matrix (matrix)
- invert: Whether to perform reverse calculation (bool)
  - false: Calculate the local matrix of the target bone relative to the parent bone (default)
  - true: Calculate the local matrix of the parent bone relative to the target bone
Exception Scenario: Returns `nil` if the target matrix or parent matrix is singular.
Use Case: Core auxiliary method for local-space interpolation to convert between world and local coordinate systems.
```

![client](./materials/upgui/client.jpg)
**matrix** UPManip.GetBoneMatrixFromSnapshot(**string** boneName, **entity/table** snapshotOrEnt)
```note
Unified extraction of the transformation matrix of the specified bone from an entity or snapshot, with no need to manually distinguish input types.
Parameter Descriptions:
- boneName: Target bone name (string)
- snapshotOrEnt: Entity (Entity) or snapshot (table, with bone names as keys and matrices as values)
Internal Logic:
  1.  If it is a snapshot (table type), directly return snapshotOrEnt[boneName]
  2.  If it is an entity (Entity type), first get the boneId via LookupBone, then get the matrix via GetBoneMatrix
Return Value: Bone transformation matrix (matrix); returns `nil` if the bone does not exist or the matrix is invalid.
Use Case: Quickly retrieve bone matrices during batch interpolation to simplify code logic and improve development efficiency.
```

### Bone Manipulation Related
![client](./materials/upgui/client.jpg)
**int** ent:UPMaSetBonePosition(**string** boneName, **vector** posw, **angle** angw)
```note
Controls both the world position and angle of the specified bone. Returns a bit flag (`SUCC_FLAG` for success; corresponding `ERR_FLAG` + `CALL_FLAG_SET_POSITION` for failure).
Limit: The distance between the new position and the bone's original position cannot exceed 128 units; otherwise, manipulation will fail.
Internal Logic:
  1.  Get the boneId via the bone name, then retrieve the current bone matrix and parent bone matrix
  2.  Perform matrix inverse operation to convert the manipulation space and bypass native API limitations
  3.  Calculate the new manipulation position and angle, then call the native ManipulateBonePosition/Angles methods
It is recommended to execute `ent:SetupBones()` before calling to ensure up-to-date matrix data.
```

![client](./materials/upgui/client.jpg)
**int** ent:UPMaSetBonePos(**string** boneName, **vector** posw)
```note
Controls only the world position of the specified bone. Returns a bit flag (`SUCC_FLAG` for success; corresponding `ERR_FLAG` + `CALL_FLAG_SET_POS` for failure).
Limit: The distance between the new position and the bone's original position cannot exceed 128 units; exceeding this limit will cause manipulation to fail.
Internal Logic: Simplified version of UPMaSetBonePosition that only processes position parameters and skips angle calculations.
It is recommended to execute `ent:SetupBones()` before calling to ensure up-to-date matrix data.
```

![client](./materials/upgui/client.jpg)
**int** ent:UPMaSetBoneAng(**string** boneName, **angle** angw)
```note
Controls only the world angle of the specified bone. Returns a bit flag (`SUCC_FLAG` for success; corresponding `ERR_FLAG` + `CALL_FLAG_SET_ANG` for failure).
Internal Logic: Simplified version of UPMaSetBonePosition that only processes angle parameters and skips position calculations; converts the angle space via matrix inverse operation to ensure accurate angle setting.
It is recommended to execute `ent:SetupBones()` before calling to ensure up-to-date matrix data.
```

![client](./materials/upgui/client.jpg)
**int** ent:UPMaSetBoneScale(**string** boneName, **vector** scale)
```note
Sets only the scale ratio of the specified bone. Returns a bit flag (`SUCC_FLAG` for success; corresponding `ERR_FLAG` + `CALL_FLAG_SET_SCALE` for failure).
Limit: Does not support scaling of the entity itself, only bone scaling; returns an error flag directly if the bone does not exist.
Note: Should be used in conjunction with bone position/angle manipulation (using it alone may cause abnormal bone postures).
```

![client](./materials/upgui/client.jpg)
**int** ent:UPManipBoneBatch(**table** snapshot, **table** boneIterator, **int** manipflag)
```note
Batch manipulates bones in the order of the bone iterator, applying interpolated snapshot data to entity bones.
Parameter Descriptions:
- snapshot: Interpolated bone data snapshot (table, keys = bone names, values = bone matrices)
- boneIterator: Bone iterator (table, must be pre-initialized via UPManip.InitBoneIterator)
- manipflag: Manipulation flag (int, from `UPManip.MANIP_FLAG`, supporting combined usage via `bit.bor`)
Return Value: Bone manipulation status table (table, keys = bone names, values = bit flags)
Internal Logic:
  1.  Iterate over bones in the order of the bone iterator (ensuring parent first, child second)
  2.  Extract bone position, angle, and scale data from the snapshot
  3.  Call the corresponding manipulation methods (UPMaSetBonePos/Ang/Scale, etc.) based on `manipflag`
  4.  Skip the current bone if snapshot data is invalid without affecting other bones
```

### Snapshot Related
![client](./materials/upgui/client.jpg)
**table, table** ent:UPMaSnapshot(**table** boneIterator)
```note
Generates a snapshot of the entity's bones, caches bone transformation matrices, and returns a snapshot table and status flag table.
Parameter Description:
- boneIterator: Bone iterator (table, must be pre-initialized via UPManip.InitBoneIterator)
Return Values:
- snapshot: Snapshot table (table, keys = bone names, values = bone matrices)
- flags: Status flag table (table, keys = bone names, values = bit flags)
Internal Logic:
  1.  Iterate over bones in the order of the bone iterator
  2.  Retrieve the boneId and matrix for each bone and cache them in the snapshot table
  3.  Record the corresponding error flag and skip the current bone if the bone does not exist or the matrix is invalid
Use Case: Reduces the overhead of repeated `GetBoneMatrix` calls in the frame loop to improve runtime performance.
```

### Bone Interpolation Related
![client](./materials/upgui/client.jpg)
**table, table** ent:UPMaLerpBoneBatch(**number** t, **entity/table** snapshotOrEnt, **entity/table** tarSnapshotOrEnt, **table** boneIterator)
```note
Batch executes linear bone posture interpolation, returning only interpolation results (no direct bone state changes) along with an interpolation snapshot and status flag table.
Parameter Descriptions:
- t: Interpolation factor (number, recommended 0-1; values outside this range cause over-interpolation)
- snapshotOrEnt: Initial source (Entity or table snapshot, optional; defaults to the current entity if not specified)
- tarSnapshotOrEnt: Target source (Entity or table snapshot, required)
- boneIterator: Bone iterator (table, must be pre-initialized via UPManip.InitBoneIterator and supports custom callbacks)
Return Values:
- lerpSnapshot: Interpolation snapshot (table, keys = bone names, values = bone matrices)
- flags: Status flag table (table, keys = bone names, values = bit flags)
Internal Logic:
1.  Automatically identifies root nodes and forces a switch to world-space interpolation (`CALL_FLAG_LERP_WORLD`)
2.  Supports two interpolation modes:
    - World-Space Interpolation (`CALL_FLAG_LERP_WORLD`): Uses the world coordinate system as the parent, independent of bone parent-child relationships
    - Local-Space Interpolation (`CALL_FLAG_LERP_LOCAL`): Uses the bone's native/custom parent as the coordinate system to maintain bone linkage
3.  First executes the `UnpackMappingData` callback to dynamically process bone configuration data
4.  Automatically applies bone offset matrices and processes custom parent configurations
5.  Executes the `LerpRangeHandler` callback to redirect/correct the initial and target interpolation matrices
6.  Performs linear interpolation (LerpVector/LerpAngle) on position, angle, and scale separately
7.  Records error flags for failed interpolation and skips the current bone without affecting other bones
It is recommended to execute `currentEntity:SetupBones()` and `targetEntity:SetupBones()` (when passing an entity) before calling.
```

### Error Handling Related
![client](./materials/upgui/client.jpg)
**void** ent:UPMaPrintErr(**int/table** runtimeflag, **string** boneName, **number** depth)
```note
Recursively prints error information from bone manipulation/interpolation, supporting both single bit flags and flag tables as input.
Parameter Descriptions:
- runtimeflag: Bit flag (number) or flag table (table, keys = bone names, values = bit flags)
- boneName: Bone name (string, only valid for single flag input; optional)
- depth: Recursion depth (number, internal use; default 0, maximum limit 10 to prevent infinite recursion)
Internal Logic:
  1.  If it is a flag table, recursively traverse the flag of each bone and print it
  2.  If it is a single flag, parse the error/call information corresponding to the flag and output it in a formatted way
  3.  Outputs nothing if there is no exception information
Use Case: Output all exception information with one click during debugging to quickly locate issues (e.g., non-existent bones, singular matrices, invalid parent bones).
```

### Initialization Related
![client](./materials/upgui/client.jpg)
**void** UPManip.InitBoneIterator(**table** boneIterator)
```note
Validates the validity of the bone iterator and automatically converts angle/position/scale offsets in the configuration into an offset matrix (`offset`).
#### Validation Rules (triggers `assert` error on failure):
1.  The bone iterator must be a table type
2.  Iterator elements must be table types and contain the required `bone` field (string type)
3.  Offset configurations (`ang`/`pos`/`scale`) must be `angle`/`vector` types or `nil`
4.  Top-level callbacks (`UnpackMappingData`/`LerpRangeHandler`) must be `function` types or `nil`
5.  Custom fields (`tarBone`/`parent`/`tarParent`/`lerpMethod`) must be `string`/`number`/`nil` types
#### Conversion Rules:
1.  If a manual `offset` matrix (matrix type) is set, automatic conversion is skipped and the original configuration is retained
2.  If no valid `offset` matrix exists, `ang` (angle), `pos` (position), and `scale` (scale) are merged into an `offset` matrix
3.  If only partial offset fields are passed (e.g., only `ang`), only the corresponding attributes are converted, with other attributes remaining default
Use Case: Avoid runtime type errors in advance and automatically generate offset matrices to simplify user configuration.
```

## Global Constants and Tables
### 1. Bit Flag Message Table
```lua
UPManip.RUNTIME_FLAG_MSG -- Mapping table between bit flags and description information (keys = bit flags (number), values = error/call descriptions (string))
```

### 2. Manipulation Flag Table
```lua
UPManip.MANIP_FLAG = {
    MANIP_POS = 0x01, -- Position-only manipulation
    MANIP_ANG = 0x02, -- Angle-only manipulation
    MANIP_SCALE = 0x04, -- Scale-only manipulation
    MANIP_POSITION = 0x03, -- Position + angle manipulation (MANIP_POS | MANIP_ANG)
    MANIP_MATRIX = 0x07, -- Position + angle + scale manipulation (MANIP_POS | MANIP_ANG | MANIP_SCALE)
}
```

### 3. Interpolation Mode Table
```lua
UPManip.LERP_METHOD = {
    LOCAL = 0x2000, -- Local-Space Interpolation (corresponding to CALL_FLAG_LERP_LOCAL)
    WORLD = 0x1000, -- World-Space Interpolation (corresponding to CALL_FLAG_LERP_WORLD)
}
```

### 4. Core Flag Constants
```lua
-- Interpolation Type Flags
CALL_FLAG_LERP_WORLD = 0x1000 -- World-Space Interpolation
CALL_FLAG_LERP_LOCAL = 0x2000 -- Local-Space Interpolation

-- Call Type Flags
CALL_FLAG_SET_POSITION = 0x4000 -- Call UPMaSetBonePosition (Position + Angle)
CALL_FLAG_SNAPSHOT = 0x8000 -- Call UPMaSnapshot (Generate Snapshot)
CALL_FLAG_SET_POS = 0x20000 -- Call UPMaSetBonePos (Position Only)
CALL_FLAG_SET_ANG = 0x40000 -- Call UPMaSetBoneAng (Angle Only)
CALL_FLAG_SET_SCALE = 0x80000 -- Call UPMaSetBoneScale (Scale Only)

-- Basic Error Flags
ERR_FLAG_BONEID = 0x01 -- Bone does not exist (failed to get boneId via bone name)
ERR_FLAG_MATRIX = 0x02 -- Bone matrix does not exist (failed to get GetBoneMatrix)
ERR_FLAG_SINGULAR = 0x04 -- Singular bone matrix (non-invertible)
ERR_FLAG_PARENT = 0x08 -- Parent bone does not exist
ERR_FLAG_PARENT_MATRIX = 0x10 -- Parent bone matrix does not exist
ERR_FLAG_PARENT_SINGULAR = 0x20 -- Singular parent bone matrix
ERR_FLAG_TAR_BONEID = 0x40 -- Target bone does not exist
ERR_FLAG_TAR_MATRIX = 0x80 -- Target bone matrix does not exist
ERR_FLAG_TAR_SINGULAR = 0x100 -- Singular target bone matrix
ERR_FLAG_TAR_PARENT = 0x200 -- Target bone parent does not exist
ERR_FLAG_TAR_PARENT_MATRIX = 0x400 -- Target bone parent matrix does not exist
ERR_FLAG_TAR_PARENT_SINGULAR = 0x800 -- Singular target bone parent matrix
ERR_FLAG_LERP_METHOD = 0x10000 -- Invalid interpolation mode (not WORLD/LOCAL)
SUCC_FLAG = 0x00 -- Operation success flag
```

## Complete Workflow Example
```lua
-- 1. Create and initialize the bone iterator (with custom callbacks)
local boneIterator = {
    {
        bone = "ValveBiped.Bip01_Head1",
        lerpMethod = UPManip.LERP_METHOD.WORLD -- Use convenient interpolation mode table
    },
    {
        bone = "ValveBiped.Bip01_Pelvis",
        pos = Vector(0, 0, 5),
        ang = Angle(0, 0, 0)
    },
    -- Dynamically modify bone configuration
    UnpackMappingData = function(self, t, snapshotOrEnt, tarSnapshotOrEnt, mappingData)
        -- Dynamically adjust angle offset based on interpolation factor
        mappingData.ang = Angle(90 * t, 0, 0)
        return mappingData
    end,
    -- Redirect interpolation targets and limit rotation range
    LerpRangeHandler = function(self, t, snapshotOrEnt, tarSnapshotOrEnt, initMatrix, finalMatrix, mappingData)
        local finalAng = finalMatrix:GetAngles()
        finalAng.p = math.Clamp(finalAng.p, -90, 90) -- Limit X-axis rotation range
        finalMatrix:SetAngles(finalAng)
        return initMatrix, finalMatrix
    end
}
-- Initialize bone iterator (validate types + generate offset matrix)
UPManip.InitBoneIterator(boneIterator)

-- 2. Create client-side models (target entity and current entity)
local ply = LocalPlayer()
local basePos = ply:GetPos() + ply:GetAimVector() * 150
local ent = ClientsideModel("models/mossman.mdl", RENDERGROUP_OTHER)
local tarEnt = ClientsideModel("models/mossman.mdl", RENDERGROUP_OTHER)

-- Set entity positions to avoid overlapping
ent:SetPos(basePos)
tarEnt:SetPos(basePos + Vector(100, 0, 0))
-- Initialize bone states
ent:SetupBones()
tarEnt:SetupBones()

-- 3. Execute interpolation and bone manipulation in the frame loop
local interpolateT = 0
timer.Create("upmanip_demo", 0, 0, function()
    if not IsValid(ent) or not IsValid(tarEnt) then
        timer.Remove("upmanip_demo")
        return
    end

    -- 3.1 Update bone states (mandatory to ensure latest matrices)
    ent:SetupBones()
    tarEnt:SetupBones()

    -- 3.2 Dynamically update interpolation factor (cycle between 0 and 1)
    interpolateT = (interpolateT + FrameTime() * 0.1) % 1

    -- 3.3 Batch bone interpolation (automatically executes custom callbacks)
    local lerpSnapshot, lerpFlags = ent:UPMaLerpBoneBatch(
        interpolateT, ent, tarEnt, boneIterator
    )
    -- Print interpolation error information
    ent:UPMaPrintErr(lerpFlags)

    -- 3.4 Batch bone manipulation (apply interpolation results)
    local manipFlags = ent:UPManipBoneBatch(
        lerpSnapshot, boneIterator, UPManip.MANIP_FLAG.MANIP_MATRIX
    )
    -- Print manipulation error information
    ent:UPMaPrintErr(manipFlags)

    -- 3.5 Move target entity to demonstrate interpolation effect
    tarEnt:SetPos(basePos + Vector(math.cos(CurTime()), math.sin(CurTime()), 0) * 50)
end)

-- 4. Automatically clean up resources after 5 seconds
timer.Simple(5, function()
    if IsValid(ent) then ent:Remove() end
    if IsValid(tarEnt) then tarEnt:Remove() end
    timer.Remove("upmanip_demo")
end)
```