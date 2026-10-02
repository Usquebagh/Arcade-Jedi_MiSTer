// Optional on-screen yoke readout: "X+000 Y+000" centred near the bottom of the screen,
// showing how far the ADC values the game reads are from centre (0x80). Text is drawn in
// a 5x7 font (6 px pitch) over a darkened strip; everything else passes straight through.
module yoke_overlay #(
    parameter X0 = 115,          // left edge of the strip (296 px wide screen)
    parameter Y0 = 229           // top edge of the strip (240 lines)
) (
    input            clk,
    input            enable,
    input      [8:0] h,          // position of the pixel on rgb_in
    input      [8:0] v,
    input      [7:0] adc_x,
    input      [7:0] adc_y,
    input     [23:0] rgb_in,
    output    [23:0] rgb_out
);

localparam CHARS = 11, W = CHARS * 6 + 2, HGT = 9;

// Signed deflection -> sign + three decimal digits
function [15:0] fmt(input [7:0] adc);   // {sign_char, hundreds, tens, ones} as 4-bit codes
    reg [7:0] mag;
    reg [6:0] rem, tens, ones;
    begin
        mag  = adc >= 8'h80 ? adc - 8'h80 : 8'h80 - adc;
        rem  = mag >= 8'd100 ? mag - 8'd100 : mag[6:0];
        tens = rem / 7'd10;
        ones = rem % 7'd10;
        fmt  = {adc >= 8'h80 ? 4'd11 : 4'd12,          // '+' or '-'
                mag >= 8'd100 ? 4'd1 : 4'd0, tens[3:0], ones[3:0]};
    end
endfunction

// Character codes: 0-9 digits, 10 'X', 11 '+', 12 '-', 13 ' ', 14 'Y'
function [4:0] glyph_row(input [3:0] c, input [2:0] r);   // 5 pixels, MSB = left
    case (c)
        4'd0:  case (r) 0: glyph_row = 5'b01110; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b10011;
                        3: glyph_row = 5'b10101; 4: glyph_row = 5'b11001; 5: glyph_row = 5'b10001;
                        default: glyph_row = 5'b01110; endcase
        4'd1:  case (r) 0: glyph_row = 5'b00100; 1: glyph_row = 5'b01100; 6: glyph_row = 5'b01110;
                        default: glyph_row = 5'b00100; endcase
        4'd2:  case (r) 0: glyph_row = 5'b01110; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b00001;
                        3: glyph_row = 5'b00010; 4: glyph_row = 5'b00100; 5: glyph_row = 5'b01000;
                        default: glyph_row = 5'b11111; endcase
        4'd3:  case (r) 0: glyph_row = 5'b11110; 1: glyph_row = 5'b00001; 2: glyph_row = 5'b00001;
                        3: glyph_row = 5'b01110; 4: glyph_row = 5'b00001; 5: glyph_row = 5'b00001;
                        default: glyph_row = 5'b11110; endcase
        4'd4:  case (r) 0: glyph_row = 5'b00010; 1: glyph_row = 5'b00110; 2: glyph_row = 5'b01010;
                        3: glyph_row = 5'b10010; 4: glyph_row = 5'b11111; default: glyph_row = 5'b00010; endcase
        4'd5:  case (r) 0: glyph_row = 5'b11111; 1: glyph_row = 5'b10000; 2: glyph_row = 5'b11110;
                        3: glyph_row = 5'b00001; 4: glyph_row = 5'b00001; 5: glyph_row = 5'b10001;
                        default: glyph_row = 5'b01110; endcase
        4'd6:  case (r) 0: glyph_row = 5'b00110; 1: glyph_row = 5'b01000; 2: glyph_row = 5'b10000;
                        3: glyph_row = 5'b11110; 4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                        default: glyph_row = 5'b01110; endcase
        4'd7:  case (r) 0: glyph_row = 5'b11111; 1: glyph_row = 5'b00001; 2: glyph_row = 5'b00010;
                        3: glyph_row = 5'b00100; default: glyph_row = 5'b01000; endcase
        4'd8:  case (r) 0: glyph_row = 5'b01110; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b10001;
                        3: glyph_row = 5'b01110; 4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                        default: glyph_row = 5'b01110; endcase
        4'd9:  case (r) 0: glyph_row = 5'b01110; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b10001;
                        3: glyph_row = 5'b01111; 4: glyph_row = 5'b00001; 5: glyph_row = 5'b00010;
                        default: glyph_row = 5'b01100; endcase
        4'd10: case (r) 0, 6: glyph_row = 5'b10001; 1, 5: glyph_row = 5'b10001; 2, 4: glyph_row = 5'b01010;
                        default: glyph_row = 5'b00100; endcase
        4'd11: case (r) 1, 2, 4, 5: glyph_row = 5'b00100; 3: glyph_row = 5'b11111;
                        default: glyph_row = 5'b00000; endcase
        4'd12: glyph_row = r == 3 ? 5'b11111 : 5'b00000;
        4'd14: case (r) 0, 1: glyph_row = 5'b10001; 2: glyph_row = 5'b01010; default: glyph_row = 5'b00100; endcase
        default: glyph_row = 5'b00000;
    endcase
endfunction

// Digits are registered (they only change when the stick moves) to keep the
// yoke -> ADC scaling -> divide-by-10 chain out of the pixel path.
reg [15:0] fx = 0, fy = 0;
always @(posedge clk) begin
    fx <= fmt(adc_x);
    fy <= fmt(adc_y);
end
// "X+000 Y+000"
wire [3:0] text [0:CHARS-1];
assign text[0] = 4'd10;      assign text[1] = fx[15:12]; assign text[2] = fx[11:8];
assign text[3] = fx[7:4];    assign text[4] = fx[3:0];   assign text[5] = 4'd13;
assign text[6] = 4'd14;      assign text[7] = fy[15:12]; assign text[8] = fy[11:8];
assign text[9] = fy[7:4];    assign text[10] = fy[3:0];

wire       in_box = enable && h >= X0 && h < X0 + W && v >= Y0 && v < Y0 + HGT;
wire [8:0] bx = h - X0 - 9'd1;           // 1 px margin
wire [8:0] by = v - Y0 - 9'd1;
wire [4:0] col_char = bx / 6;
wire [2:0] col_px   = bx % 6;
wire       in_text  = in_box && h > X0 && bx < CHARS * 6 && v > Y0 && by < 7 && col_px < 5;
wire [4:0] row_bits = glyph_row(text[col_char[3:0]], by[2:0]);
wire       lit      = in_text && row_bits[3'd4 - col_px];

assign rgb_out = !in_box ? rgb_in :
                 lit     ? 24'hFFFFFF :
                           {1'b0, rgb_in[23:17], 1'b0, rgb_in[15:9], 1'b0, rgb_in[7:1]};   // darken

endmodule
