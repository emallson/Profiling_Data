---@class Profiling_Data
local lib = LibStub:GetLibrary("Profiling_Data")
local lastKnownTime = nil
local internalFrameCounter = 0
local frameTimes = {}

---@class FrameIndex
---Provides information about the current rendered frame's position in time.
---Implemented by (ab)using the fact that GetTime's value is fixed within a frame. 
local frameIndex = {}

function frameIndex:reset()
    lastKnownTime = nil
    internalFrameCounter = 0
    frameTimes = {}
end

---Get the frame index. This doesn't necessarily correspond to the exact number of 
---frames since we started, but does count each frame in which `frameIndex` was called.
---@return integer
function frameIndex:get()
    local currentTime = GetTime()

    if currentTime ~= lastKnownTime then
        lastKnownTime = currentTime
        internalFrameCounter = internalFrameCounter + 1
        table.insert(frameTimes, currentTime)
    end

    return internalFrameCounter
end

---Get the value of `GetTime()` at each frame start.
---@return number[]
function frameIndex:getTimes()
    return frameTimes
end

lib.frameIndex = frameIndex