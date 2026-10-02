# Return of the Jedi (Arcade, 1984) for MiSTer FPGA

An FPGA implementation of Atari's **Return of the Jedi** arcade game for the [MiSTer FPGA](https://github.com/MiSTer-devel/Main_MiSTer/wiki) platform.

Atari's third Star Wars arcade game swapped vectors for colourful raster graphics: race speeder bikes through the forests of Endor, fly the Millennium Falcon, and pilot an AT-ST — all in a diagonal, scrolling 3D view with a distinctive soft, "smoothed" look.

> **Early build.** Playable, and tested on MiSTer over HDMI. Feedback and bug reports are welcome via [Issues](https://github.com/Usquebagh/Arcade-Jedi_MiSTer/issues).

---

## Original Hardware

| Subsystem | Original Hardware | FPGA Implementation |
|---|---|---|
| **Main CPU** | MOS 6502 @ 2.5 MHz (own 10 MHz crystal) | Arlet Ottens' verilog-6502 |
| **Sound CPU** | MOS 6502 @ 1.512 MHz | Arlet Ottens' verilog-6502 |
| **Video** | Alphanumerics, scrolling playfield, 48 motion objects, 1024-colour palette with no priority logic | `jedi_core.v`, from the SP-227 schematics |
| **Smoothing** | PIXI II board: two 82S137 PROMs + line buffer blend each background pixel with its neighbours | Modelled in `jedi_core.v` |
| **Sound** | Quad POKEY custom + TI TMS5220 speech | `pokey.v` + d18c7db's TMS5220 |
| **Controls** | Flight yoke (2-axis analog) + trigger and thumb buttons | Analog stick, mouse, or d-pad |
| **NOVRAM** | 2 × X2212 (high scores, settings) | Saved to the SD card via MiSTer NVRAM |

Notes on the hardware and design decisions are in [docs/hardware.md](docs/hardware.md).

---

## Controls

| Input | Function |
|---|---|
| **Analog Stick** | Yoke |
| **A** | Trigger — fires, and starts the game after inserting a coin |
| **B / X** | Left / right thumb buttons |
| **Select / R** | Coin L / Coin R |

The **Yoke Controls** OSD page selects Analog Stick, Mouse, Digital Centering, Digital Relative or Auto, with separate Analog Sensitivity and Digital Speed settings and Y-axis inversion.

**Service Mode:** set it On in the OSD and choose Reset to enter Atari's self-test; set it Off and Reset to return to the game.

**High scores and game settings:** turn on **Autosave NVRAM** in the OSD, or use **Save NVRAM**.
Settings changed in Service Mode (lives, difficulty, coinage) are kept the same way.

**Yoke readout:** *Yoke Controls → Show Yoke X/Y* shows how far the yoke is from centre at the
bottom of the screen (`X+000 Y+000` = centred; about ±112 at full deflection).

**Known issue:** at the start of the first game the bike can pull hard to the left even though the
readout shows the stick centred. Push right briefly and it recovers; after that the controls behave
normally. Still being investigated.

**Cheats:** Infinite Lives and Invincibility are available from the OSD **Cheats** menu.

---

## ROMs

```
ROMs are not included. Use the MAME "jedi" set.

/_Arcade/Return of the Jedi.mra
/_Arcade/cores/Jedi_YYYYMMDD.rbf
/games/mame/jedi.zip
```

---

## Compilation

Quartus Prime Lite 17.0 targeting the DE10-Nano's Cyclone V. Open `Arcade-Jedi.qpf` and compile, or run `./build.sh` to build in Docker. A Verilator simulation is in `sim/`.

---

## Credits

- **Return of the Jedi (Arcade):** Dennis Harper (design / programming), Susan G. McBride (graphics), Synthia Petroka (audio), Mike Mahar (software support) — Atari, 1984
- **6502 CPU:** Arlet Ottens
- **TMS5220:** d18c7db
- **Yoke input:** Videodr0me ([Star Wars core](https://github.com/Videodr0me/Arcade-StarWars_MiSTer))
- **Cheat engine:** based on Kitrinx's MiSTer cheat code handling, via Martin Donlon's Irem M92 core
- **Cheats:** converted from the MAME cheat file at [mamecheat.co.uk](https://www.mamecheat.co.uk)
- **Reference:** MAME `jedi` driver by Dan Boris and Aaron Giles
- **MiSTer Platform:** Sorgelig and the MiSTer community

## License

GPL-3.0. See individual source files for their respective licenses.
