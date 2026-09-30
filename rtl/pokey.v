// Atari POKEY (C012294) — audio section, RANDOM, and benign stubs for the rest.
// Behaviour follows the Atari POKEY data sheet and MAME's pokey.cpp, including its
// poly4/poly5/poly9/poly17 generator definitions.
//
// Jedi has four of these (in one quad custom) clocked at 1.512 MHz; pots, keyboard,
// serial port and IRQs are unused by the game, so those registers read as idle values.
module pokey (
    input            clk,
    input            ce,          // POKEY clock enable ("1.79 MHz" input, 1.512 MHz here)
    input            reset,
    input      [3:0] addr,
    input      [7:0] din,
    input            we,          // write strobe, qualified with ce by the caller
    output     [7:0] dout,
    output     [5:0] audio        // sum of the four channels, 0..60
);

reg [7:0] audf [0:3];
reg [7:0] audc [0:3];
reg [7:0] audctl = 0;
reg [7:0] skctl = 0;

// ---------------------------------------------------------------------------
// Polynomial counters, stepped every POKEY clock (MAME poly_init_*)
// ---------------------------------------------------------------------------
reg  [3:0]  p4  = 0;
reg  [4:0]  p5  = 0;
reg  [8:0]  p9  = 9'h1ff;
reg  [16:0] p17 = 17'h1ffff;
wire        p17_in8 = p17[8] ^ p17[13];
wire [16:0] p17_sh  = {1'b0, p17[16:1]};
wire        in_reset = skctl[1:0] == 2'b00;   // SKCTL init mode holds the polys

always @(posedge clk) begin
    if (reset || in_reset) begin
        p4  <= 0;
        p5  <= 0;
        p9  <= 9'h1ff;
        p17 <= 17'h1ffff;
    end else if (ce) begin
        p4  <= {p4[2:0], ~(p4[2] ^ p4[3])};
        p5  <= {p5[3:0], ~(p5[2] ^ p5[4])};
        p9  <= {p9[0] ^ p9[5], p9[8:1]};
        p17 <= {p17[0], p17_sh[15:8], p17_in8, p17_sh[6:0]};
    end
end

wire poly4_bit  = p4[0];
wire poly5_bit  = p5[0];
wire polyN_bit  = audctl[7] ? p9[0] : p17[0];

// ---------------------------------------------------------------------------
// Base clocks: 64 kHz = /28, 15 kHz = /114
// ---------------------------------------------------------------------------
reg [6:0] div28 = 0, div114 = 0;
wire ce64 = ce && div28 == 0;
wire ce15 = ce && div114 == 0;
always @(posedge clk) if (ce) begin
    div28  <= div28  == 7'd27  ? 7'd0 : div28 + 7'd1;
    div114 <= div114 == 7'd113 ? 7'd0 : div114 + 7'd1;
end
wire ce_base = audctl[0] ? ce15 : ce64;

// ---------------------------------------------------------------------------
// Channel dividers. Period (in source clocks) = AUDF+1; +4 when a single channel is
// clocked at 1.79 MHz; +7 for a joined 16-bit pair clocked at 1.79 MHz.
// ---------------------------------------------------------------------------
reg [7:0]  cnt [0:3];
reg [3:0]  borrow;
wire join12 = audctl[4];
wire join34 = audctl[3];
wire fast1  = audctl[6];
wire fast3  = audctl[5];

wire clk1 = fast1 ? ce : ce_base;
wire clk3 = fast3 ? ce : ce_base;
wire clk2 = join12 ? clk1 : ce_base;
wire clk4 = join34 ? clk3 : ce_base;

wire stimer = we && addr == 4'h9;

// 16-bit pair helpers
wire [15:0] cnt12 = {cnt[1], cnt[0]};
wire [15:0] cnt34 = {cnt[3], cnt[2]};
wire [15:0] load12 = {audf[1], audf[0]} + (fast1 ? 16'd6 : 16'd0);
wire [15:0] load34 = {audf[3], audf[2]} + (fast3 ? 16'd6 : 16'd0);

integer i;
always @(posedge clk) begin
    borrow <= 0;
    if (reset || stimer) begin
        for (i = 0; i < 4; i = i + 1) cnt[i] <= audf[i];
    end else begin
        // channels 1/2
        if (join12) begin
            if (clk1) begin
                if (cnt12 == 0) begin
                    {cnt[1], cnt[0]} <= load12;
                    borrow[1] <= 1;
                end else
                    {cnt[1], cnt[0]} <= cnt12 - 16'd1;
            end
        end else begin
            if (clk1) begin
                if (cnt[0] == 0) begin cnt[0] <= audf[0] + (fast1 ? 8'd3 : 8'd0); borrow[0] <= 1; end
                else cnt[0] <= cnt[0] - 8'd1;
            end
            if (clk2) begin
                if (cnt[1] == 0) begin cnt[1] <= audf[1]; borrow[1] <= 1; end
                else cnt[1] <= cnt[1] - 8'd1;
            end
        end
        // channels 3/4
        if (join34) begin
            if (clk3) begin
                if (cnt34 == 0) begin
                    {cnt[3], cnt[2]} <= load34;
                    borrow[3] <= 1;
                end else
                    {cnt[3], cnt[2]} <= cnt34 - 16'd1;
            end
        end else begin
            if (clk3) begin
                if (cnt[2] == 0) begin cnt[2] <= audf[2] + (fast3 ? 8'd3 : 8'd0); borrow[2] <= 1; end
                else cnt[2] <= cnt[2] - 8'd1;
            end
            if (clk4) begin
                if (cnt[3] == 0) begin cnt[3] <= audf[3]; borrow[3] <= 1; end
                else cnt[3] <= cnt[3] - 8'd1;
            end
        end
    end
end

// ---------------------------------------------------------------------------
// Channel output flip-flops, distortion and high-pass filters
// AUDC: b7 = no poly5 gate, b6 = poly4 (else poly17/9), b5 = pure tone,
//       b4 = volume only, b3..0 = volume
// ---------------------------------------------------------------------------
reg [3:0] out = 0;
reg       hp1 = 0, hp2 = 0;

always @(posedge clk) begin
    if (reset || stimer) begin
        out <= 0;
        hp1 <= 0;
        hp2 <= 0;
    end else begin
        for (i = 0; i < 4; i = i + 1)
            if (borrow[i] && (audc[i][7] || poly5_bit))
                out[i] <= audc[i][5] ? ~out[i] : (audc[i][6] ? poly4_bit : polyN_bit);
        // High-pass: ch1 sampled by ch3, ch2 sampled by ch4
        if (borrow[2]) hp1 <= out[0];
        if (borrow[3]) hp2 <= out[1];
    end
end

wire [3:0] level;
assign level[0] = audctl[2] ? out[0] ^ hp1 : out[0];
assign level[1] = audctl[1] ? out[1] ^ hp2 : out[1];
assign level[2] = out[2];
assign level[3] = out[3];

function [3:0] chan_vol(input [7:0] c, input l);
    chan_vol = (c[4] | l) ? c[3:0] : 4'd0;
endfunction

assign audio = chan_vol(audc[0], level[0]) + chan_vol(audc[1], level[1]) +
               chan_vol(audc[2], level[2]) + chan_vol(audc[3], level[3]);

// ---------------------------------------------------------------------------
// Register interface
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        for (i = 0; i < 4; i = i + 1) begin audf[i] <= 0; audc[i] <= 0; end
        audctl <= 0;
        skctl  <= 0;
    end else if (we) begin
        case (addr)
            4'h0: audf[0] <= din;  4'h1: audc[0] <= din;
            4'h2: audf[1] <= din;  4'h3: audc[1] <= din;
            4'h4: audf[2] <= din;  4'h5: audc[2] <= din;
            4'h6: audf[3] <= din;  4'h7: audc[3] <= din;
            4'h8: audctl <= din;
            4'hF: skctl  <= din;
            default: ;             // STIMER handled above; others unused
        endcase
    end
end

// RANDOM = inverted poly bits (MAME); IRQST/SKSTAT idle; pots/keyboard/serial = 0
wire [7:0] random = audctl[7] ? ~p9[7:0] : ~p17[15:8];
assign dout = addr == 4'hA ? random :
              addr == 4'hE ? 8'hFF :
              addr == 4'hF ? 8'hFF : 8'h00;

endmodule
