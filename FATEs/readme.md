### Support via [baanderson40's ko-fi](https://ko-fi.com/baanderson40)
---

# FATE scripts

FATE-focused SND lua scripts.

## Scripts
- [FateToolkit Helper](FateToolkit%20Helper.lua)

  - Adds support utilities around Fate Tool Kit automation.
    - Pauses for AutoRetainer and handles Limsa summoning bell routing.
    - Maintains gemstone stockpiles and can exchange bicolor gemstones.
    - Supports self-repair or NPC repair workflows.
    - Includes optional stuck monitoring and local aetheryte recovery.
- [FateToolkit Inventory Watcher](FateToolkit%20Inventory%20Watcher.lua)
  - Watches an inventory item while Fate Toolkit runs and stops at the configured quantity.
  - Supports optional stuck recovery, a follow-up script, and AutoRetainer MultiMode on completion.

## Requirements and setup
- Run these alongside Fate Toolkit; they provide supporting workflows rather than replacing it.
- Helper declares AutoRetainer, vnavmesh, and Automaton dependencies. Its optional starting-area travel uses Lifestream.
- Inventory Watcher declares AutoRetainer, Lifestream, and vnavmesh dependencies. Set a valid target item DataId and stop quantity before starting.

## Installation
- Copy script's Github URL and paste into SND GitHub URL option to import and update.

### or

- Copy script's contents and paste into a new lua macro and update manually.
