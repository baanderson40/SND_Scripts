### Support via [baanderson40's ko-fi](https://ko-fi.com/baanderson40)
---

# Crafting & Gathering scripts

## Scripts
- [Collectable GatherBuddy Watcher](Collectable%20GatherBuddy%20Watcher.lua): monitors an item count, stops GatherBuddy AutoGather at the target, and optionally enables AutoRetainer MultiMode or runs a follow-up macro. Set the target item ID/count; requires GatherBuddy Reborn for AutoGather.
- [Diadem Artisanal Crafting](Diadem%20Artisanal%20Crafting.lua): gathers Diadem materials, approves them in the Firmament, and optionally crafts Grade 4 Artisanal Skybuilders' items with Artisan before turning them in to Potkin. Supports timed Gathering/Fishing modes and repeated cycles.
  - Declares GatherBuddy Reborn, vnavmesh, Artisan, and Pandora's Box dependencies. Prepare an existing GBR auto-gather list with the required ingredients enabled; configure the craft/mode, amount, and cycles.
- [Enable AR MultiMode After Crafting](Enable%20AR%20MultiMode%20After%20Crafting.lua): waits for the configured idle period after crafting/repair conditions, then enables AutoRetainer MultiMode.
- [Enable AR MultiMode After Gathering](Enable%20AR%20MultiMode%20After%20Gathering.lua): waits for the configured continuous normal-condition period, then enables AutoRetainer MultiMode.
- [Enable AR MultiMode After Timer](Enable%20AR%20MultiMode%20After%20Timer.lua): enables AutoRetainer MultiMode after a configured number of minutes.
- [Start Ocean Fishing and AR MultiMode](Start%20Ocean%20Fishing%20and%20AR%20MultiMode.lua): starts Henchman's On A Boat workflow and enables AutoRetainer MultiMode. Requires those plugins/workflows to be configured.
- [toggle_artisan](toggle_artisan.lua): toggles the Artisan plugin using Dalamud plugin enable/disable commands.

## Installation and setup
Import the individual Lua file's GitHub URL into SND, or paste its contents into a new Lua macro. Review metadata/configuration before running. AutoRetainer handoffs require AutoRetainer; follow-up macros must exist under their configured names.
