---@class LibProfiling_Data
local Profiling_Data = LibStub:NewLibrary("Profiling_Data", 0)

local functionRegistry = {}

function Profiling_Data.registerFunction(key, fn)
    functionRegistry[key] = fn
end

---build a string key for a frame
---@param frameName string
---@param origParent Frame|ParentedObject
---@return string
function Profiling_Data.buildFrameKey(frameName, origParent)
    local keys = {frameName}
    local parent = origParent

    while parent ~= nil do
        local subKey = parent:GetDebugName()
        table.insert(keys, subKey)
        parent = parent:GetParent()
    end

    return strjoin('/', unpack(keys))
end

function Profiling_Data.frameKey(frame)
    return Profiling_Data.buildFrameKey(frame:GetDebugName(), frame:GetParent())
end

---check if script profiling is enabled
---@return boolean
local function isScriptProfilingEnabled()
    return C_CVar.GetCVarBool("scriptProfile") or false
end

local createdFrames = {
    named = {},
    anonymous = {},
}

local function hookCreateFrame()
    local function hookSetScript(frame, scriptType, fn, alreadyInstrumented)
        local name = frame:GetName()
        local parent = frame:GetParent()
        if frame:IsToplevel() 
            or frame:IsForbidden() 
            or frame:IsProtected() 
            or (name ~= nil and string.match(name, "Blizzard") ~= nil)
            or (parent ~= nil and parent:GetDebugName() == "NamePlateDriverFrame")
            or name == "NamePlateDriverFrame" then
                -- print("skipping frame hook")
            return
        end
        if fn == nil or alreadyInstrumented then
            return
        end

        local frameKey = Profiling_Data.frameKey(frame)
        -- print('hooking frame: ' .. frame:GetDebugName())

        Profiling_Data.registerFunction(strjoin(':', frameKey, scriptType), fn)

        local status, err = pcall(frame.SetScript, frame, scriptType, function(...)
            local status, err = pcall(fn, ...)
            if not status then
                DevTools_Dump({
                    frame = frameKey,
                    err = err,
                    loc = "callsite"
                })
            end
        end, true)

        if not status then
            DevTools_Dump({
                frame = frameKey,
                err = err,
                loc = "instrumentation"
            })
        end
    end

    local dummyFrame = CreateFrame("Frame")
    local frameIndex = getmetatable(dummyFrame).__index
    hooksecurefunc(frameIndex, 'SetScript', hookSetScript)

    hooksecurefunc("CreateFrame", function(frameType, name, parent, template, index)
        local anonymous = true
        local frameName = 'Anonymous'
        if name ~= nil then
            frameName = name
            anonymous = false
        end
        local key = Profiling_Data.buildFrameKey(frameName, parent)

        local parentName = 'nil'
        if parent ~= nil then
            parentName = Profiling_Data.frameKey(parent)
        end

        local record = {
            frameType = frameType,
            name = name,
            parent = parentName,
            template = template,
            index = index
        }

        if not anonymous then
            createdFrames.named[key] = record
        else
            table.insert(createdFrames.anonymous, record)
        end
    end)
end

if isScriptProfilingEnabled() then
    hookCreateFrame()
end

local function addonUsage()
    local results = {}
    UpdateAddOnCPUUsage()
    for ix=1,GetNumAddOns() do
        local loaded, finishedLoading = IsAddOnLoaded(ix)
        if loaded then
            local pathName, name = GetAddOnInfo(ix)
            local time = GetAddOnCPUUsage(ix)

            results[pathName] = {
                name = name,
                time = time,
            }
        end
    end

    return results
end

local function functionUsage()
    local results = {}
    for key, value in pairs(functionRegistry) do
        local totalTime, count = GetFunctionCPUUsage(value, true)
        local selfTime, _count = GetFunctionCPUUsage(value, false)
        results[key] = {
            totalTime = totalTime,
            selfTime = selfTime,
            callCount = count
        }
    end
    return results
end

local function createFrameUsage()
    return createdFrames
end

local function resetCreatedFrames()
    createdFrames = {
        named = {},
        anonymous = {}
    }
end

function Profiling_Data.buildUsageTable()
    local results = {
        addon = addonUsage(),
        fn = functionUsage(),
        CreateFrame = createFrameUsage(),
    }
    return results
end

function Profiling_Data.dumpUsage()
    DevTools_Dump(Profiling_Data.buildUsageTable())
end

local currentEncounter = nil
function Profiling_Data.startEncounter(encounterId, encounterName, difficultyId, groupSize)
    resetCreatedFrames()
    ResetCPUUsage()
    currentEncounter = {
        encounterId = encounterId,
        encounterName = encounterName,
        difficultyId = difficultyId,
        groupSize = groupSize,
        startTime = time()
    }
end

function Profiling_Data.encounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    if currentEncounter == nil then
        -- don't do anything if we didn't see the encounter start. a mid-combat reload probably happened
        return
    end
    currentEncounter.success = true

    table.insert(Profiling_Data_Storage.recordings, {
        encounter = currentEncounter,
        data = Profiling_Data.buildUsageTable()
    })
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(frame, eventName, ...)
    if eventName == "ENCOUNTER_START" then
        Profiling_Data.startEncounter(...)
    elseif eventName == "ENCOUNTER_END" then
        Profiling_Data.encounterEnd(...)
    elseif eventName == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Profiling_Data" then
            Profiling_Data_Storage = Profiling_Data_Storage or { recordings = {} }
        end
    end
end)