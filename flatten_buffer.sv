`timescale 1ns/1ps
module flatten_buffer (
	input logic clk,
	input logic rst,
	input logic start_signal,
	input logic pixel_valid,
	input logic signed [21:0] pixel_in,
	output logic result_valid,
	output logic signed [21:0] result_out [0:224],
	output logic done_signal
);
	parameter DATA_WIDTH = 22;
	parameter ADDR_WIDTH = 8;  // 주소 버스의 비트 수 (2^ADDR_WIDTH >= 225 이므로, 8-bit), 2^8 = 256, so 8 bits are enough for 225 addresses
	
	