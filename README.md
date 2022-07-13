# Profiling_Data

WoW Addon to generate profiling data via hooking the frame creation system. Very alpha. YMMV

## Data Being Dumped:

- `addon` - Addon usage as returned by `GetAddonCPUUsage()`
- `fn` - Function total and self time as returned by `GetFunctionCPUUsage()` for all scripts of all frames (except some internal Blizzard frames). This is done by replacing the called function with my own, which works around the double-counting that `GetFunctionCPUUsage()` normally does.
- `CreateFrame` - Information about frames created during combat. Frame creation seems to be slow relative to script calls.