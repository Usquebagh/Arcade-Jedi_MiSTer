# Return of the Jedi (Atari, 1984) for MiSTer

FPGA recreation of Atari's *Return of the Jedi* arcade hardware for the MiSTer (DE10-Nano).

**Status: early development — not playable yet.**

## Plan

1. Hardware spec from the schematics and MAME driver → [docs/hardware.md](docs/hardware.md)
2. Simulation harness (Verilator, frames dumped as images, compared against MAME)
3. Main CPU + ROM + video timing + alphanumerics layer (boot/self-test text on screen)
4. Playfield with PIXI smoothing, motion objects, colour RAM
5. Sound board: 6502, 4 × POKEY, TMS5220
6. Inputs (analogue yoke via ADC), NOVRAM save, MRA, MiSTer integration

## ROMs

ROMs are not included. The core will load the MAME 0.289 `jedi` set via an MRA file.
