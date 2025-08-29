`timescale 1ns/1ps
module CNN_TOP(
	input logic clk,
	input logic rst,
	input logic start_signal,
	input logic pixel_valid,
	input logic [7:0] pixel_in,
	output logic final_result_valid,
	output logic signed [47:0] final_lane_result
);
	logic signed [21:0] feature_result;
	logic feature_valid;
	logic feature_done;
	
	logic flattened_buffer_full;
	logic signed [21:0] flatten_data [0:224];
	
	logic fc_done_pulse;
	logic fc_result_valid_d1;
	
	Feature_Extractor u_feature_extractor(
		.clk, .rst, .pixel_valid_in(pixel_valid),
		.start_signal, .pixel_in, .final_result_out(feature_result),
		.final_result_valid(feature_valid), .final_done_signal(feature_done)
	);
	
	flatten_buffer u_flatten_buffer(
		.clk, .rst, .i_data_valid(feature_valid),
		.i_data_in(feature_result), .o_buffer_full(flattened_buffer_full),
		.o_flattened_data(flatten_data), .i_fc_done(fc_done_pulse)
	);
	
	Fully_Connected_Layer u_fully_connected_layer(
		.clk, .rst, .i_start(flattened_buffer_full),
		.i_flattened_data(flatten_data), .o_result_valid(final_result_valid), 
		.o_result_data(final_lane_result)
	);
	
	always_ff @(posedge clk) begin
		if(rst) fc_result_valid_d1 <= 1'b0;
		else fc_result_valid_d1 <= final_result_valid;
	end
	
	assign fc_done_pulse = fc_result_valid_d1 & ~final_result_valid;
	
endmodule