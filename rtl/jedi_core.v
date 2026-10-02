// Atari Return of the Jedi (1984) — core logic.
// See docs/hardware.md for the memory maps and sources.
//
// Milestone 1: both CPUs, memory maps, CPU<->sound latches, IRQs, video timing,
// alphanumerics layer and colour RAM. Playfield, motion objects, POKEY, TMS5220 and
// PIXI smoothing are stubbed (contribute colour 0 / return 0).
//
// Clocking: single master clock of 48.384 MHz (4 x 12.096 MHz) with clock enables.
//   ce_pix  = 6.048 MHz (every 8 clocks)
//   ce_snd  = 1.512 MHz (every 32 clocks)
//   ce_main = 2.5 MHz  (fractional: 2500/48384; the 10 MHz main CPU crystal is independent)
//
// CPU bus convention (Arlet 6502 with RDY as clock enable): the CPU's address/WE/DO are
// stable for a whole enabled cycle; the data it reads is latched into m_di/s_di on the
// enable edge that ends the cycle, so DI holds data for the previous cycle's address,
// which is what the core expects from synchronous RAM.
module jedi_core #(
    parameter MAIN_ROM_INIT  = "",
    parameter SND_ROM_INIT   = "",
    parameter TX_ROM_INIT    = "",
    parameter BG1_ROM_INIT   = "",   // 136030-126 (playfield planes, first half)
    parameter BG2_ROM_INIT   = "",   // 136030-127
    parameter SPR1_ROM_INIT  = "",   // 136030-130 + -131
    parameter SPR2_ROM_INIT  = "",   // 136030-128 + -129
    parameter PROM1_INIT     = "",   // 136030-117 (horizontal smoothing)
    parameter PROM2_INIT     = "",   // 136030-118 (vertical smoothing)
    parameter V_START        = 16,   // first visible counter line (see jedi_timing.v)
    parameter NOVRAM_INIT    = "rtl/novram_init.hex"   // X2212 EEPROM defaults
) (
    input            clk,           // 48.384 MHz
    input            reset,

    // Inputs as the hardware sees them
    input      [7:0] in0,           // 0C00: b7 coin R, b6 coin L, b5 coin aux, b4 /self-test,
                                    //       b3 spare, b2 /L thumb, b1 /fire, b0 /R thumb
    input            tilt,          // slam switch, active high
    input      [7:0] adc_x,
    input      [7:0] adc_y,

    // Video
    output reg [7:0] red,
    output reg [7:0] green,
    output reg [7:0] blue,
    output reg       hsync,
    output reg       vsync,
    output reg       hblank,
    output reg       vblank,
    output           ce_pix,        // outputs above are valid when this is high
    output reg [8:0] vid_h,         // counter position of the current output pixel
    output reg [8:0] vid_v,

    // Audio: 4 x POKEY + TMS5220 speech, signed mono
    output signed [15:0] audio,

    // ROM download (MiSTer ioctl, MRA order - see docs/hardware.md)
    input     [18:0] dn_addr,
    input      [7:0] dn_data,
    input            dn_wr,

    // NOVRAM access for save/load (256 bytes)
    input      [7:0] nv_addr,
    input      [7:0] nv_din,
    input            nv_we,
    output     [7:0] nv_dout,        // reads the EEPROM half (see NOVRAM below)
    output           nv_changed,     // pulses when the game STOREs to the EEPROM

    // Cheats (MiSTer ioctl index 255): codes applied to main CPU reads
    input    [128:0] cheat_code,
    input            cheat_reset,

    // Debug
    output    [15:0] dbg_main_ab,
    output    [15:0] dbg_snd_ab,
    output     [7:0] dbg_outlatch
);

// ---------------------------------------------------------------------------
// Clock enables
// ---------------------------------------------------------------------------
reg  [2:0] pdiv = 0;
reg  [4:0] sdiv = 0;
reg [15:0] macc = 0;
wire [16:0] macc_next = {1'b0, macc} + 17'd2500;
wire ce_pix_int = pdiv == 3'd7;
wire ce_snd     = sdiv == 5'd31;
reg  [1:0] nv_op = 0;              // NOVRAM copy in progress: 0 idle, 1 store, 2 recall
wire       nv_busy = nv_op != 0;
wire ce_main_t  = macc_next >= 17'd48384;
wire ce_main    = ce_main_t & ~nv_busy;   // main CPU waits while the NOVRAM copies

always @(posedge clk) begin
    pdiv <= pdiv + 3'd1;
    sdiv <= sdiv + 5'd1;
    macc <= ce_main_t ? macc_next[15:0] - 16'd48384 : macc_next[15:0];
end

assign ce_pix = pdiv == 3'd0;   // one clock after outputs update

// ---------------------------------------------------------------------------
// Video timing and IRQ generation (32V)
// ---------------------------------------------------------------------------
wire [8:0] h, v, y;   // v = hardware line counter, y = display line (v - 16)
wire t_hblank, t_vblank, t_hsync, t_vsync;

jedi_timing #(.V_START(V_START)) timing (
    .clk(clk), .reset(reset), .ce_pix(ce_pix_int),
    .h(h), .v(v), .y(y),
    .hblank(t_hblank), .vblank(t_vblank), .hsync(t_hsync), .vsync(t_vsync)
);

reg v32_last = 0;
reg main_irq = 0, snd_irq = 0;
wire main_irq_ack, snd_irq_ack;

always @(posedge clk) begin
    v32_last <= v[5];
    if (reset) begin
        main_irq <= 0;
        snd_irq  <= 0;
    end else begin
        // Asserted while 32V is low (MAME: lines 64,128,192,256 assert; 32,96,... clear)
        if (v32_last && !v[5]) begin main_irq <= 1; snd_irq <= 1; end
        if (!v32_last && v[5]) begin main_irq <= 0; snd_irq <= 0; end
        if (main_irq_ack) main_irq <= 0;
        if (snd_irq_ack)  snd_irq  <= 0;
    end
end

// ---------------------------------------------------------------------------
// Main CPU
// ---------------------------------------------------------------------------
wire [15:0] m_ab;
wire  [7:0] m_do;
wire        m_we;
reg   [7:0] m_di = 0;

cpu main_cpu (
    .clk(clk), .reset(reset),
    .AB(m_ab), .DI(m_di), .DO(m_do), .WE(m_we),
    .IRQ(main_irq), .NMI(1'b0), .RDY(ce_main)
);

wire m_wr = ce_main & m_we;
wire m_rd = ce_main & ~m_we;

wire m_sel_ram   = m_ab[15:11] == 5'b00000;             // 0000-07FF
wire m_sel_nov   = m_ab[15:10] == 6'b000010;            // 0800-0BFF
wire m_sel_in    = m_ab[15:10] == 6'b000011;            // 0C00-0FFF
wire m_sel_sack  = m_ab[15:10] == 6'b000101;            // 1400-17FF
wire m_sel_adc   = m_ab[15:10] == 6'b000110;            // 1800-1BFF
wire m_sel_ctl   = m_ab[15:10] == 6'b000111;            // 1C00-1FFF
wire m_sel_pf    = m_ab[15:11] == 5'b00100;             // 2000-27FF
wire m_sel_col   = m_ab[15:11] == 5'b00101;             // 2800-2FFF
wire m_sel_alpha = m_ab[15:12] == 4'h3 && m_ab[11:10] != 2'b11; // 3000-3BFF
wire m_sel_vctl  = m_ab[15:10] == 6'b001111;            // 3C00-3FFF
wire m_sel_rom   = m_ab[15:14] != 2'b00;                // 4000-FFFF

// Main work RAM
wire [7:0] m_ram_q;
dpram #(.AW(11)) main_ram (
    .clk(clk),
    .a_addr(m_ab[10:0]), .a_din(m_do), .a_we(m_wr & m_sel_ram), .a_dout(m_ram_q),
    .b_addr(11'd0), .b_din(8'd0), .b_we(1'b0), .b_dout()
);

// NOVRAM: 2 x X2212 (256 x 4 each, together 256 x 8). Each X2212 is a static RAM (what
// the CPU reads and writes) shadowed by an EEPROM:
//   STORE  (write 1D00)        copies RAM -> EEPROM
//   RECALL (write 1C00, reset) copies EEPROM -> RAM
// The game relies on this: the self-test overwrites the RAM half and recalls afterwards,
// and option changes are made permanent with STORE. The MiSTer saves/loads the EEPROM.
// The main CPU is held for the ~260 clocks (5 us) a copy takes.
//
// EEPROM defaults (rtl/novram_init.hex) start from MAME's fill (0x0F, 0x50-0x5F zero),
// but all-zero data has a *valid* checksum in the small blocks, so:
//  - stats (50-54, checksum 5C) and options (55-56, checksum 5D) get checksum FF, making
//    the game install its own factory settings on first boot;
//  - the yoke calibration (57-5A: X min/max, Y min/max; checksum 5E, routine DF38) gets a
//    valid centred 11/EF (checksum 02). With zeros the game loads min = max = 0, the
//    steering window wraps and the bike sticks until the stick is swept both ways.
//    11/EF matches the 0x10-0xEF range the MiSTer yoke is scaled to.
reg  [8:0] nv_cnt = 0;           // nv_op / nv_busy are declared with the clock enables
// Copy pipeline: while nv_cnt = k the source RAM is addressed with k, and its registered
// output holds byte k-1, which is written to the destination at address k-1.
wire [7:0] nv_cpy_rd = nv_cnt[7:0];
wire [8:0] nv_cnt_m1 = nv_cnt - 9'd1;
wire [7:0] nv_cpy_wr = nv_cnt_m1[7:0];
wire       nv_cpy_we = nv_busy && nv_cnt >= 9'd1;
wire [7:0] nv_sram_b_q, nv_eep_a_q;
wire [7:0] m_nov_q;

dpram #(.AW(8)) novram_sram (
    .clk(clk),
    .a_addr(m_ab[7:0]), .a_din(m_do), .a_we(m_wr & m_sel_nov), .a_dout(m_nov_q),
    .b_addr(nv_op == 2'd2 ? nv_cpy_wr : nv_cpy_rd), .b_din(nv_eep_a_q),
    .b_we(nv_op == 2'd2 && nv_cpy_we), .b_dout(nv_sram_b_q)
);
dpram #(.AW(8), .INIT(NOVRAM_INIT)) novram_eeprom (
    .clk(clk),
    .a_addr(nv_op == 2'd1 ? nv_cpy_wr : nv_cpy_rd), .a_din(nv_sram_b_q),
    .a_we(nv_op == 2'd1 && nv_cpy_we), .a_dout(nv_eep_a_q),
    .b_addr(nv_addr), .b_din(nv_din), .b_we(nv_we), .b_dout(nv_dout)   // MiSTer save/load
);

reg reset_last = 1;
wire nv_store_req  = m_wr & m_sel_ctl & (m_ab[9:7] == 3'b010);              // 1D00
wire nv_recall_req = (m_wr & m_sel_ctl & (m_ab[9:7] == 3'b000) & ~m_ab[0])  // 1C00
                   | (reset_last & ~reset);                                 // end of reset
reg nv_stored = 0;
always @(posedge clk) begin
    reset_last <= reset;
    nv_stored  <= 0;
    if (nv_busy) begin
        nv_cnt <= nv_cnt + 9'd1;
        if (nv_cnt == 9'd256) begin      // byte 255 written on this clock
            nv_stored <= nv_op == 2'd1;
            nv_op <= 0;
        end
    end else if (nv_store_req | nv_recall_req) begin
        nv_op  <= nv_store_req ? 2'd1 : 2'd2;
        nv_cnt <= 0;
    end
end
assign nv_changed = nv_stored;   // EEPROM updated -> MiSTer autosave

// ROM download decode
wire [18:0] dn_snd_a  = dn_addr - 19'h14000;
wire [18:0] dn_tx_a   = dn_addr - 19'h1C000;
wire [18:0] dn_bg1_a  = dn_addr - 19'h1E000;
wire [18:0] dn_bg2_a  = dn_addr - 19'h26000;
wire [18:0] dn_spr1_a = dn_addr - 19'h2E000;
wire [18:0] dn_spr2_a = dn_addr - 19'h3E000;
wire [18:0] dn_prm_a  = dn_addr - 19'h4E000;
wire dn_main = dn_wr && dn_addr < 19'h14000;
wire dn_snd  = dn_wr && dn_addr >= 19'h14000 && dn_addr < 19'h1C000;
wire dn_tx   = dn_wr && dn_addr >= 19'h1C000 && dn_addr < 19'h1E000;
wire dn_bg1  = dn_wr && dn_addr >= 19'h1E000 && dn_addr < 19'h26000;
wire dn_bg2  = dn_wr && dn_addr >= 19'h26000 && dn_addr < 19'h2E000;
wire dn_spr1 = dn_wr && dn_addr >= 19'h2E000 && dn_addr < 19'h3E000;
wire dn_spr2 = dn_wr && dn_addr >= 19'h3E000 && dn_addr < 19'h4E000;
wire dn_prm1 = dn_wr && dn_addr >= 19'h4E000 && dn_addr < 19'h4E400;
wire dn_prm2 = dn_wr && dn_addr >= 19'h4E400 && dn_addr < 19'h4E800;

// Playfield RAM 2000-27FF: 000-3FF tile code low, 400-7FF bank/flip bits
reg  [10:0] pf_vaddr = 0;
wire  [7:0] m_pf_q, pf_q;
dpram #(.AW(11)) pf_ram (
    .clk(clk),
    .a_addr(m_ab[10:0]), .a_din(m_do), .a_we(m_wr & m_sel_pf), .a_dout(m_pf_q),
    .b_addr(pf_vaddr), .b_din(8'd0), .b_we(1'b0), .b_dout(pf_q)
);

// Colour RAM: 2800-2BFF low byte, 2C00-2FFF high nibble
reg  [9:0] col_addr = 0;
wire [7:0] m_col_lo_q, m_col_hi_q, col_lo, col_hi;
dpram #(.AW(10)) col_ram_lo (
    .clk(clk),
    .a_addr(m_ab[9:0]), .a_din(m_do), .a_we(m_wr & m_sel_col & ~m_ab[10]), .a_dout(m_col_lo_q),
    .b_addr(col_addr), .b_din(8'd0), .b_we(1'b0), .b_dout(col_lo)
);
dpram #(.AW(10)) col_ram_hi (
    .clk(clk),
    .a_addr(m_ab[9:0]), .a_din(m_do), .a_we(m_wr & m_sel_col & m_ab[10]), .a_dout(m_col_hi_q),
    .b_addr(col_addr), .b_din(8'd0), .b_we(1'b0), .b_dout(col_hi)
);

// Alphanumerics + motion object RAM 3000-3BFF
reg  [11:0] tx_ram_addr = 0;
wire  [7:0] m_alpha_q, tx_code;
dpram #(.AW(12)) alpha_ram (
    .clk(clk),
    .a_addr(m_ab[11:0]), .a_din(m_do), .a_we(m_wr & m_sel_alpha), .a_dout(m_alpha_q),
    .b_addr(tx_ram_addr), .b_din(8'd0), .b_we(1'b0), .b_dout(tx_code)
);

// Private copy of the motion object area (37C0-3BFF) for the sprite engine, so it does
// not compete with the alphanumerics fetch for the alpha RAM video port.
// Copy address = alpha offset - 0x400: code 3C0+n, flags 400+n, Y 440+n, X 4C0+n.
wire [11:0] m_alpha_off = m_ab[11:0];
wire [11:0] m_mo_off    = m_alpha_off - 12'h400;
reg  [10:0] mo_vaddr = 0;
wire  [7:0] mo_q;
dpram #(.AW(11)) mo_ram (
    .clk(clk),
    .a_addr(m_mo_off[10:0]), .a_din(m_do), .a_we(m_wr & m_sel_alpha & (m_alpha_off >= 12'h400)), .a_dout(),
    .b_addr(mo_vaddr), .b_din(8'd0), .b_we(1'b0), .b_dout(mo_q)
);

// Program ROM: 5 x 16 KB = 221 (8000), 222 (C000), 123/124/122 (banks 0-2 at 4000)
reg  [1:0] rom_bank = 0;
wire [2:0] rom_page = m_ab[15:14] == 2'b10 ? 3'd0 :
                      m_ab[15:14] == 2'b11 ? 3'd1 : 3'd2 + {1'b0, rom_bank};
wire [7:0] m_rom_q;
dpram #(.AW(17), .DEPTH(5 * 16384), .INIT(MAIN_ROM_INIT)) main_rom (
    .clk(clk),
    .a_addr({rom_page, m_ab[13:0]}), .a_din(8'd0), .a_we(1'b0), .a_dout(m_rom_q),
    .b_addr(dn_addr[16:0]), .b_din(dn_data), .b_we(dn_main), .b_dout()
);

// Latches between the CPUs (5E/4E LS374 + 3E LS279 flags)
reg  [7:0] sound_latch = 0, sack_latch = 0;
reg        sound_full = 0, sack_full = 0;

// Output latch 14J (LS259): 0/1 coin counters, 2/3 LEDs, 4 alpha bank, 6 sound /reset, 7 video off
reg  [7:0] outlatch = 0;
wire       alpha_bank = outlatch[4];
wire       video_off  = outlatch[7];

reg  [2:0] adc_chan = 0;
reg  [8:0] vscroll = 0, hscroll = 0;
reg  [1:0] pixi_page = 0;

assign main_irq_ack = m_wr & m_sel_ctl & (m_ab[9:7] == 3'b100);

wire [7:0] m_in1 = {t_vblank, sound_full, sack_full, 2'b11, tilt, 2'b11};
wire [7:0] m_adc_q = adc_chan == 3'd0 ? adc_y : adc_chan == 3'd2 ? adc_x : 8'h00;

wire [7:0] m_bus_q =
    m_sel_ram   ? m_ram_q :
    m_sel_nov   ? m_nov_q :
    m_sel_in    ? (m_ab[0] ? m_in1 : in0) :
    m_sel_sack  ? sack_latch :
    m_sel_adc   ? m_adc_q :
    m_sel_pf    ? m_pf_q :
    m_sel_col   ? (m_ab[10] ? m_col_hi_q : m_col_lo_q) :
    m_sel_alpha ? m_alpha_q :
    m_sel_rom   ? m_rom_q : 8'hff;

wire [7:0] m_bus_cheat;
jedi_cheats cheats (
    .clk(clk), .reset(cheat_reset), .code(cheat_code),
    .addr(m_ab), .din(m_bus_q), .dout(m_bus_cheat)
);

always @(posedge clk) if (ce_main) m_di <= m_bus_cheat;

// ---------------------------------------------------------------------------
// Sound CPU
// ---------------------------------------------------------------------------
wire [15:0] s_ab;
wire  [7:0] s_do;
wire        s_we;
reg   [7:0] s_di = 0;
wire        s_reset = reset | ~outlatch[6];

cpu snd_cpu (
    .clk(clk), .reset(s_reset),
    .AB(s_ab), .DI(s_di), .DO(s_do), .WE(s_we),
    .IRQ(snd_irq), .NMI(1'b0), .RDY(ce_snd)
);

wire s_wr = ce_snd & s_we;
wire s_rd = ce_snd & ~s_we;

wire s_sel_ram   = s_ab[15:11] == 5'b00000;   // 0000-07FF
wire s_sel_pokey = s_ab[15:11] == 5'b00001;   // 0800-0FFF (4 x POKEY, 16 regs each, mirrored)
wire s_sel_io1   = s_ab[15:11] == 5'b00010;   // 1000-17FF writes
wire s_sel_io2   = s_ab[15:11] == 5'b00011;   // 1800-1FFF reads
wire s_sel_rom   = s_ab[15];                  // 8000-FFFF

assign snd_irq_ack = s_wr & s_sel_io1 & (s_ab[10:8] == 3'b000);

wire [7:0] s_ram_q, s_rom_q;
dpram #(.AW(11)) snd_ram (
    .clk(clk),
    .a_addr(s_ab[10:0]), .a_din(s_do), .a_we(s_wr & s_sel_ram), .a_dout(s_ram_q),
    .b_addr(11'd0), .b_din(8'd0), .b_we(1'b0), .b_dout()
);
dpram #(.AW(15), .INIT(SND_ROM_INIT)) snd_rom (
    .clk(clk),
    .a_addr(s_ab[14:0]), .a_din(8'd0), .a_we(1'b0), .a_dout(s_rom_q),
    .b_addr(dn_snd_a[14:0]), .b_din(dn_data), .b_we(dn_snd), .b_dout()
);

// ---- TMS5220 speech (sheet 7A) ----------------------------------------------
// 1100 data latch (4D), 1200/1300 /WS strobe on/off (A8), 1500 D0 = speech enable
// (gates the chip's supply on the real board; modelled as output mute),
// 1C00 b7 = /READY. Clock 12.096 MHz / 2 / 9 = 672 kHz = 48.384 MHz / 72.
reg  [6:0] tms_div = 0;
wire       tms_ce = tms_div == 7'd71;
always @(posedge clk) tms_div <= tms_ce ? 7'd0 : tms_div + 7'd1;

reg  [7:0] speech_data = 0;
reg        speech_ws_n = 1;
reg        speech_en = 0;
wire       speech_ready_n;
wire signed [13:0] speech_out;

`ifdef VERILATOR
// Simulation speed-up: give the (large, netlisted) TMS5220 its own 672 kHz clock so
// the simulator evaluates it once per chip clock instead of on every 48 MHz clock.
reg tms_clk = 0;
always @(posedge clk) if (tms_div == 7'd35 || tms_ce) tms_clk <= ~tms_clk;
wire tms_osc = tms_clk;
wire tms_ena = 1'b1;
`else
wire tms_osc = clk;
wire tms_ena = tms_ce;
`endif

TMS5220 tms (
    .I_OSC(tms_osc), .I_ENA(tms_ena),
    .I_WSn(speech_ws_n), .I_RSn(1'b1), .I_DATA(1'b1), .I_TEST(1'b1),
    .I_DBUS(speech_data), .O_DBUS(),
    .O_RDYn(speech_ready_n), .O_INTn(),
    .O_M0(), .O_M1(), .O_ADD8(), .O_ADD4(), .O_ADD2(), .O_ADD1(), .O_ROMCLK(),
    .O_T11(), .O_IO(), .O_PRMOUT(),
    .O_SPKR(speech_out)
);

// Quad POKEY custom at 0800-083F: chip = A5..A4, register = A3..A0 (mirrored)
wire [7:0] pokey_q [0:3];
wire [5:0] pokey_audio [0:3];
genvar gp;
generate for (gp = 0; gp < 4; gp = gp + 1) begin : pokeys
    pokey pokey_i (
        .clk(clk), .ce(ce_snd), .reset(s_reset),
        .addr(s_ab[3:0]), .din(s_do),
        .we(s_wr & s_sel_pokey & (s_ab[5:4] == gp)),
        .dout(pokey_q[gp]), .audio(pokey_audio[gp])
    );
end endgenerate

// Mix: POKEY sum 0..240 -> +/-7680 around zero; speech is 14-bit signed.
// Relative levels are provisional (to be matched against MAME's mixer).
wire [7:0]  pokey_sum = pokey_audio[0] + pokey_audio[1] + pokey_audio[2] + pokey_audio[3];
wire signed [15:0] pokey_s = $signed({2'b0, pokey_sum, 6'd0}) - 16'sd7680;
wire signed [15:0] speech_s = (speech_en & ~s_reset) ? {{2{speech_out[13]}}, speech_out} : 16'sd0;
assign audio = pokey_s + speech_s;

wire [7:0] s_bus_q =
    s_sel_ram   ? s_ram_q :
    s_sel_pokey ? pokey_q[s_ab[5:4]] :
    s_sel_io2   ? (!s_ab[10] ? sound_latch :
                   !s_ab[0]  ? {speech_ready_n, 7'd0} :
                               {sound_full, sack_full, 6'd0}) :
    s_sel_rom   ? s_rom_q : 8'hff;

always @(posedge clk) if (ce_snd) s_di <= s_bus_q;

// ---------------------------------------------------------------------------
// Register writes and side-effect reads (both CPUs)
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        outlatch    <= 0;
        rom_bank    <= 0;
        sound_full  <= 0;
        sack_full   <= 0;
    end else begin
        // Main CPU writes 1C00-1FFF
        if (m_wr & m_sel_ctl) case (m_ab[9:7])
            3'b001: adc_chan <= m_ab[2:0];                          // 1C80 start A/D
            3'b101: outlatch[m_ab[2:0]] <= m_do[7];                 // 1E80 LS259
            3'b110: begin sound_latch <= m_do; sound_full <= 1; end // 1F00
            3'b111: begin                                           // 1F80 bank select
                if (m_do[0]) rom_bank <= 2'd0;
                if (m_do[1]) rom_bank <= 2'd1;
                if (m_do[2]) rom_bank <= 2'd2;
            end
            default: ;   // NOVRAM recall/store, watchdog, IRQ ack handled elsewhere
        endcase

        // Main CPU writes 3C00-3FFF
        if (m_wr & m_sel_vctl) case (m_ab[9:8])
            2'b00:   vscroll   <= {m_ab[0], m_do};
            2'b01:   hscroll   <= {m_ab[0], m_do};
            default: pixi_page <= m_do[1:0];
        endcase

        // Main CPU reads the sound acknowledge latch -> clear its flag
        if (m_rd & m_sel_sack) sack_full <= 0;

        // Sound CPU speech writes: 1100 data, 1200/1300 strobe, 1500 enable
        if (s_wr & s_sel_io1) case (s_ab[10:8])
            3'b001: speech_data <= s_do;
            3'b010: speech_ws_n <= 0;
            3'b011: speech_ws_n <= 1;
            3'b101: speech_en   <= s_do[0];
            default: ;
        endcase

        // Sound CPU writes 1000-17FF
        if (s_wr & s_sel_io1 && s_ab[10:8] == 3'b100) begin
            sack_latch <= s_do;
            sack_full  <= 1;
        end

        // Sound CPU reads the command latch -> clear its flag
        if (s_rd & s_sel_io2 & ~s_ab[10]) sound_full <= 0;
    end
end

// ---------------------------------------------------------------------------
// Video
//
// Eight master clocks per pixel slot. Pixel p (counter value h = p) is assembled over
// three slots and output at the end of slot p+2:
//   slot p   : alphanumerics fetch; playfield pair engine (pairs p&~1, p|1) runs across
//              the two slots of the pair
//   slot p+1 : motion object line buffer read (and clear) for p
//   slot p+2 : colour RAM lookup {alpha, MO, PF} -> RGB, registered on the slot's last clock
// hsync/vsync/blanking and vid_h/vid_v are delayed to match.
// ---------------------------------------------------------------------------
localparam V_TOTAL = 262;

reg [8:0] h_d1 = 0, h_d2 = 0, v_d1 = 0, v_d2 = 0;
reg [3:0] hb_d, vb_d, hs_d, vs_d;   // [0] = 1 slot, [1] = 2 slots
always @(posedge clk) if (ce_pix_int) begin
    h_d1 <= h;  h_d2 <= h_d1;
    v_d1 <= y;  v_d2 <= v_d1;   // display line
    hb_d <= {hb_d[2:0], t_hblank};
    vb_d <= {vb_d[2:0], t_vblank};
    hs_d <= {hs_d[2:0], t_hsync};
    vs_d <= {vs_d[2:0], t_vsync};
end

// ---- Alphanumerics (2 bpp 8x8, 64 x 30, no scroll) --------------------------
reg  [12:0] tx_rom_addr = 0;
wire  [7:0] tx_gfx;
dpram #(.AW(13), .INIT(TX_ROM_INIT)) tx_rom (
    .clk(clk),
    .a_addr(tx_rom_addr), .a_din(8'd0), .a_we(1'b0), .a_dout(tx_gfx),
    .b_addr(dn_tx_a[12:0]), .b_din(dn_data), .b_we(dn_tx), .b_dout()
);

// 4 pixels per byte, leftmost in the MSBs
wire [1:0] tx_pix = h[1:0] == 2'd0 ? tx_gfx[7:6] :
                    h[1:0] == 2'd1 ? tx_gfx[5:4] :
                    h[1:0] == 2'd2 ? tx_gfx[3:2] : tx_gfx[1:0];
reg  [1:0] tx_d1 = 0, tx_d2 = 0;

always @(posedge clk) begin
    case (pdiv)
        3'd0: tx_ram_addr <= {1'b0, y[7:3], h[8:3]};
        3'd2: tx_rom_addr <= {alpha_bank, tx_code, y[2:0], h[2]};   // 16 bytes/tile
        default: ;
    endcase
    if (ce_pix_int) begin tx_d1 <= tx_pix; tx_d2 <= tx_d1; end
end

// ---- Playfield + PIXI smoothing ---------------------------------------------
// 512 x 512 scrolling map of 16x16 tiles (8x8 source pixels doubled both ways), 4 bpp.
// Processed per pixel pair (MAME draw_background_and_text). t = step within the pair.
wire [3:0] pf_t  = {h[0], pdiv};
wire [8:0] pf_xe = {h[8:1], 1'b0};
wire [8:0] pf_sx = pf_xe + hscroll;
wire [8:0] pf_sy = y + vscroll;

reg  [14:0] bg_addr = 0;
wire  [7:0] bg1_q, bg2_q;
dpram #(.AW(15), .INIT(BG1_ROM_INIT)) bg1_rom (
    .clk(clk), .a_addr(bg_addr), .a_din(8'd0), .a_we(1'b0), .a_dout(bg1_q),
    .b_addr(dn_bg1_a[14:0]), .b_din(dn_data), .b_we(dn_bg1), .b_dout()
);
dpram #(.AW(15), .INIT(BG2_ROM_INIT)) bg2_rom (
    .clk(clk), .a_addr(bg_addr), .a_din(8'd0), .a_we(1'b0), .a_dout(bg2_q),
    .b_addr(dn_bg2_a[14:0]), .b_din(dn_data), .b_we(dn_bg2), .b_dout()
);

// 82S137 smoothing PROMs, 4 pages of 256 x 4 selected by the PIXI register
reg  [9:0] prom1_addr = 0, prom2_addr = 0;
wire [7:0] prom1_q, prom2_q;
dpram #(.AW(10), .INIT(PROM1_INIT)) prom1 (
    .clk(clk), .a_addr(prom1_addr), .a_din(8'd0), .a_we(1'b0), .a_dout(prom1_q),
    .b_addr(dn_prm_a[9:0]), .b_din(dn_data), .b_we(dn_prm1), .b_dout()
);
dpram #(.AW(10), .INIT(PROM2_INIT)) prom2 (
    .clk(clk), .a_addr(prom2_addr), .a_din(8'd0), .a_we(1'b0), .a_dout(prom2_q),
    .b_addr(dn_prm_a[9:0]), .b_din(dn_data), .b_we(dn_prm2), .b_dout()
);

// PIXI II line buffer (2149 at 2A): previous line's pre-smoothed pixels
reg  [8:0] pxl_raddr = 0, pxl_waddr = 0;
reg  [3:0] pxl_wdata = 0;
reg        pxl_we = 0;
wire [7:0] pxl_q;
dpram #(.AW(9)) pixi_line (
    .clk(clk),
    .a_addr(pxl_waddr), .a_din({4'd0, pxl_wdata}), .a_we(pxl_we), .a_dout(),
    .b_addr(pxl_raddr), .b_din(8'd0), .b_we(1'b0), .b_dout(pxl_q)
);
wire [3:0] pxl_prev = y == 0 ? 4'd0 : pxl_q[3:0];   // MAME clears it at the top of the frame

reg  [7:0] pf_code_lo = 0;
reg  [1:0] pf_pixsel = 0;
reg  [3:0] bg_col = 0, bg_last = 0;
reg  [3:0] pf_even = 0, pf_odd = 0;

// Pixel select within the two bitplane bytes: {d1[7-s], d1[3-s], d2[7-s], d2[3-s]}
wire [3:0] bg_pix = pf_pixsel == 2'd0 ? {bg1_q[7], bg1_q[3], bg2_q[7], bg2_q[3]} :
                    pf_pixsel == 2'd1 ? {bg1_q[6], bg1_q[2], bg2_q[6], bg2_q[2]} :
                    pf_pixsel == 2'd2 ? {bg1_q[5], bg1_q[1], bg2_q[5], bg2_q[1]} :
                                        {bg1_q[4], bg1_q[0], bg2_q[4], bg2_q[0]};

always @(posedge clk) begin
    pxl_we <= 0;
    case (pf_t)
        4'd0: pf_vaddr <= {1'b0, pf_sy[8:4], pf_sx[8:4]};          // tile code low
        4'd1: pf_vaddr <= {1'b1, pf_sy[8:4], pf_sx[8:4]};          // bank/flip bits
        4'd2: pf_code_lo <= pf_q;
        4'd3: begin                                                  // pf_q = bank byte
            // code = {b1, b3, b0, lo}; b2 = X flip (sx ^= 0x0F)
            bg_addr   <= {pf_q[1], pf_q[3], pf_q[0], pf_code_lo, pf_sy[3:1], pf_sx[3] ^ pf_q[2]};
            pf_pixsel <= pf_sx[2:1] ^ {2{pf_q[2]}};
        end
        4'd5: begin
            bg_col     <= bg_pix;
            prom1_addr <= {pixi_page, bg_last, bg_pix};             // horizontal smoothing
            pxl_raddr  <= pf_xe;
        end
        4'd7: begin
            prom2_addr <= {pixi_page, pxl_prev, prom1_q[3:0]};      // vertical smoothing
            pxl_raddr  <= pf_xe + 9'd1;
            pxl_waddr  <= pf_xe;
            pxl_wdata  <= prom1_q[3:0];
            pxl_we     <= 1;
        end
        4'd9: begin
            pf_even    <= prom2_q[3:0];
            prom2_addr <= {pixi_page, pxl_prev, bg_col};
            pxl_waddr  <= pf_xe + 9'd1;
            pxl_wdata  <= bg_col;
            pxl_we     <= 1;
            bg_last    <= bg_col;
        end
        4'd11: pf_odd <= prom2_q[3:0];
        default: ;
    endcase
    if (pf_t == 4'd0 && h == 0) bg_last <= 0;   // start of line
end

// ---- Motion objects ---------------------------------------------------------
// 48 sprites, 8 wide, 16 or 32 tall, 4 bpp. During line v the engine renders line v+1
// into one half of a double line buffer while the other half is displayed and cleared.
reg  [15:0] spr_addr = 0;
wire  [7:0] spr1_q, spr2_q;
dpram #(.AW(16), .INIT(SPR1_ROM_INIT)) spr1_rom (
    .clk(clk), .a_addr(spr_addr), .a_din(8'd0), .a_we(1'b0), .a_dout(spr1_q),
    .b_addr(dn_spr1_a[15:0]), .b_din(dn_data), .b_we(dn_spr1), .b_dout()
);
dpram #(.AW(16), .INIT(SPR2_ROM_INIT)) spr2_rom (
    .clk(clk), .a_addr(spr_addr), .a_din(8'd0), .a_we(1'b0), .a_dout(spr2_q),
    .b_addr(dn_spr2_a[15:0]), .b_din(dn_data), .b_we(dn_spr2), .b_dout()
);

reg  [9:0] mol_waddr = 0, mol_raddr = 0;
reg  [3:0] mol_wdata = 0;
reg        mol_we = 0, mol_clr = 0;
wire [7:0] mol_q;
dpram #(.AW(10)) mo_line (
    .clk(clk),
    .a_addr(mol_waddr), .a_din({4'd0, mol_wdata}), .a_we(mol_we), .a_dout(),
    .b_addr(mol_raddr), .b_din(8'd0), .b_we(mol_clr), .b_dout(mol_q)
);

// Renderer. Kicked off on the clock that ends counter line v (about to wrap to v+1),
// so it renders counter line v+2 while v+1 is displayed. Only visible lines
// (counter 16..255) are rendered; the target is expressed as a display line.
wire [9:0] mo_v2  = {1'b0, v} + 10'd2;
wire [8:0] mo_v2w = mo_v2 >= V_TOTAL ? mo_v2 - V_TOTAL : mo_v2[8:0];
wire [8:0] mo_line_next = mo_v2w - V_START;   // >= 240 (incl. wrap) = not visible
reg  [7:0] mo_target = 0;           // screen line being rendered (only lines < 240)
reg        mo_busy = 0;
reg  [5:0] mo_n = 0;                // sprite number
reg  [4:0] mo_st = 0;
reg  [7:0] sp_y = 0, sp_flags = 0, sp_code = 0;
reg  [8:0] sp_x0 = 0;
reg  [7:0] d1a = 0, d2a = 0, d1b = 0, d2b = 0;

wire       sp_tall  = sp_flags[3];
wire       sp_flipx = sp_flags[4];
wire       sp_flipy = sp_flags[5];
wire [7:0] sp_top   = 8'd241 - sp_y - (sp_tall ? 8'd16 : 8'd0);
wire [7:0] sp_dy    = mo_target - sp_top;
wire [5:0] sp_size  = sp_tall ? 6'd32 : 6'd16;
wire [4:0] sp_row   = sp_flipy ? sp_size[4:0] - 5'd1 - sp_dy[4:0] : sp_dy[4:0];
wire [10:0] sp_code_full = {sp_flags[2], sp_flags[6], sp_flags[1], sp_code[7:1],
                            sp_code[0] & ~sp_tall};
wire [15:0] sp_gfx = {sp_code_full, 5'd0} + {10'd0, sp_row, 1'b0};

// Pixel j (0..7) of the current row, bits 7..4 of the colour RAM address
wire [2:0] mo_j = mo_st[2:0];       // pixel index during states 16..23
wire [7:0] pd1  = mo_j[2] ? d1b : d1a;
wire [7:0] pd2  = mo_j[2] ? d2b : d2a;
wire [1:0] pk   = mo_j[1:0];
wire [3:0] mo_pix_col = {pd1[7 - pk], pd1[3 - pk], pd2[7 - pk], pd2[3 - pk]};
wire [8:0] mo_pos = sp_flipx ? sp_x0 + 9'd7 - {6'd0, mo_j} : sp_x0 + {6'd0, mo_j};

always @(posedge clk) begin
    mol_we <= 0;
    if (ce_pix_int && h == 9'd383) begin      // start rendering the next line
        mo_busy   <= mo_line_next < 9'd240;
        mo_target <= mo_line_next[7:0];
        mo_n      <= 0;
        mo_st     <= 0;
    end else if (mo_busy) begin
        mo_st <= mo_st + 5'd1;
        case (mo_st)
            5'd0:  mo_vaddr <= 11'h440 + mo_n;                 // Y
            5'd1:  mo_vaddr <= 11'h400 + mo_n;                 // flags
            5'd2:  begin sp_y <= mo_q; mo_vaddr <= 11'h3C0 + mo_n; end   // code
            5'd3:  begin sp_flags <= mo_q; mo_vaddr <= 11'h4C0 + mo_n; end // X low
            5'd4:  sp_code <= mo_q;
            5'd5:  sp_x0 <= {sp_flags[0], mo_q} - 9'd2;
            5'd6:  if (sp_dy >= {2'b0, sp_size}) begin         // not on this line
                       mo_st <= 0;
                       mo_n  <= mo_n + 6'd1;
                       if (mo_n == 6'd47) mo_busy <= 0;
                   end else
                       spr_addr <= sp_gfx;
            5'd7:  spr_addr <= sp_gfx + 16'd1;
            5'd8:  begin d1a <= spr1_q; d2a <= spr2_q; end
            5'd9:  begin d1b <= spr1_q; d2b <= spr2_q; mo_st <= 5'd16; end
            5'd23: begin
                       mo_st <= 0;
                       mo_n  <= mo_n + 6'd1;
                       if (mo_n == 6'd47) mo_busy <= 0;
                   end
            default: ;
        endcase
        // States 16..23 write pixels 0..7 (transparent colour 0 is skipped;
        // later sprites overwrite earlier ones, as in MAME)
        if (mo_st[4] && mo_pix_col != 0) begin
            mol_waddr <= {mo_target[0], mo_pos};
            mol_wdata <= mo_pix_col;
            mol_we    <= 1;
        end
    end
end

// Display side: read pixel h_d1 of line v_d1 during slot p+1, then clear it
reg [3:0] mo_cur = 0;
always @(posedge clk) begin
    mol_clr <= 0;
    case (pdiv)
        3'd0: mol_raddr <= {v_d1[0], h_d1};
        3'd2: begin
            mo_cur  <= mol_q[3:0];
            mol_clr <= h_d1 < 9'd296;
        end
        default: ;
    endcase
end

// ---- Colour RAM lookup and output --------------------------------------------
// No priority logic: {alpha[1:0], MO[3:0], PF[3:0]} addresses the 1024-entry palette.
wire [3:0] pf_cur = h_d2[0] ? pf_odd : pf_even;

always @(posedge clk)
    if (pdiv == 3'd0) col_addr <= {tx_d2, mo_cur, pf_cur};

// IRGB 3-3-3-3: gun = 5 * value * intensity (0..245)
wire [2:0] c_i = col_hi[3:1];
wire [2:0] c_r = {col_hi[0], col_lo[7:6]};
wire [2:0] c_g = col_lo[5:3];
wire [2:0] c_b = col_lo[2:0];
wire [5:0] r_x = c_r * c_i, g_x = c_g * c_i, b_x = c_b * c_i;

always @(posedge clk) begin
    if (ce_pix_int) begin
        if (video_off | hb_d[1] | vb_d[1]) begin
            red <= 0; green <= 0; blue <= 0;
        end else begin
            red   <= {2'b0, r_x} * 8'd5;
            green <= {2'b0, g_x} * 8'd5;
            blue  <= {2'b0, b_x} * 8'd5;
        end
        hsync  <= hs_d[1];
        vsync  <= vs_d[1];
        hblank <= hb_d[1];
        vblank <= vb_d[1];
        vid_h  <= h_d2;
        vid_v  <= v_d2;
    end
end

`ifdef JEDI_TRACE
always @(posedge clk) begin
    if (m_wr & m_sel_vctl)
        $display("TRACE vctl %04x=%02x line %0d h %0d", m_ab, m_do, v, h);
    if (v32_last != v[5])
        $display("TRACE 32V=%0d line %0d", v[5], v);
    if (main_irq_ack)
        $display("TRACE irqack line %0d h %0d", v, h);
end
`endif
`ifdef JEDI_TRACE_PC
// Main CPU instruction trace (opcode addresses) for frames PC_FROM..PC_TO,
// frame counted as in sim_main.cpp (VBLANK rising edges).
integer trace_frame = 0;
reg     trace_vb = 0;
reg [15:0] trace_prev_ab = 0;
always @(posedge clk) begin
    trace_vb <= t_vblank;
    if (t_vblank && !trace_vb) trace_frame <= trace_frame + 1;
    if (ce_main) begin
        trace_prev_ab <= m_ab;
        if (main_cpu.state == 6'd12 && trace_frame >= `PC_FROM && trace_frame < `PC_TO)
            $display("PC %04X", trace_prev_ab);
    end
end
`endif
`ifdef JEDI_RAMDUMP
// Dump main work RAM (0000-07FF) every 30 frames from frame RD_FROM, to ram_NNNN.hex
integer rd_frame = 0;
reg     rd_vb = 0;
always @(posedge clk) begin
    rd_vb <= t_vblank;
    if (t_vblank && !rd_vb) begin
        rd_frame <= rd_frame + 1;
        if (rd_frame >= `RD_FROM && rd_frame % 30 == 0)
            $writememh($sformatf("ram_%04d.hex", rd_frame), main_ram.mem);
    end
end
`endif
`ifdef JEDI_WATCH
// Print the last values the main CPU wrote to up to four RAM addresses, once per frame.
// Define JEDI_WATCH plus W0..W3 (16-bit addresses).
reg [7:0] watch_val [0:3];
reg       watch_vb = 0;
initial begin watch_val[0] = 0; watch_val[1] = 0; watch_val[2] = 0; watch_val[3] = 0; end
always @(posedge clk) begin
    watch_vb <= t_vblank;
    if (m_wr && m_ab == `W0) watch_val[0] <= m_do;
    if (m_wr && m_ab == `W1) watch_val[1] <= m_do;
    if (m_wr && m_ab == `W2) watch_val[2] <= m_do;
    if (m_wr && m_ab == `W3) watch_val[3] <= m_do;
    if (t_vblank && !watch_vb)
        $display("WATCH %02x %02x %02x %02x", watch_val[0], watch_val[1], watch_val[2], watch_val[3]);
end
`endif
`ifdef JEDI_TRACE_IO
// Main CPU I/O reads/writes and sound CPU POKEY reads (for divergence hunting)
always @(posedge clk) begin
    if (m_rd & (m_sel_sack | m_sel_adc | (m_sel_in & m_ab[0])))
        $display("IO m_rd %04x=%02x line %0d", m_ab, m_bus_q, v);
    if (m_wr & m_sel_ctl & (m_ab[9:7] == 3'b110))
        $display("IO snd_cmd %02x line %0d", m_do, v);
    if (s_wr & s_sel_io1 && s_ab[10:8] == 3'b100)
        $display("IO snd_ack %02x line %0d", s_do, v);
    if (s_rd & s_sel_pokey)
        $display("IO pokey_rd %04x line %0d", s_ab, v);
end
`endif

assign dbg_main_ab  = m_ab;
assign dbg_snd_ab   = s_ab;
assign dbg_outlatch = outlatch;

endmodule
