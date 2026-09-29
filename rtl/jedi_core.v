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
    parameter MAIN_ROM_INIT = "",
    parameter SND_ROM_INIT  = "",
    parameter TX_ROM_INIT   = ""
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
wire ce_main    = macc_next >= 17'd48384;

always @(posedge clk) begin
    pdiv <= pdiv + 3'd1;
    sdiv <= sdiv + 5'd1;
    macc <= ce_main ? macc_next[15:0] - 16'd48384 : macc_next[15:0];
end

assign ce_pix = pdiv == 3'd0;   // one clock after outputs update

// ---------------------------------------------------------------------------
// Video timing and IRQ generation (32V)
// ---------------------------------------------------------------------------
wire [8:0] h, v;
wire t_hblank, t_vblank, t_hsync, t_vsync;

jedi_timing timing (
    .clk(clk), .reset(reset), .ce_pix(ce_pix_int),
    .h(h), .v(v),
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

// NOVRAM (2 x X2212, 256 x 4 each). Store/recall not modelled yet; power-on contents
// match MAME's defaults (0x0F fill, 0x50-0x5F zero) so the checksum is invalid.
reg [7:0] novram [0:255];
reg [7:0] m_nov_q;
integer i;
initial for (i = 0; i < 256; i = i + 1) novram[i] = (i >= 8'h50 && i < 8'h60) ? 8'h00 : 8'h0f;
always @(posedge clk) begin
    if (m_wr & m_sel_nov) novram[m_ab[7:0]] <= m_do;
    m_nov_q <= novram[m_ab[7:0]];
end

// Playfield RAM 2000-27FF (video port unused until milestone 2)
wire [7:0] m_pf_q;
dpram #(.AW(11)) pf_ram (
    .clk(clk),
    .a_addr(m_ab[10:0]), .a_din(m_do), .a_we(m_wr & m_sel_pf), .a_dout(m_pf_q),
    .b_addr(11'd0), .b_din(8'd0), .b_we(1'b0), .b_dout()
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

// Program ROM: 5 x 16 KB = 221 (8000), 222 (C000), 123/124/122 (banks 0-2 at 4000)
reg  [1:0] rom_bank = 0;
wire [2:0] rom_page = m_ab[15:14] == 2'b10 ? 3'd0 :
                      m_ab[15:14] == 2'b11 ? 3'd1 : 3'd2 + {1'b0, rom_bank};
wire [7:0] m_rom_q;
dpram #(.AW(17), .DEPTH(5 * 16384), .INIT(MAIN_ROM_INIT)) main_rom (
    .clk(clk),
    .a_addr({rom_page, m_ab[13:0]}), .a_din(8'd0), .a_we(1'b0), .a_dout(m_rom_q),
    .b_addr(17'd0), .b_din(8'd0), .b_we(1'b0), .b_dout()
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

always @(posedge clk) if (ce_main) m_di <= m_bus_q;

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
    .b_addr(15'd0), .b_din(8'd0), .b_we(1'b0), .b_dout()
);

wire speech_ready_n = 1'b0;   // TMS5220 stub: always ready

wire [7:0] s_bus_q =
    s_sel_ram   ? s_ram_q :
    s_sel_pokey ? 8'h00 :                                       // POKEY stub
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
// Video: alphanumerics layer -> colour RAM -> RGB
// Eight master clocks per pixel; fetches are sequenced within the pixel slot and the
// result is output on the next slot (all outputs delayed by exactly one pixel).
// ---------------------------------------------------------------------------
reg  [12:0] tx_rom_addr = 0;
wire  [7:0] tx_gfx;
dpram #(.AW(13), .INIT(TX_ROM_INIT)) tx_rom (
    .clk(clk),
    .a_addr(tx_rom_addr), .a_din(8'd0), .a_we(1'b0), .a_dout(tx_gfx),
    .b_addr(13'd0), .b_din(8'd0), .b_we(1'b0), .b_dout()
);

// 4 pixels per byte, leftmost in the MSBs
wire [1:0] tx_pix = h[1:0] == 2'd0 ? tx_gfx[7:6] :
                    h[1:0] == 2'd1 ? tx_gfx[5:4] :
                    h[1:0] == 2'd2 ? tx_gfx[3:2] : tx_gfx[1:0];

always @(posedge clk) begin
    case (pdiv)
        3'd0: tx_ram_addr <= {1'b0, v[7:3], h[8:3]};                 // 64 x 30 tiles
        3'd2: tx_rom_addr <= {alpha_bank, tx_code, v[2:0], h[2]};    // 16 bytes/tile
        3'd4: col_addr    <= {tx_pix, 4'd0 /* MO */, 4'd0 /* PF */};
        default: ;
    endcase
end

// IRGB 3-3-3-3: gun = 5 * value * intensity (0..245)
wire [2:0] c_i = col_hi[3:1];
wire [2:0] c_r = {col_hi[0], col_lo[7:6]};
wire [2:0] c_g = col_lo[5:3];
wire [2:0] c_b = col_lo[2:0];
wire [5:0] r_x = c_r * c_i, g_x = c_g * c_i, b_x = c_b * c_i;

always @(posedge clk) begin
    if (ce_pix_int) begin
        if (video_off | t_hblank | t_vblank) begin
            red <= 0; green <= 0; blue <= 0;
        end else begin
            red   <= {2'b0, r_x} * 8'd5;
            green <= {2'b0, g_x} * 8'd5;
            blue  <= {2'b0, b_x} * 8'd5;
        end
        hsync  <= t_hsync;
        vsync  <= t_vsync;
        hblank <= t_hblank;
        vblank <= t_vblank;
        vid_h  <= h;
        vid_v  <= v;
    end
end

assign dbg_main_ab  = m_ab;
assign dbg_snd_ab   = s_ab;
assign dbg_outlatch = outlatch;

endmodule
