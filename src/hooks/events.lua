---@class Profiling_Data
local Profiling_Data = LibStub("Profiling_Data")

---@class EventHook:Hook
local eventHook = {}

local state = {}

local function eventState(key, eventName)
    if state[key] == nil then
        state[key] = {}
    end

    if state[key][eventName] == nil then
        state[key][eventName] = {}
    end

    return state[key][eventName]
end

local function RecordRegisterEvent(frame, eventName, unit1, unit2)
    local frameKey = Profiling_Data.frameKey(frame)
    local currentFrameIndex = Profiling_Data.frameIndex:get()

    local units = nil

    if unit1 or unit2 then
        units = {unit1, unit2}
    end

    table.insert(eventState(frameKey, eventName), {
        type = 'R',
        units = units,
        frameIndex = currentFrameIndex
    })
end

local function RecordUnregisterEvent(frame, eventName)
    local frameKey = Profiling_Data.frameKey(frame)
    local currentFrameIndex = Profiling_Data.frameIndex:get()

    table.insert(eventState(frameKey, eventName), {
        type = 'U',
        frameIndex = currentFrameIndex,
    })
end

local function RecordUnregisterAllEvents(frame)
    RecordUnregisterEvent(frame, "*")
end

local function RecordRegisterAllEvents(frame)
    RecordRegisterEvent(frame, "*")
end

function eventHook.hook(__index)
    hooksecurefunc(__index, 'RegisterEvent', RecordRegisterEvent)
    hooksecurefunc(__index, 'RegisterUnitEvent', RecordRegisterEvent)
    hooksecurefunc(__index, 'RegisterAllEvents', RecordRegisterAllEvents)
    hooksecurefunc(__index, 'UnregisterEvent', RecordUnregisterEvent)
    hooksecurefunc(__index, 'UnregisterAllEvents', RecordUnregisterAllEvents)
end

function eventHook.reset()
    state = {}
end

function eventHook.usage()
    local eventUsage = {}
    for _frameKey, tbl in pairs(state) do
        for eventName, _ in pairs(tbl) do
            if eventName ~= "*" and eventUsage[eventName] == nil then
                eventUsage[eventName] = GetEventCPUUsage(eventName)
            end
        end
    end
    return {
        updates = state,
        totalUsage = GetEventCPUUsage(),
        usage = eventUsage
    }
end

---@class HookTable
local hooks = Profiling_Data.hooks

hooks.event = eventHook