### Support via [baanderson40's ko-fi](https://ko-fi.com/baanderson40)
---

# AutoDuty scripts

## Scripts
- [AutoDuty Multibox Starter](AutoDuty%20Multibox%20Starter.lua)
  - Enables AutoDuty multibox on the current character. Hosts send activation tells to configured clients; clients listen for activation and accept BossMod preset/Lifestream commands from the host in party chat.
  - Requires AutoDuty. Set **Host**, world-qualified **Client Names** (for example `Character Name@Kraken`), and a matching **Activation Message** on the relevant characters.
  - After importing or updating, disable and re-enable the **OnChatMessage** trigger in SND to refresh registration. BossMod/Lifestream commands require their corresponding plugins.
- [Hostile Target Action Rotation](Hostile%20Target%20Action%20Rotation.lua)
  - Finds matching BattleNpcs, moves into capture range, captures them, and repeats its damage rotation until manually stopped.
  - Set **Target Name Contains** before running. Review the script's action/movement logic for the intended activity.

## Installation
Import the individual Lua file's GitHub URL into SND, or paste its contents into a new Lua macro. Review metadata and configuration before running.
