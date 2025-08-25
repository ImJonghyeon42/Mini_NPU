`timescale 1ns/1ps
module CONV_RELU_TOP(
	input logic clk,
	input logic rst,
	input logic start_signal,
	input logic pixel_valid,
	input logic [7:0] pixel_in,

	output logic signed [21:0] result_out,
	output logic             result_valid,
	output logic             done_signal
);

	// 내부 연결 신호
	logic signed [21:0] conv_result;
	logic             conv_valid;
	
	// 1. Convolution Engine 인스턴스
	conv_engine_2d U0_CONV (
		.clk, .rst, .start_signal, .pixel_valid, .pixel_in,
		.result_out(conv_result),
		.result_valid(conv_valid),
		.done_signal(done_signal) // done 신호는 conv 엔진에서 나옴
	);
	
	// 2. Activation Function 인스턴스
	Activation_Function U1_RELU (
		.clk, .rst,
		.pixel_valid(conv_valid),
		.pixel_in(conv_result),
		.result_out(result_out),
		.result_valid(result_valid)
	);
	
endmodule