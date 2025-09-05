`timescale 1ns/1ps
module MAC_unit(
	input logic clk,
	input logic rst,
	input logic i_valid,
	input logic signed [21:0] data_in_a,
	input logic signed [21:0] data_in_b,
	input logic signed [47:0] sum_in,
	output logic o_valid,
	output logic signed [47:0] sum_out
);
	logic signed [21:0] data_a_reg;
	logic signed [21:0] data_b_reg;
	logic signed [43:0] mul_result_reg;
	logic i_valid_d1;
	logic i_valid_d2;
	logic signed [47:0] sum_in_d1;
	logic signed [47:0] sum_in_d2;
	
	always_ff@(posedge clk or negedge rst) begin 
		if(!rst) begin  
			data_a_reg <= '0;
			data_b_reg <= '0;
			mul_result_reg <= '0;
			sum_out <= '0;
			i_valid_d1 <= '0;
			i_valid_d2 <= '0;
			o_valid <= '0;
			sum_in_d1 <= '0;
			sum_in_d2 <= '0;
		end else begin
			data_a_reg <= data_in_a;
			data_b_reg <= data_in_b;
			i_valid_d1 <= i_valid;
			sum_in_d1 <= sum_in;
			
			mul_result_reg <= data_a_reg * data_b_reg;
			i_valid_d2 <= i_valid_d1;
			sum_in_d2 <= sum_in_d1;
			
			sum_out <= mul_result_reg + sum_in_d2;
			o_valid <= i_valid_d2;
		end
	end
	
endmodule