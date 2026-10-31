### Support via [baanderson40's ko-fi](https://ko-fi.com/baanderson40)
---

# Useful Scripts

Diagnostics, helpers, navigation tools, and examples for SND Lua development. Some files are reusable snippets rather than standalone workflows.

## Scripts
| Script | Purpose |
| --- | --- |
| [Addon Arg Probe](Addon%20Arg%20Probe.lua) | Probes configured addon callback opcode/argument ranges using `/pcall`. |
| [Big Dump](Big%20Dump.lua) | Dumps player, target, and client-state information using reflection. |
| [Character Condition Testing](Character%20Condition%20Testing.lua) | Inspects character condition flags. |
| [Go To Coordinates](Go%20To%20Coordinates.lua) | Pathfinds to configured X/Y/Z coordinates using vnavmesh. |
| [Installed Dalamud Plugins](Installed%20Dalamud%20Plugins.lua) | Logs installed plugin names/load status and provides a plugin-state helper. |
| [IPCs Subscribers](IPCs%20Subscribers.lua) | Reusable IPC subscriber cache and calling helpers. |
| [Job Name&Abbr from excel sheet](Job%20Name%26Abbr%20from%20excel%20sheet.lua) | Reads job names and abbreviations from ClassJob sheet rows. |
| [NPC name by id and excel sheet](NPC%20name%20by%20id%20and%20excel%20sheet.lua) | Resolves NPC names from IDs and game sheets. |
| [PlaceName by TerritoryTypeID](PlaceName%20by%20TerritoryTypeID.lua) | Resolves a territory ID to a localized place name. |
| [Player Current Status IDs](Player%20Current%20Status%20IDs.lua) | Echoes current player status IDs. |
| [Player Movement Speed Tracker](Player%20Movement%20Speed%20Tracker.lua) | Samples player movement and logs speed/rolling averages. |
| [Scan Entity By Name](Scan%20Entity%20By%20Name.lua) | Continuously scans for a configured entity and reports its return. |
| [SND base script](SND%20base%20script.lua) | Script template with logging, timing, and utility helpers. |
| [Target Distance Tracker](Target%20Distance%20Tracker.lua) | Echoes flat and 3D target distance every 0.25 seconds. |

## Setup and usage
- Import an individual Lua file's GitHub URL into SND, or paste it into a Lua macro. Review its metadata and source settings first; some examples use hard-coded IDs or ranges.
- Go To Coordinates requires vnavmesh. IPC helpers require the plugins exposing the IPCs you call.
- **Addon Arg Probe sends real UI callbacks, not read-only queries. Review the addon and argument ranges before running; callbacks can trigger unintended actions.**
- Diagnostic output may contain character/target information. Review logs before sharing them.
