`timescale 1ns/1ps
module Max_Pooling(
	input logic clk, 
	input logic rst,
	input logic start_signal,
	input logic pixel_valid,
	input logic signed [21:0]pixel_in,
	output logic signed [21:0] result_out,
	output logic result_valid,
	output logic done_signal
);
	localparam IMG_WIDTH = 32;
	localparam IMG_HEIGHT = 32;
	
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
	logic done_signal_reg;
	
	always_ff@(posedge clk) begin
		if(rst) begin
			pixel_d1 <= '0;
			line_buffer <= '{default : '0};
		end else if(pixel_valid) begin
			pixel_d1 <= pixel_in;
			line_buffer[cnt_x] <= pixel_in;
		end
	end		
	
	always_ff@(posedge clk) begin
		if(rst) begin
			cnt_x <= '0;
			cnt_y <= '0;
		end else if(start_signal) begin
			cnt_x <= '0;
			cnt_y <= '0;
		end else if(pixel_valid) begin
			if(cnt_x == IMG_WIDTH-1) begin
				cnt_x <= '0;
				cnt_y <= cnt_y + '1;
			end else begin
				cnt_x <= cnt_x + '1;
			end
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
			end
		end
	end
	
	always_ff@(posedge clk) begin
		if(rst) begin
			done_signal_reg <= 1'b0;
		end else begin
			done_signal_reg <= last_pixel_processed;
		end
	end
	
	assign win_top_left = (cnt_x == 0) ? '0 : line_buffer[cnt_x - 1];
	assign win_top_right = line_buffer[cnt_x];
	assign win_bot_left = pixel_d1;
	assign win_bot_right = pixel_in;
	
	assign pool_enable = pixel_valid && (cnt_x[0] == 1'b1) && (cnt_y[0] == 1'b1);
	
	assign compare_stage1 = (win_top_left >= win_top_right) ? win_top_left : win_top_right;
	assign compare_stage2 = (win_bot_left >= win_bot_right) ? win_bot_left : win_bot_right;
	assign compare_MAX = (compare_stage1 >= compare_stage2) ? compare_stage1 : compare_stage2;
	
	assign last_pixel_processed = (cnt_y == IMG_HEIGHT-1) && (cnt_x == IMG_WIDTH-1) && pixel_valid;
	assign done_signal = done_signal_reg;
	
endmodule