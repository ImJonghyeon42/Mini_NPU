`timescale 1ns/1ps
module flatten_buffer (
	input logic clk,
	input logic rst,
	input logic i_data_valid,
	input logic signed [21:0] i_data_in,
	output logic o_buffer_full,
	output logic signed [21:0] o_flattened_data [0 : 224]
);
	
	logic signed [21:0] buffer_mem [0 : 224];
	
	logic [7:0] write_addr_cnt;
	
	enum logic [1:0] {IDLE, PROCESSING, FULL} state;
	
	always_ff@(posedge clk) begin
		if(rst) begin
			state <= IDLE;
			buffer_mem <= '{default: '0};
			write_addr_cnt <= '0;
		end else begin
			if(i_data_valid) begin
				case(state)
					IDLE : begin
						buffer_mem[0] <= i_data_in;
						write_addr_cnt <= 1;
						state <= PROCESSING;
					end
					PROCESSING : begin
						buffer_mem[write_addr_cnt] <= i_data_in;
						if(write_addr_cnt == 224) begin
							state <= FULL;
						end else begin
							write_addr_cnt <= write_addr_cnt + 1'd1;
						end
					end
				endcase
			end
		end
	end
	
	assign o_buffer_full = (state == FULL);
	assign o_flattened_data = buffer_mem;
	
endmodule