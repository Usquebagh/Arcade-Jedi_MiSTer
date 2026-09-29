# Return of the Jedi (Atari, 1984) — hardware spec for the FPGA core

Sources, in priority order:
1. **SP-227** Schematic Package (sheets 4A–12A) — ground truth for timing and structure.
2. **MAME 0.289** `src/mame/atari/jedi.cpp` (Dan Boris, Aaron Giles) — functional model of
   the video pipeline, memory maps, ROM layout. Sheet 3B memory maps agree with it exactly.
3. **TM-227** Technical Manual — self-test and troubleshooting (not yet mined).

Sheet references below are "SP-227 sheet N".

## Board set

| Board | Contents |
|---|---|
| JEDI Game PCB (sheets 4A–11B) | Main 6502, sound 6502, quad-POKEY custom, TMS5220, all video |
| PIXI II PCB (sheet 12A) | Background smoothing: 2 × 82S137 PROMs (3C, 3B), 2149 line buffer (2A), page latch (5C) |
| Regulator/Audio II (sheet 3A) | Power + analogue audio amp — not needed in the core |

## Clocks

| Signal | Derivation | Frequency | Sheet |
|---|---|---|---|
| Video/sound osc | Y2 crystal | 12.096 MHz | 4A |
| Pixel clock `6MHZ` | 12.096 / 2 (11K) | 6.048 MHz | 4A |
| `1H` | 6MHZ / 2 (11K) | 3.024 MHz | 4A |
| Main CPU osc | Y1 crystal | 10.000 MHz | 4A |
| Main CPU φ0 | 10 / 4 | 2.5 MHz | 4A |
| Sound CPU φ0 | 12.096 / 8 | 1.512 MHz | 6A |
| POKEY clock | = sound CPU clock | 1.512 MHz | 6B |
| TMS5220 | 12.096 / 2 / 9 (LS163 counting 7→16) | 672 kHz | 7A |
| ADC0809 | same as TMS5220 | ~672 kHz | 5B |

FPGA plan: one master clock (e.g. 48.384 MHz = 4 × 12.096) with clock enables. The 10 MHz
domain is not a rational multiple, so the main CPU's 2.5 MHz enable comes from a fractional
accumulator (2.5 / 48.384). Main CPU timing relative to video is asynchronous on the real board too.

## Video timing (sheet 4A)

- **H counter**: 1H (11K) + 11J/11L LS163s = 2H…256H. Clear via 11M (LS20) when
  256H·64H·32H and 11J ripple-carry (1H–16H all set) → counts **0–383, 384 pixels/line**
  → 6.048 MHz / 384 = **15.75 kHz**.
- **HBLANK / HSYNC**: 12L/12M LS74s clocked from 8H/32H/2H, decoding 256H·64H (10L) and 16H.
  Exact edge positions to be taken from a higher-res read of sheet 4A; MAME's visible area is
  **296 pixels** (x 0–295).
- **V counter**: 10J/10H LS163s clocked by /256H, reloaded from **sync PROM 82S129 at 9H**
  (addressed by V bits), whose outputs are latched in 9F (LS175) → VBLANK, VSYNC, /VSYNC, reload.
- **9H PROM contents are not in the MAME ROM set.** Chosen layout: 262 lines (60.11 Hz),
  **visible = counter lines 16–255** (display line = V − 16), VBLANK 256–15, VSYNC 0–2.
  Evidence: the game writes the playfield scroll registers ~10 lines after the 256V IRQ
  (traced in simulation). With visible = 0–239 the top 10 lines would show the previous
  frame's scroll (a tear MAME hides by rendering whole frames); with 16–255 the IRQ lands
  exactly at VBLANK start and all updates finish before the first visible line.
  Revisit if a PROM dump or a scope capture turns up.
- **RNG:** the main CPU's idle loop at DE95 is an LFSR stepped continuously between IRQs, so
  random numbers depend on exact CPU/video timing (and on real hardware, on the phase between
  the 10 MHz and 12.096 MHz crystals). Attract-mode demos therefore diverge from MAME after
  ~11 s; MAME also runs at 60.00 Hz rather than the schematic's 60.11 Hz.
- **Composite sync** = HSYNC XOR /VSYNC (8F LS86). `BLANK` = HBLANK | VBLANK | VIDOFF (13M/13L).
- **IRQ** (both CPUs): driven by 32V. Asserted while 32V = 0, cleared when 32V = 1 → four IRQ
  edges per frame. Each CPU has its own ack (main 1E00, sound 1000) that also clears it.

## Main CPU (6502 @ 2.5 MHz) — sheets 4B, 5A, 5B

| Address | R/W | Function |
|---|---|---|
| 0000–07FF | RW | Work RAM |
| 0800–08FF (mirror 0300) | RW | NOVRAM: 2 × X2212 (12B low nibble, 12C high nibble) |
| 0C00 (mirror 03FE) | R | IN0: b7 coin R, b6 coin L, b5 coin aux, b4 self-test (active low), b2 L thumb, b1 fire, b0 R thumb (active low) |
| 0C01 (mirror 03FE) | R | IN1: b7 VBLANK, b6 sound latch full, b5 sound-ack latch full, b2 slam (active high) |
| 1400 (mirror 03FF) | R | Sound→main acknowledge latch |
| 1800 (mirror 03FF) | R | ADC0809 result |
| 1C00/1C01 (mirror 007E) | W | NOVRAM recall enable/disable (A0) |
| 1C80–1C87 | W | ADC start, channel = A2..A0 (0 = vertical/Y, 2 = horizontal/X per MAME) |
| 1D00 | W | NOVRAM store |
| 1D80 | W | Watchdog clear |
| 1E00 | W | Main IRQ ack |
| 1E80–1E87 | W | LS259 outlatch (D7): 0 coin ctr L, 1 coin ctr R, 2/3 LEDs, 4 alpha bank, 6 sound CPU /reset, 7 video off |
| 1F00 | W | Main→sound command latch |
| 1F80 | W | ROM bank: D0→bank 0, D1→bank 1, D2→bank 2 |
| 2000–27FF | RW | Playfield RAM: 2000–23FF code low, 2400–27FF bank/flip bits (4 bits) |
| 2800–2FFF | RW | Colour RAM, 1024 × 12: 2800 low byte, 2C00 high nibble |
| 3000–37BF | RW | Alphanumerics RAM (64 × 30 tiles) |
| 37C0–3BFF | RW | Motion object RAM (48 sprites): +00 code, +40 flags, +80 Y, +100 X low |
| 3C00–3C01 | W | Playfield V scroll: data + A0 as bit 8 |
| 3D00–3D01 | W | Playfield H scroll: data + A0 as bit 8 |
| 3E00–3FFF | W | PIXI page select (smoothing table), low 2 bits used |
| 4000–7FFF | R | Banked ROM (3 × 16 KB) |
| 8000–FFFF | R | Fixed ROM |

## Sound CPU (6502 @ 1.512 MHz) — sheets 6A, 6B, 7A

| Address | R/W | Function |
|---|---|---|
| 0000–07FF | RW | RAM |
| 0800–083F (mirror 07C0) | RW | Quad-POKEY custom: 0800 / 0810 / 0820 / 0830 |
| 1000 | W | Sound IRQ ack |
| 1100 | W | TMS5220 data |
| 1200 / 1300 | W | TMS5220 /WS strobe on / off (A8) |
| 1400 | W | Sound→main acknowledge latch |
| 1500 | W | Speech chip enable (D0; gates TMS5220 power — treat as output mute) |
| 1800 (mirror 03FF) | R | Main→sound command latch |
| 1C00 | R | b7 = TMS5220 /READY |
| 1C01 | R | b7 command latch full, b6 ack latch full |
| 8000–FFFF | R | ROM (32 KB) |

Latch "full" flags: set on write, cleared when the other side reads (LS279 at 3E).

## Video pipeline (sheets 8A–11B, 12A; MAME `draw_*`)

There is **no priority logic**. Each pixel forms a 10-bit colour RAM address:
`A9..A8` = alphanumeric pixel, `A7..A4` = motion object pixel, `A3..A0` = playfield pixel.
The game programs the 1024-entry palette to fake priorities.

**Colour RAM word (12 bits)**: b0–2 blue, b3–5 green, b6–8 red, b9–11 intensity.
Output per gun ≈ `5 × gun × intensity` (0–245), via 22K/10K/4.7K resistor DAC (sheet 11B).

**Alphanumerics** (2 bpp, 8×8, no scroll): 64 columns × 30 rows at 3000. Tile code =
`alpha_bank << 8 | ram`. ROM 136030-215 (8 KB); each tile is 16 bytes, 2 bytes per row, 4 px/byte.

**Playfield** (4 bpp, 16×16 on screen from 8×8 source pixels doubled horizontally ×2 and
vertically ×2, scrollable, 32 × 32 tiles in a 512 × 512 map):
- `bg_offs = ((sy & 0x1F0) << 1) | ((sx & 0x1F0) >> 4)` where `sx = x + hscroll`, `sy = y + vscroll`.
- Code = `ram_lo | (bank&1)<<8 | (bank&8)<<6 | (bank&2)<<9` (11 bits); `bank&4` = X flip.
- ROMs 136030-126 / -127 (2 × 32 KB, one per bitplane pair).

**Smoothing (PIXI II)**: pixels processed in pairs. For the first pixel of each pair,
`t = PROM1[page][last_col<<4 | col]` (horizontal smoothing with the previous pixel), then both
pixels pass through `PROM2[page][linebuf[x]<<4 | pixel]` (vertical smoothing with the pixel
from the line above, held in the 2149 line buffer at 2A). `page` = PIXI register & 3.
PROMs 136030-117 / -118 (1 KB each as dumped; the schematic shows 2 KB parts).

**Motion objects**: 48 sprites, 8 px wide, 16 or 32 tall, 4 bpp, H/V flip, 9-bit X,
13-bit code (bank bits in flags b1, b2, b6). Colour 0 = transparent. Rendered through two
alternating horizontal line buffers (sheet 9B: 2149s at 4P/5P with LS163 address counters),
i.e. the classic "draw next line while displaying this one". ROMs 136030-128…131 (4 × 32 KB).
MAME's `-2` X and `240 - Y + 1` offsets are empirical and need checking against the hardware timing.

## ROMs and memory budget (DE10-Nano Cyclone V 5CSEBA6: ~553 M10K ≈ 553 KB as ×8)

| Region | Files | Size |
|---|---|---|
| Main CPU | 136030-221, -222, -123, -124, -122 | 80 KB |
| Sound CPU | 136030-133, -134 | 32 KB |
| Alphanumerics | 136030-215 | 8 KB |
| Playfield | 136030-126, -127 | 64 KB |
| Motion objects | 136030-128, -129, -130, -131 | 128 KB |
| Smoothing PROMs | 136030-117, -118 | 2 KB |
| **ROM total** | | **314 KB** |
| RAMs (work, sound, PF, colour, alpha, MO, line buffers, NOVRAM) | | ~12 KB |

Everything fits in block RAM with room for the MiSTer framework — **no SDRAM needed**.
ROMs are loaded via the MiSTer ioctl download from `jedi.zip` (MAME 0.289 set) using an MRA.

## Controls

Analogue flight yoke → ADC0809 channels (Y on 0, X on 2), centre 0x80. Three buttons
(L thumb, fire, R thumb). On MiSTer: analogue stick → ADC value, with digital-joystick fallback.

## Open questions

1. 9H sync PROM contents → exact VBLANK/VSYNC/line count (assume 262/240).
2. Exact HBLANK/HSYNC positions and sprite X/Y offsets relative to the counters.
3. Quad-POKEY custom vs 4 discrete POKEYs — assume identical to 4 × POKEY (MAME does).
4. X2212 NOVRAM store/recall semantics → map to MiSTer NVRAM save.
