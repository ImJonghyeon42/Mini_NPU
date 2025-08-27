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
	logic signed [21:0] conv_result;
	logic conv_valid;
	logic conv_done_signal;
	
	logic Activation_valid;
	logic signed [21:0] Activation_result;
	
	conv_engine_2d	U0(
		.clk, .rst, .start_signal, 
		.pixel_in, .pixel_valid(pixel_valid_in),
		.result_out(conv_result), .result_valid(conv_valid),
		.done_signal(conv_done_signal)
	);
	
	Activation_Function U1(
		.clk, .rst,
		.pixel_valid(conv_valid), .pixel_in(conv_result),
		.result_valid(Activation_valid), .result_out(Activation_result)
	);
	
	Max_Pooling #( .IMG_WIDTH(30), .IMG_HEIGHT(30))
	U2 (
		.clk, .rst, 
		.pixel_in(Activation_result), .pixel_valid(Activation_valid),
		.result_out(final_result_out), .result_valid(final_result_valid), 
		.done_signal(final_done_signal)
	   );
	
endmodule