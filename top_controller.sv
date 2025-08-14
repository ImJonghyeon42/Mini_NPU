`timescale 1ns/1ps
module top_controller(
	input logic clk,
	input logic rst,
	input logic start,
	input logic [7:0] rx_data,
	input logic  rx_valid,
	output logic  [7:0] tx_data,
	output logic done_signal
);

	logic start_signal;
	logic conv_engine_done;
	logic signed [17:0] max_val_reg;
	logic [5:0]  count;
	logic signed [255:0] flattened_pixel_data;
	logic [7:0] pixel_row_data [0:31];
	logic signed [17:0] result_data [0:29];
	
	enum logic [2:0] {IDLE, RECEIVE_DATA, COMPUTE, FIND_MAX, SEND_RESULT} state;
	
	always_comb begin
		for( int i=0;i<32;i++) flattened_pixel_data[i*8 +: 8] = pixel_row_data[i];
	end
	
	conv_engine U0(
		.clk, .rst,
		.start(start_signal),
		.pixel_row_data(flattened_pixel_data),
		.done_signal(conv_engine_done),
		.result_data
	);

	always_ff@(posedge clk) begin
		if(rst) begin
			max_val_reg <= '0;
			state <= IDLE;
			count <= '0;
			start_signal <= '0;
			done_signal <= 0;
			tx_data <= '0;
			pixel_row_data <= '{default: '0};
		end
		else begin
			start_signal <= '0;
			done_signal <= 0;
			case(state) 
				IDLE : if(start) state <= RECEIVE_DATA;
				RECEIVE_DATA : begin
					if(rx_valid) begin
						pixel_row_data[count] <= rx_data;
						if(count == 31) begin
							state <= COMPUTE;
							count <= '0;
							start_signal <= '1;
						end
						else count <= count +'1;
					end
				end
				COMPUTE : begin
					if(conv_engine_done) begin
						state <= FIND_MAX;
						max_val_reg <= result_data[0];
						count <= '1;
					end
				end
				FIND_MAX : begin
					if(max_val_reg >= result_data[count] ) max_val_reg <= max_val_reg;
					else max_val_reg <= result_data[count];
					
					if(count == 29) begin
						state <= SEND_RESULT;
						count <= '0;
					end
					else count <= count + '1;
				end
				SEND_RESULT: begin
					tx_data <= max_val_reg[7:0];
					done_signal <= 1;
					state <= IDLE;
				end
			endcase
		end
	end
endmodule
	