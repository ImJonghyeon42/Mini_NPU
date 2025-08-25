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
	
	