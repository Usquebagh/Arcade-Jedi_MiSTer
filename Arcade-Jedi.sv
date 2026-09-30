//============================================================================
//  Arcade: Return of the Jedi (Atari, 1984)
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"Jedi;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"P1,Yoke Controls;",
	"P1-;",
	"P1O[10:8],Input,Analog Stick,Mouse,Digital Centering,Digital Relative,Auto;",
	"P1O[13:11],Analog Sensitivity,1.0x,0.75x,0.5x,0.25x,0.125x,1.25x,1.5x,2.0x;",
	"P1O[20:18],Digital Speed,1.0x,0.75x,0.5x,0.25x,0.125x,1.25x,1.5x,2.0x;",
	"P1O[14],Y-Axis,Normal,Inverted;",
	"-;",
	"C,Cheats;",
	"-;",
	"O[6],Service Mode,Off,On;",
	"O[17],Autosave NVRAM,Off,On;",
	"T[16],Save NVRAM;",
	"-;",
	"R[0],Reset;",
	"J1,Trigger,Left Thumb,Right Thumb,Coin L,Coin R,Aux Coin;",
	"jn,A,B,X,Select,R,Start;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;   // 48.384 MHz = 4 x 12.096 MHz
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys)
);

///////////////////////////////////////////////////

wire [127:0] status;
wire   [1:0] buttons;
wire         forced_scandoubler;
wire         direct_video;
wire  [21:0] gamma_bus;

wire         ioctl_download;
wire         ioctl_upload;
wire         ioctl_upload_req;
wire         ioctl_wr;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire   [7:0] ioctl_din;
wire  [15:0] ioctl_index;

wire  [31:0] joy0, joy1;
wire  [31:0] joy = joy0 | joy1;
wire  [15:0] joy_analog0;
wire  [24:0] ps2_mouse;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),

	.buttons(buttons),
	.status(status),
	.status_menumask({direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_upload_index(8'd4),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),
	.ioctl_wait(1'b0),

	.joystick_0(joy0),
	.joystick_1(joy1),
	.joystick_l_analog_0(joy_analog0),
	.ps2_mouse(ps2_mouse)
);

wire rom_download   = ioctl_download && ioctl_index == 0;
wire nvram_download = ioctl_download && ioctl_index == 4;
wire code_download  = ioctl_download && ioctl_index == 255;

// Cheat codes from the MRA <cheats> section: 16 bytes per code, shifted in MSB first;
// bit 128 strobes each complete code into the engine (as in the Irem M92 core).
reg [128:0] cheat_code = 0;
always @(posedge clk_sys) begin
	cheat_code[128] <= 1'b0;
	if (code_download & ioctl_wr) begin
		cheat_code[127:0] <= {cheat_code[119:0], ioctl_dout};
		cheat_code[128]   <= &ioctl_addr[3:0];
	end
end
wire cheat_reset = code_download && ioctl_wr && ioctl_addr == 0;
wire reset = RESET | status[0] | buttons[1] | rom_download | nvram_download;

////////////////////   INPUTS   ///////////////////

wire m_trigger = joy[4];
wire m_lthumb  = joy[5];
wire m_rthumb  = joy[6];
wire m_coin_l  = joy[7];
wire m_coin_r  = joy[8];
wire m_auxcoin = joy[9];   // also advances the self-test screens

// 0C00: b7 coin R, b6 coin L, b5 aux coin, b4 /self-test, b3 spare (reads 0 in MAME),
//       b2 /L thumb, b1 /trigger, b0 /R thumb - all active low
wire [7:0] in0 = {~m_coin_r, ~m_coin_l, ~m_auxcoin, ~status[6], 1'b0, ~m_lthumb, ~m_trigger, ~m_rthumb};

// Flight yoke: analog stick / mouse / digital, via Videodr0me's Star Wars adapter.
// TICK_BITS 18 keeps its digital step rate as designed (it was written for 12 MHz).
wire [7:0] yoke_x, yoke_y;
starwars_yoke_input #(.TICK_BITS(18)) yoke_input
(
	.clk_sys(clk_sys),
	.reset(reset),
	.analog(joy_analog0),
	.mouse(ps2_mouse),
	.left(joy[1]),
	.right(joy[0]),
	.up(joy[3]),
	.down(joy[2]),
	.input_mode(status[10:8]),
	.sensitivity(status[13:11]),
	.digital_sensitivity(status[20:18]),
	.invert_y(status[14]),
	.yoke_x(yoke_x),
	.yoke_y(yoke_y)
);

// Signed yoke axes -> ADC0809 values. Scaled by 7/8 to 0x10..0xEF so they stay inside
// the game's steering window (calibrated centre +/- 0x70) and its min/max calibration
// (pre-loaded as 0x11/0xEF in jedi_core's NOVRAM) can never be pulled off-centre.
function [7:0] yoke_to_adc(input [7:0] axis);
	reg signed [10:0] scaled;
	begin
		scaled = ($signed({{3{axis[7]}}, axis}) * 11'sd7) >>> 3;
		yoke_to_adc = 8'h80 + scaled[7:0];
	end
endfunction

wire [7:0] adc_x = yoke_to_adc(yoke_x);
wire [7:0] adc_y = yoke_to_adc(yoke_y);

////////////////////   CORE   ///////////////////

wire [7:0] r, g, b;
wire       hs, vs, hbl, vbl, ce_pix;
wire signed [15:0] audio;

wire [7:0] nv_dout;
wire       nv_changed;

jedi_core core
(
	.clk(clk_sys),
	.reset(reset),

	.in0(in0),
	.tilt(1'b0),
	.adc_x(adc_x),
	.adc_y(adc_y),

	.red(r),
	.green(g),
	.blue(b),
	.hsync(hs),
	.vsync(vs),
	.hblank(hbl),
	.vblank(vbl),
	.ce_pix(ce_pix),
	.vid_h(),
	.vid_v(),

	.audio(audio),

	.dn_addr(ioctl_addr[18:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr & rom_download),

	.nv_addr(ioctl_addr[7:0]),
	.nv_din(ioctl_dout),
	.nv_we(ioctl_wr & nvram_download),
	.nv_dout(nv_dout),
	.nv_changed(nv_changed),

	.cheat_code(cheat_code),
	.cheat_reset(cheat_reset),

	.dbg_main_ab(),
	.dbg_snd_ab(),
	.dbg_outlatch()
);

////////////////////   NVRAM save   ///////////////////
// MRA declares <nvram index="4" size="256">; the HPS loads it as a download with
// ioctl_index 4 and saves it by uploading when ioctl_upload_req is raised.

reg nvram_dirty = 0;
always @(posedge clk_sys) begin
	if (ioctl_upload && ioctl_index == 4) nvram_dirty <= 0;
	else if (nv_changed)                  nvram_dirty <= 1;
end

assign ioctl_upload_req = status[16] | (status[17] & nvram_dirty);
assign ioctl_din = nv_dout;

////////////////////   VIDEO / AUDIO   ///////////////////

arcade_video #(296, 24) arcade_video
(
	.clk_video(clk_sys),
	.ce_pix(ce_pix),

	.RGB_in({r, g, b}),
	.HBlank(hbl),
	.VBlank(vbl),
	.HSync(hs),
	.VSync(vs),

	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_DE(VGA_DE),
	.VGA_SL(VGA_SL),

	.fx(status[5:3]),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus)
);

assign AUDIO_L   = audio;
assign AUDIO_R   = audio;
assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;

assign LED_USER = ioctl_download;

endmodule
