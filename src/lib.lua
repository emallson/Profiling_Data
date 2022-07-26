---@class Profiling_Data
---@field hooks HookTable
local Profiling_Data = LibStub:NewLibrary("Profiling_Data", 0)
Profiling_Data.hooks = {}

---@class Hook
---@field hook fun(table)
---@field reset fun()
---@field usage fun(): any

---@class HookTable


local functionRegistry = {}
local functionDebugTime = {}

function Profiling_Data.registerFunction(key, fn)
    functionRegistry[key] = fn
    functionDebugTime[key] = 0
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

local function reportTiming(key, duration)
    functionDebugTime[key] = functionDebugTime[key] + duration
end

local function hookCreateFrame()
    local function hookSetScript(frame, scriptType, fn, alreadyInstrumented)
        local name = frame:GetName()
        local parent = frame:GetParent()
        if (frame.IsTopLevel and frame:IsToplevel())
            or (frame.IsForbidden and frame:IsForbidden())
            or (frame.IsProtected and frame:IsProtected())
            or (name ~= nil and string.match(name, "Blizzard") ~= nil)
            or (parent ~= nil and parent:GetDebugName() == "NamePlateDriverFrame")
            or name == "NamePlateDriverFrame" then
                -- print("skipping frame hook")
            return
        end
        if fn == nil or alreadyInstrumented then
            return
        end

        Profiling_Data.frameIndex:tap()
        local frameKey = Profiling_Data.frameKey(frame)
        -- print('hooking frame: ' .. frameKey)

        local wrappedFn = function(...) fn(...) end
        local key = strjoin(':', frameKey, scriptType)
        Profiling_Data.registerFunction(key, wrappedFn)

        frame:SetScript(scriptType, function(...)
            local startTime = debugprofilestop()
            local status, err = pcall(wrappedFn, ...)
            local endTime = debugprofilestop()

            reportTiming(key, endTime - startTime)
            if not status then
                DevTools_Dump({
                    frame = frameKey,
                    err = err,
                    loc = "callsite"
                })
            end
        end, true)
    end

    local dummyFrame = CreateFrame("Frame")
    local dummyAnimGroup = dummyFrame:CreateAnimationGroup()
    local dummyAnim = dummyAnimGroup:CreateAnimation()
    local function hookmetatable(object)
        local frameIndex = getmetatable(object).__index
        hooksecurefunc(frameIndex, 'SetScript', hookSetScript)
    end
    hookmetatable(dummyFrame)
    hookmetatable(dummyAnim)
    hookmetatable(dummyAnimGroup)

    Profiling_Data.hooks.event.hook(getmetatable(dummyFrame).__index)

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
            index = index,
            creationTime = time(),
            frameIndex = Profiling_Data.frameIndex:get()
        }

        if not anonymous then
            createdFrames.named[key] = record
        else
            table.insert(createdFrames.anonymous, record)
        end
    end)
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
        if count > 0 then
            results[key] = {
                totalTime = totalTime,
                callCount = count,
                debugTime = functionDebugTime[key]
            }
        end
    end
    return results
end

local function createFrameUsage()
    return createdFrames
end

local function resetState()
    createdFrames = {
        named = {},
        anonymous = {}
    }
    for key, value in pairs(functionDebugTime) do
        functionDebugTime[key] = 0
    end
    Profiling_Data.frameIndex:reset()
    Profiling_Data.hooks.event.reset()
end

function Profiling_Data.buildUsageTable()
    local results = {
        addon = addonUsage(),
        fn = functionUsage(),
        CreateFrame = createFrameUsage(),
        events = Profiling_Data.hooks.event.usage(),
        frames = {
            times = Profiling_Data.frameIndex:getTimes()
        }
    }
    return results
end

function Profiling_Data.dumpUsage(startKey)
    if startKey then
        DevTools_Dump(Profiling_Data.buildUsageTable()[startKey])
    else
        DevTools_Dump(Profiling_Data.buildUsageTable())
    end
end

local currentEncounter = nil
local currentMythicPlus = nil
function Profiling_Data.startEncounter(encounterId, encounterName, difficultyId, groupSize)
    if currentMythicPlus ~= nil then
        return
    end
    resetState()
    ResetCPUUsage()
    currentEncounter = {
        kind = "raid",
        encounterId = encounterId,
        encounterName = encounterName,
        difficultyId = difficultyId,
        groupSize = groupSize,
        startTime = time()
    }
end

function Profiling_Data.encounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    if currentEncounter == nil then
        -- don't do anything if we didn't see the encounter start. a mid-combat reload probably happened or we're in a key
        return
    end
    currentEncounter.success = success == 1
    currentEncounter.endTime = time()

    table.insert(Profiling_Data_Storage.recordings, {
        encounter = currentEncounter,
        data = Profiling_Data.buildUsageTable()
    })
    resetState()
    currentEncounter = nil
end

---@param mapId number
function Profiling_Data.startMythicPlus(mapId)
    resetState()
    ResetCPUUsage()
    currentMythicPlus = {
        kind = "mythicplus",
        mapId = mapId,
        groupSize = 5,
        startTime = time()
    }
end

---@param isCompletion boolean
---@param mapId number|nil
function Profiling_Data.endMythicPlus(isCompletion, mapId)
    if currentMythicPlus == nil then
        return
    end

    currentMythicPlus.success = isCompletion
    currentMythicPlus.endTime = time()
    table.insert(Profiling_Data_Storage.recordings, {
        encounter = currentMythicPlus,
        data = Profiling_Data.buildUsageTable()
    })
    resetState()
    currentMythicPlus = nil
end



if isScriptProfilingEnabled() then
    local frame = CreateFrame("Frame", "Profiling_Data_Frame")
    frame:RegisterEvent("ENCOUNTER_START")
    frame:RegisterEvent("ENCOUNTER_END")
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("CHALLENGE_MODE_START")
    frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    frame:RegisterEvent("CHALLENGE_MODE_RESET")
    frame:SetScript("OnEvent", function(frame, eventName, ...)
        if eventName == "ENCOUNTER_START" then
            Profiling_Data.startEncounter(...)
        elseif eventName == "ENCOUNTER_END" then
            Profiling_Data.encounterEnd(...)
        elseif eventName == "CHALLENGE_MODE_START" then
            Profiling_Data.startMythicPlus(...)
        elseif eventName == "CHALLENGE_MODE_COMPLETED" or eventName == "CHALLENGE_MODE_RESET" then
            Profiling_Data.endMythicPlus(eventName == "CHALLENGE_MODE_COMPLETED", ...)
        elseif eventName == "ADDON_LOADED" then
            local addonName = ...
            if addonName == "Profiling_Data" then
                Profiling_Data_Storage = Profiling_Data_Storage or { recordings = {} }
                hookCreateFrame()
            end
        end
    end)
end