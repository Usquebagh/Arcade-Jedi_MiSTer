# Return of the Jedi (Atari, 1984) for MiSTer

FPGA recreation of Atari's *Return of the Jedi* arcade hardware for the MiSTer (DE10-Nano).

**Status: in development — not yet tested on hardware.**

| Part | State |
|---|---|
| Main 6502, sound 6502, memory maps, latches, IRQs | done |
| Video: alphanumerics, playfield, PIXI smoothing, motion objects, colour RAM | done — pixel-identical to MAME 0.268 in attract mode |
| Sound: 4 × POKEY | done — pitch/rhythm match MAME |
| Speech: TMS5220 | integrated, being verified |
| Flight yoke (analog stick / mouse / digital), buttons, coins | wired, needs hardware test |
| NOVRAM (high scores, settings) save/load | wired, needs hardware test |
| MiSTer integration (MRA, ROM loading, OSD, video/audio) | first build |

## Installing

1. Copy `releases/Arcade-Jedi_<date>.rbf` to `/media/fat/_Arcade/cores/` as `Jedi_<date>.rbf`.
2. Copy `releases/Return of the Jedi.mra` to `/media/fat/_Arcade/`.
3. Put the MAME `jedi.zip` ROM set in `/media/fat/games/mame/`.

Controls: analog stick = yoke; A = trigger (also starts the game), B / X = thumb buttons,
Select = coin. Yoke input mode (analog / mouse / digital) is in the OSD.

## Building

```bash
./build.sh            # Quartus Lite 17.0.2 in Docker (theypsilon/quartus-lite-c5:17.0.2)
sim/run.sh 600 30     # Verilator simulation; frames to sim/out/ (needs ROMs in ~/roms/jedi)
sim/attract_check.sh  # pixel comparison against MAME reference captures
```

Hardware notes and design decisions: [docs/hardware.md](docs/hardware.md).

## Credits and licences

This core is released under the **GPL-3.0** (see individual file headers).

- 6502 CPU: [Arlet Ottens' verilog-6502](https://github.com/Arlet/verilog-6502) (permissive licence, see `rtl/cpu6502/cpu.v`), with a small change for clock-enable use.
- TMS5220: [d18c7db's TMS5220_FPGA](https://github.com/d18c7db/TMS5220_FPGA) (GPL-3.0), modified for GHDL synthesis compatibility (see file header).
- Yoke input adapter: from [Videodr0me's Star Wars core](https://github.com/MiSTer-devel/Arcade-StarWars_MiSTer) (GPL-3.0).
- MiSTer framework (`sys/`): [MiSTer-devel Template](https://github.com/MiSTer-devel/Template_MiSTer) (GPL-2.0+).
- Hardware reference: Atari SP-227 schematics / TM-227 manual, and MAME's `jedi.cpp` (Dan Boris, Aaron Giles).

ROMs are not included.
