// Cheat engine for an 8-bit data bus (main CPU reads).
//
// Adapted from the Irem M92 core's cheatengine_32_16 (Martin Donlon, GPL-2.0+), which is
// based on Kitrinx's MiSTer cheat code handling. Same 16-byte code format as MiSTer MRA
// <cheat> entries, e.g. "000000 10 00000123 00000000 00000003":
//
//   [127:96] flags: bit 96 = compare enable, [102:100] = width (1 = byte),
//                   [105:104] = method (0 replace, 1 OR, 2 AND)
//   [95:64]  address (low 16 bits used)
//   [63:32]  compare value (low byte used)
//   [31:0]   replacement value (low byte used)
//
// When the CPU reads a matching address (and the compare matches, if enabled), the value
// it sees is replaced. Only byte-wide codes are meaningful on this bus.
module jedi_cheats #(
    parameter MAX_CODES = 16
) (
    input            clk,
    input            reset,      // on the first byte of a new code download
    input    [128:0] code,       // bit 128 = strobe (rising edge loads one code)
    input     [15:0] addr,
    input      [7:0] din,
    output reg [7:0] dout
);

reg        valid  [0:MAX_CODES-1];
reg [15:0] c_addr [0:MAX_CODES-1];
reg  [7:0] c_cmp  [0:MAX_CODES-1];
reg        c_cmpe [0:MAX_CODES-1];
reg  [7:0] c_val  [0:MAX_CODES-1];
reg  [1:0] c_meth [0:MAX_CODES-1];

reg  [4:0] next_index = 0;
reg        strobe_last = 0;
integer    k;
initial for (k = 0; k < MAX_CODES; k = k + 1) valid[k] = 0;

always @(posedge clk) begin
    strobe_last <= code[128];
    if (reset) begin
        next_index <= 0;
        for (k = 0; k < MAX_CODES; k = k + 1) valid[k] <= 0;
    end else if (code[128] && !strobe_last && next_index < MAX_CODES) begin
        valid [next_index] <= code[102:100] == 3'd1;   // byte codes only
        c_addr[next_index] <= code[79:64];
        c_cmp [next_index] <= code[39:32];
        c_cmpe[next_index] <= code[96];
        c_val [next_index] <= code[7:0];
        c_meth[next_index] <= code[105:104];
        next_index <= next_index + 5'd1;
    end
end

integer x;
always @* begin
    dout = din;
    for (x = 0; x < MAX_CODES; x = x + 1)
        if (valid[x] && c_addr[x] == addr && (!c_cmpe[x] || c_cmp[x] == din))
            case (c_meth[x])
                2'd1:    dout = c_val[x] | din;
                2'd2:    dout = c_val[x] & din;
                default: dout = c_val[x];
            endcase
end

endmodule
