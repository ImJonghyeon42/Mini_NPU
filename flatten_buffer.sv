`timescale 1ns/1ps
module flatten_buffer (
	input logic clk,
	input logic rst,
	input logic i_data_valid,
	input logic signed [21:0] i_data_in,
	input logic i_fc_done,
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
			if(i_fc_done && state == FULL) begin
				state <= IDLE;
				write_addr_cnt <= '0;
				$display("--- [DEBUG] flatten_buffer: Reset to IDLE after FC completion");
			end else if(i_data_valid) begin
				if (write_addr_cnt < 5) begin
					$display("--- [DEBUG] flatten_buffer received data[%0d] = %h (%0d)", write_addr_cnt, i_data_in, i_data_in);
				end
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
							$display("--- [DEBUG] flatten_buffer: Buffer FULL");
						end else begin
							write_addr_cnt <= write_addr_cnt + 1'd1;
						end
					end
					FULL : begin
					end
				endcase
			end
		end
	end
	
	assign o_buffer_full = (state == FULL);
	assign o_flattened_data = buffer_mem;
	
endmodule