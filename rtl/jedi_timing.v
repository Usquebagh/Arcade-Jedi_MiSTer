// Video timing (SP-227 sheet 4A).
// H: 6.048 MHz pixel clock, 384 pixels/line (11J/11L clear at 383) -> 15.75 kHz.
// V: 262 lines assumed (the 9H sync PROM is undumped) -> 60.1 Hz, 240 visible.
// Visible area 296 x 240 as in MAME. Sync positions are estimates (see docs/hardware.md).
module jedi_timing #(
    parameter H_TOTAL   = 384,
    parameter H_VISIBLE = 296,
    parameter HS_START  = 320,
    parameter HS_END    = 352,
    parameter V_TOTAL   = 262,
    parameter V_VISIBLE = 240,
    parameter VS_START  = 244,
    parameter VS_END    = 247
) (
    input            clk,
    input            reset,
    input            ce_pix,
    output reg [8:0] h,
    output reg [8:0] v,
    output           hblank,
    output           vblank,
    output           hsync,
    output           vsync
);

always @(posedge clk) begin
    if (reset) begin
        h <= 0;
        v <= 0;
    end else if (ce_pix) begin
        if (h == H_TOTAL - 1) begin
            h <= 0;
            v <= (v == V_TOTAL - 1) ? 9'd0 : v + 9'd1;
        end else
            h <= h + 9'd1;
    end
end

assign hblank = h >= H_VISIBLE;
assign vblank = v >= V_VISIBLE;
assign hsync  = h >= HS_START && h < HS_END;
assign vsync  = v >= VS_START && v < VS_END;

endmodule
