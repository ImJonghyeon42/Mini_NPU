`timescale 1ns/1ps
module Activation_Function #(parameter DATA_WIDTH = 22)( // N은 입출력의 비트 폭입니다.
	input logic clk,
	input logic rst,
	input logic pixel_valid,
	input logic signed [DATA_WIDTH-1:0] pixel_in,
	output logic result_valid,
	output logic signed [DATA_WIDTH-1:0] result_out
);
	
	always_ff@(posedge clk) begin
		if(rst) begin
			result_out <= '0;
			result_valid <= 1'b0;
		end else begin
			result_valid <= pixel_valid;
			// ReLU 기능: 음수이면 0, 양수이면 그대로
			result_out <= (pixel_in[DATA_WIDTHN-1]) ? '0 : pixel_in;
		end
	end
	
endmodule