`timescale 1ns/1ps
module Fully_Connected_Layer(
	input logic clk,
	input logic rst,
	input logic i_start,
	input logic signed [21:0] i_flattened_data [0:224],
	output logic o_result_valid,
	output logic signed [47:0] o_result_data
);
	enum logic [1:0] {IDLE, COMPUTE, DONE} state;
	
	logic [7:0] mac_cnt;
	logic mac_valid;
	
	logic signed [21 : 0] weight_ROM [0 : 224];
	
	logic signed [47:0] accumulator_reg;
	
	logic signed [47:0] mac_sum_in;
	logic signed [47:0] mac_sum_out;
	logic mac_sum_out_valid;
	
	initial begin
		$readmemh("weight.mem", weight_ROM);
	end

	MAC_unit MAC(
		.clk, .rst, .i_valid(mac_valid),
		.data_in_a(i_flattened_data[mac_cnt]),
		.data_in_b(weight_ROM [mac_cnt]),
		.sum_in(mac_sum_in),
		.o_valid(mac_sum_out_valid),
		.sum_out(mac_sum_out)
	);
	
	always_ff@(posedge clk ) begin
		if(rst) begin
			state <= IDLE;
			mac_cnt <= '0;
			mac_valid <= 1'b0;
			accumulator_reg <= '0;
			o_result_valid <= 1'b0;
		end else begin
			o_result_valid <= 1'b0;
			mac_valid <= 1'b0;
			
			case(state) 
			IDLE : begin
				if(i_start) begin
					accumulator_reg <= '0;
					mac_cnt <= '0;
					mac_valid <= 1'b1;
					state <= COMPUTE;
				end
			end
			COMPUTE : begin
				if(mac_sum_out_valid) begin
					accumulator_reg <= mac_sum_out;
				end
				if(mac_cnt == 224) begin
					state <= DONE;
					mac_valid <= 1'b0;
				end else begin
					mac_cnt <= mac_cnt + 1'b1;
					mac_valid <= 1'b1;
				end
			end
			DONE : begin
				o_result_valid <= 1'b1;
				state <= IDLE;
			end
			endcase
		end
	end
	
	assign mac_sum_in = accumulator_reg;
	assign o_result_data = accumulator_reg;
endmodule