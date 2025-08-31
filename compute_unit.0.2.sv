`timescale 1ns/1ps
module compute_unit #(
	parameter N = 8,
	parameter Q = 8
)(
	input logic clk,
	input logic rst,
	input logic [7:0] pixel_a, 
	input logic signed [7:0] weight_b,
	output logic signed  [17:0] sum_out
);
	logic signed [(N*2)-1:0] mul_result;
	
	always_ff@(posedge clk) begin
		if(rst) begin
			sum_out <= '0;
		end else begin
			mul_result <= signed'({1'b0, pixel_a}) * weight_b;
			sum_out <= mul_result >>> Q;
		end
	end
endmodule