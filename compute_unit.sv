`timescale 1ns/1ps
module compute_unit (
	input logic clk,
	input logic rst,
	input logic [7:0] pixel_a, 
	input logic signed [7:0] weight_b,
	output logic signed  [17:0] sum_out
);
	logic	signed	[16 : 0]	sum_out_reg;
	always_ff@(posedge clk) begin
		if(rst) begin
			sum_out_reg <= '0;
		end else begin
			
			sum_out_reg <= signed'({1'b0, pixel_a}) * signed'(weight_b);
		end
	end
	assign	sum_out	=	sum_out_reg;
endmodule