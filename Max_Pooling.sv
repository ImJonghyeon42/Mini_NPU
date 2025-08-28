`timescale 1ns/1ps
module Max_Pooling(
	input logic clk, 
	input logic rst,
	input logic pixel_valid,
	input logic start_signal,
	input logic signed [21:0]pixel_in,
	output logic signed [21:0] result_out,
	output logic result_valid,
	output logic done_signal
);
	parameter IMG_WIDTH = 32;
	parameter IMG_HEIGHT = 32;
	
	logic signed [21:0] pixel_d1;
	logic signed [21:0] line_buffer [0 : IMG_WIDTH-1];
	
	logic signed [21:0] win_top_left;
	logic signed [21:0] win_top_right;
	logic signed [21:0] win_bot_left;
	logic signed [21:0] win_bot_right;
	
	logic [5:0] cnt_x, cnt_y;
	
	logic pool_enable;
	
	logic signed [21:0] compare_stage1; 
	logic signed [21:0] compare_stage2; 
	logic signed [21:0] compare_MAX; 
	
	logic last_pixel_processed;
	//logic capture_condition_is_true;
	
	enum logic [1:0] {IDLE, PROCESSING, DONE} state, next_state;
	
	always_ff@(posedge clk) begin
		if(rst) begin
			pixel_d1 <= '0;
			line_buffer <= '{default : '0};
		end else if(state == PROCESSING && pixel_valid) begin
			pixel_d1 <= pixel_in;
			line_buffer[cnt_x] <= pixel_in;
		end
	end		
	
	always_ff@(posedge clk) begin
		if(rst) begin
			cnt_x <= '0;
			cnt_y <= '0;
		end else if(state == PROCESSING && pixel_valid) begin
			if(cnt_x == IMG_WIDTH-1) begin
				cnt_x <= '0;
				cnt_y <= cnt_y + 1'd1;
			end else begin
				cnt_x <= cnt_x + 1'd1;
			end
		end
	end
	
	always_comb begin
		next_state = state;
		case(state)
		IDLE : begin
			if(start_signal) begin
				next_state = PROCESSING;
			end
		end
		PROCESSING : begin
			if(last_pixel_processed) begin
				next_state = DONE;
			end
		end
		DONE : begin
			next_state = IDLE;
		end
		endcase
	end
	
	always_ff@(posedge clk) begin
		if(rst) begin
			state <= IDLE;
		end else begin
			state <= next_state;
		end
	end
	
	always_ff@(posedge clk) begin
		if(rst) begin
			result_out <= '0;
			result_valid <= 1'b0;
		end else begin
			result_valid <= pool_enable;
			if(pool_enable) begin
				result_out <= compare_MAX;
				if (compare_MAX != 0) begin
                $display("--- [DEBUG] Max_Pooling is producing NON-ZERO output: %h (%d)", compare_MAX, compare_MAX);
				end
			end
		end
	end
	
	assign win_top_left = (cnt_x == 0 || cnt_y == 0) ? '0 : line_buffer[cnt_x - 1];
	assign win_top_right = (cnt_y == 0)? '0 : line_buffer[cnt_x];
	assign win_bot_left = (cnt_x == 0)? '0 : pixel_d1;
	assign win_bot_right = pixel_in;
	
	assign pool_enable = pixel_valid && (cnt_x[0] == 1'b1) && (cnt_y[0] == 1'b1) && (state == PROCESSING);
	
	assign compare_stage1 = ($signed(win_top_left) >= $signed(win_top_right)) ? win_top_left : win_top_right;
	assign compare_stage2 = ($signed(win_bot_left) >= $signed(win_bot_right)) ? win_bot_left : win_bot_right;
	assign compare_MAX = ($signed(compare_stage1) >= $signed(compare_stage2)) ? compare_stage1 : compare_stage2;
	
	assign last_pixel_processed = (cnt_y == IMG_HEIGHT-1) && (cnt_x == IMG_WIDTH-1) && pixel_valid && (state == PROCESSING);
	assign done_signal = (state == DONE);
endmodule