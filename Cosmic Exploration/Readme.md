### Support via [baanderson40's ko-fi](https://ko-fi.com/baanderson40)
---

# Cosmic Exploration scripts

Cosmic Exploration centered SND lua scripts. 

## Scripts
- [Cosmic Red Alert Jumper](Cosmic%20Red%20Alert%20Jumper.lua)
  - Cycles enabled territories, starts ICE during selected weather, and advances after the configured normal-condition duration.
- [Cosmic Time Jumper](Cosmic%20Time%20Jumper.lua)
  - Runs ICE on the planets configured for each two-hour Eorzea Time slot.
- [Cosmic Weather Jumper](Cosmic%20Weather%20Jumper.lua)
  - Travels between territories for configured weather windows and runs ICE.
- [ICEd AR](ICEd%20AR.lua)
  - Integrates AutoRetainer processing into the ICE workflow, with configurable retainer-list closing and return distance.

## Requirements and setup
- Jumpers require ICE and vnavmesh. Configure enabled territories, time slots, or weather targets before running the relevant script.
- ICEd AR requires ICE, AutoRetainer, and vnavmesh. Configure it as an ICE post-mission command as shown below.

## Installation
- Copy script's Github URL and paste into SND GitHub URL option to import and update.
<img width="747" height="183" alt="image" src="https://github.com/user-attachments/assets/4af080ef-54a9-4ff1-8f9b-09fd740ac514" />

### or

- Copy script's contents and paste into a new lua macro and update manually.

## Ice Settings for ICEd AR
- Add `/snd run "ICEd AR"` to the ICE post-mission command, using the macro's actual name if renamed.
<img width="907" height="153" alt="image" src="https://github.com/user-attachments/assets/0e7ff53e-b12b-424d-90c0-2c26cf5e5342" />
