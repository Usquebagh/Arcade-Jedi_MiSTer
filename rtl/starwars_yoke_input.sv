//============================================================================
//  Star Wars flight-yoke input adapter
//
//  Written 2026 by Videodr0me
//============================================================================

`default_nettype none

module starwars_yoke_input
(
	input  wire        clk_sys,
	input  wire        reset,
	input  wire [15:0] analog,
	input  wire [24:0] mouse,
	input  wire        left,
	input  wire        right,
	input  wire        up,
	input  wire        down,
	input  wire  [2:0] input_mode,
	input  wire  [2:0] sensitivity,
	input  wire        invert_y,
	output logic [7:0] yoke_x,
	output logic [7:0] yoke_y
);

	localparam logic [2:0] INPUT_ANALOG = 3'd0;
	localparam logic [2:0] INPUT_MOUSE = 3'd1;
	localparam logic [2:0] INPUT_DIGITAL_CENTER = 3'd2;
	localparam logic [2:0] INPUT_DIGITAL_RELATIVE = 3'd3;
	localparam logic [2:0] INPUT_AUTO = 3'd4;

	localparam logic [1:0] AUTO_ANALOG = 2'd0;
	localparam logic [1:0] AUTO_MOUSE = 2'd1;
	localparam logic [1:0] AUTO_DIGITAL = 2'd2;

	localparam logic signed [11:0] AXIS_Q3_MIN = -12'sd1024;
	localparam logic signed [11:0] AXIS_Q3_MAX = 12'sd1016;

	function automatic logic [4:0] gain_eighths(input logic [2:0] gain);
		begin
			case (gain)
				3'd1: gain_eighths = 5'd6;  // 0.75x
				3'd2: gain_eighths = 5'd4;  // 0.5x
				3'd3: gain_eighths = 5'd2;  // 0.25x
				3'd4: gain_eighths = 5'd1;  // 0.125x
				3'd5: gain_eighths = 5'd10; // 1.25x
				3'd6: gain_eighths = 5'd12; // 1.5x
				3'd7: gain_eighths = 5'd16; // 2.0x
				default: gain_eighths = 5'd8;
			endcase
		end
	endfunction

	function automatic logic signed [8:0] scale_analog_axis(
		input logic signed [8:0] axis,
		input logic        [2:0] gain
	);
		logic [8:0] magnitude;
		logic [13:0] product;
		logic [10:0] scaled;
		begin
			if (gain == 3'd0) begin
				scale_analog_axis = axis;
			end else begin
				magnitude = axis[8] ? $unsigned(-axis) : $unsigned(axis);
				product = magnitude * gain_eighths(gain);
			scaled = product[13:3];
				if (axis[8])
					scale_analog_axis = (scaled >= 11'd128) ?
						-9'sd128 : -$signed({1'b0, scaled[7:0]});
				else
					scale_analog_axis = (scaled >= 11'd127) ?
						9'sd127 : $signed({1'b0, scaled[7:0]});
			end
		end
	endfunction

	function automatic logic signed [11:0] axis_to_q3(
		input logic signed [8:0] axis
	);
		begin
			axis_to_q3 = $signed(axis) <<< 3;
		end
	endfunction

	function automatic logic signed [8:0] q3_to_axis(
		input logic signed [11:0] value
	);
		logic [11:0] magnitude;
		logic  [8:0] whole;
		begin
			magnitude = value[11] ? $unsigned(-value) : $unsigned(value);
			whole = magnitude[11:3];
			q3_to_axis = value[11] ?
				-$signed(whole) : $signed(whole);
		end
	endfunction

	function automatic logic signed [14:0] scale_delta_q3(
		input logic signed [9:0] delta,
		input logic        [2:0] gain
	);
		begin
			scale_delta_q3 = delta * $signed({1'b0, gain_eighths(gain)});
		end
	endfunction

	function automatic logic signed [11:0] add_clamped_q3(
		input logic signed [11:0] position,
		input logic signed [14:0] delta
	);
		logic signed [15:0] sum;
		begin
			sum = $signed({{4{position[11]}}, position}) +
			      $signed({delta[14], delta});
			if (sum < -16'sd1024)
				add_clamped_q3 = AXIS_Q3_MIN;
			else if (sum > 16'sd1016)
				add_clamped_q3 = AXIS_Q3_MAX;
			else
				add_clamped_q3 = sum[11:0];
		end
	endfunction

	function automatic logic signed [11:0] step_toward_q3(
		input logic signed [11:0] position,
		input logic signed [11:0] target,
		input logic         [5:0] step
	);
		logic signed [12:0] difference;
		logic signed [12:0] step_ext;
		begin
			difference = $signed(target) - $signed(position);
			step_ext = $signed({7'd0, step});
			if (difference > step_ext)
				step_toward_q3 = position + $signed({6'd0, step});
			else if (difference < -step_ext)
				step_toward_q3 = position - $signed({6'd0, step});
			else
				step_toward_q3 = target;
		end
	endfunction

	function automatic logic analog_axis_moved(
		input logic signed [8:0] current,
		input logic signed [8:0] reference
	);
		logic signed [9:0] difference;
		begin
			difference = $signed(current) - $signed(reference);
			analog_axis_moved = (difference >= 10'sd4) ||
			                    (difference <= -10'sd4);
		end
	endfunction

	wire [7:0] analog_y_bits = invert_y ? ~analog[15:8] : analog[15:8];
	wire signed [8:0] analog_x_raw = $signed({analog[7], analog[7:0]});
	wire signed [8:0] analog_y_raw =
		$signed({analog_y_bits[7], analog_y_bits});
	wire signed [8:0] analog_x_scaled =
		scale_analog_axis(analog_x_raw, sensitivity);
	wire signed [8:0] analog_y_scaled =
		scale_analog_axis(analog_y_raw, sensitivity);

	wire signed [8:0] mouse_dx_raw = $signed({mouse[4], mouse[15:8]});
	wire signed [8:0] mouse_dy_raw = $signed({mouse[5], mouse[23:16]});
	wire signed [9:0] mouse_dx =
		$signed({mouse_dx_raw[8], mouse_dx_raw});
	wire signed [9:0] mouse_dy = invert_y ?
		-$signed({mouse_dy_raw[8], mouse_dy_raw}) :
		 $signed({mouse_dy_raw[8], mouse_dy_raw});
	wire signed [14:0] mouse_dx_q3 =
		scale_delta_q3(mouse_dx, sensitivity);
	wire signed [14:0] mouse_dy_q3 =
		scale_delta_q3(mouse_dy, sensitivity);

	wire digital_up = invert_y ? down : up;
	wire digital_down = invert_y ? up : down;
	wire digital_x_active = left ^ right;
	wire digital_y_active = digital_up ^ digital_down;
	wire [3:0] directions = {down, up, right, left};
	wire any_direction = |directions;
	wire signed [11:0] digital_target_x = digital_x_active ?
		(right ? AXIS_Q3_MAX : AXIS_Q3_MIN) : 12'sd0;
	wire signed [11:0] digital_target_y = digital_y_active ?
		(digital_down ? AXIS_Q3_MAX : AXIS_Q3_MIN) : 12'sd0;
	wire [5:0] digital_step_q3 = {gain_eighths(sensitivity), 1'b0};

	logic [2:0] mode_q;
	logic [1:0] auto_source;
	logic mouse_toggle_q;
	logic [3:0] directions_q;
	logic signed [8:0] analog_reference_x;
	logic signed [8:0] analog_reference_y;
	logic signed [11:0] mouse_x_q3;
	logic signed [11:0] mouse_y_q3;
	logic signed [11:0] digital_x_q3;
	logic signed [11:0] digital_y_q3;
	logic [15:0] digital_tick_div;

	wire [2:0] requested_mode = (input_mode <= INPUT_AUTO) ?
		input_mode : INPUT_ANALOG;
	wire mode_change = requested_mode != mode_q;
	wire mouse_event = mouse[24] != mouse_toggle_q;
	wire mouse_motion = mouse_event &&
		((mouse_dx_raw != 9'sd0) || (mouse_dy_raw != 9'sd0));
	wire digital_event = any_direction && (directions != directions_q);
	wire analog_motion =
		analog_axis_moved(analog_x_raw, analog_reference_x) ||
		analog_axis_moved(analog_y_raw, analog_reference_y);
	wire digital_tick = digital_tick_div == 16'd0;

	logic signed [8:0] selected_x;
	logic signed [8:0] selected_y;

	always_comb begin
		selected_x = analog_x_scaled;
		selected_y = analog_y_scaled;
		case (mode_q)
			INPUT_MOUSE: begin
				selected_x = q3_to_axis(mouse_x_q3);
				selected_y = q3_to_axis(mouse_y_q3);
			end
			INPUT_DIGITAL_CENTER,
			INPUT_DIGITAL_RELATIVE: begin
				selected_x = q3_to_axis(digital_x_q3);
				selected_y = q3_to_axis(digital_y_q3);
			end
			INPUT_AUTO: begin
				if (auto_source == AUTO_MOUSE) begin
					selected_x = q3_to_axis(mouse_x_q3);
					selected_y = q3_to_axis(mouse_y_q3);
				end else if (auto_source == AUTO_DIGITAL) begin
					selected_x = q3_to_axis(digital_x_q3);
					selected_y = q3_to_axis(digital_y_q3);
				end
			end
			default: begin end
		endcase
		yoke_x = selected_x[7:0];
		yoke_y = selected_y[7:0];
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			mode_q <= INPUT_ANALOG;
			auto_source <= AUTO_ANALOG;
			mouse_toggle_q <= 1'b0;
			directions_q <= 4'd0;
			analog_reference_x <= 9'sd0;
			analog_reference_y <= 9'sd0;
			mouse_x_q3 <= 12'sd0;
			mouse_y_q3 <= 12'sd0;
			digital_x_q3 <= 12'sd0;
			digital_y_q3 <= 12'sd0;
			digital_tick_div <= 16'd0;
		end else begin
			mouse_toggle_q <= mouse[24];
			directions_q <= directions;
			digital_tick_div <= digital_tick_div + 1'd1;

			if (mode_change) begin
				mode_q <= requested_mode;
				analog_reference_x <= analog_x_raw;
				analog_reference_y <= analog_y_raw;
				if (requested_mode == INPUT_MOUSE) begin
					mouse_x_q3 <= axis_to_q3(selected_x);
					mouse_y_q3 <= axis_to_q3(selected_y);
				end else if ((requested_mode == INPUT_DIGITAL_CENTER) ||
				             (requested_mode == INPUT_DIGITAL_RELATIVE)) begin
					digital_x_q3 <= axis_to_q3(selected_x);
					digital_y_q3 <= axis_to_q3(selected_y);
				end else if (requested_mode == INPUT_AUTO) begin
					auto_source <= AUTO_ANALOG;
				end
			end else begin
				if ((mode_q == INPUT_MOUSE) && mouse_motion) begin
					mouse_x_q3 <= add_clamped_q3(mouse_x_q3, mouse_dx_q3);
					mouse_y_q3 <= add_clamped_q3(mouse_y_q3, mouse_dy_q3);
				end

				if (mode_q == INPUT_AUTO) begin
					if (digital_event) begin
						if (auto_source != AUTO_DIGITAL) begin
							digital_x_q3 <= axis_to_q3(selected_x);
							digital_y_q3 <= axis_to_q3(selected_y);
						end
						auto_source <= AUTO_DIGITAL;
						analog_reference_x <= analog_x_raw;
						analog_reference_y <= analog_y_raw;
					end else if (mouse_motion) begin
						mouse_x_q3 <= add_clamped_q3(
							auto_source == AUTO_MOUSE ? mouse_x_q3 :
							axis_to_q3(selected_x), mouse_dx_q3);
						mouse_y_q3 <= add_clamped_q3(
							auto_source == AUTO_MOUSE ? mouse_y_q3 :
							axis_to_q3(selected_y), mouse_dy_q3);
						auto_source <= AUTO_MOUSE;
						analog_reference_x <= analog_x_raw;
						analog_reference_y <= analog_y_raw;
					end else if ((auto_source != AUTO_ANALOG) && analog_motion) begin
						auto_source <= AUTO_ANALOG;
						analog_reference_x <= analog_x_raw;
						analog_reference_y <= analog_y_raw;
					end else if (auto_source == AUTO_ANALOG) begin
						analog_reference_x <= analog_x_raw;
						analog_reference_y <= analog_y_raw;
					end
				end

				if (digital_tick &&
				    ((mode_q == INPUT_DIGITAL_CENTER) ||
				     (mode_q == INPUT_DIGITAL_RELATIVE) ||
				     ((mode_q == INPUT_AUTO) &&
				      (auto_source == AUTO_DIGITAL)))) begin
					if ((mode_q != INPUT_DIGITAL_RELATIVE) || digital_x_active)
						digital_x_q3 <= step_toward_q3(
							digital_x_q3, digital_target_x, digital_step_q3);
					if ((mode_q != INPUT_DIGITAL_RELATIVE) || digital_y_active)
						digital_y_q3 <= step_toward_q3(
							digital_y_q3, digital_target_y, digital_step_q3);
				end
			end
		end
	end

endmodule

`default_nettype wire
