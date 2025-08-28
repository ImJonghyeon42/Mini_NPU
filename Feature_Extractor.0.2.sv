`timescale 1ns/1ps
module Feature_Extractor(
	input logic clk,
	input logic rst,
	input logic start_signal,
	input logic pixel_valid_in,
	input logic [7:0] pixel_in,
	output logic signed [21:0] final_result_out,
	output logic final_result_valid,
	output logic final_done_signal
);
	logic signed [21:0] conv_result,relu_result;
	logic conv_valid,relu_valid;
	logic conv_done_signal;
	
	logic signed [21:0] conv_result_reg, relu_result_reg;
	logic conv_valid_reg, relu_valid_reg;
	
	
	always_ff @(posedge clk) begin
		if(rst) begin
			conv_result_reg <= '0;
			conv_valid_reg <= '0;
			relu_result_reg <= '0;
			relu_valid_reg <= '0;
		end else begin	
			conv_result_reg <= conv_result;
			conv_valid_reg  <= conv_valid;
			relu_result_reg <= relu_result;
			relu_valid_reg  <= relu_valid;
		end
	end
	
	conv_engine_2d #( .IMG_SIZE(32)) U0(
		.clk, .rst, .start_signal, 
		.pixel_in, .pixel_valid(pixel_valid_in),
		.result_out(conv_result), .result_valid(conv_valid),
		.done_signal(conv_done_signal)
	);
	
	Activation_Function #(.N(22)) U2(
		.clk, .rst,
		.pixel_valid(conv_valid_reg), .pixel_in(conv_result_reg),
		.result_valid(relu_valid), .result_out(relu_result)
	);
	
	Max_Pooling #( .DATA_WIDTH(22), .IMG_SIZE(30))
	U3 (
		.clk, .rst, //.start_signal,
		.pixel_in(relu_result_reg), .pixel_valid(relu_valid_reg),
		.result_out(final_result_out), .result_valid(final_result_valid), 
		.done_signal(final_done_signal)
	   );
	
endmodule