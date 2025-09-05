`timescale 1ns/1ps
module Activation_Function(
	input logic clk,
	input logic rst,
	input logic pixel_valid,
	input logic signed [21:0] pixel_in,
	output logic result_valid,
	output logic signed [21:0] result_out
);
	
	always_ff@(posedge clk or negedge rst) begin  
		if(!rst) begin  
			result_out <= '0;
			result_valid <= 1'b0;
		end else begin
			result_valid <= pixel_valid;
			result_out <= (pixel_in[21] == 1'b1) ? '0 : pixel_in;
		end
	end
	
endmodule
