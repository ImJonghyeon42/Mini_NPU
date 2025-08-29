`timescale 1ns/1ps
module Fully_Connected_Layer(
	input logic clk,
	input logic rst,
	input logic i_start,
	input logic signed [21:0] i_flattened_data [0:224],
	output logic o_result_valid,
	output logic signed [47:0] o_result_data
);
	enum logic [2:0] {IDLE, COMPUTE, FLUSH, DONE} state;
	
	logic [7:0] mac_cnt;
	logic mac_valid;
	
	logic signed [21 : 0] weight_ROM [0 : 224];
	
	logic signed [47:0] accumulator_reg;
	
	logic signed [47:0] mac_sum_in;
	logic signed [47:0] mac_sum_out;
	logic mac_sum_out_valid;
	
	logic [7:0] valid_out_cnt;
	
	logic signed [21:0] data_a_d1, data_a_d2,data_a_d3;
	logic signed [21:0] data_b_d1, data_b_d2,data_b_d3;
	
	logic mac_valid_d1,mac_valid_d2,mac_valid_d3;
	
	initial begin
		logic [21:0] temp_unsigned_rom [0:224];
		$readmemh("C:/Users/SAMSUNG/vivado_end_project/feature_test/feature_test.sim/sim_1/behav/xsim/weight.mem", temp_unsigned_rom);
		for(int i = 0; i <= 224; i++) begin
			weight_ROM[i] = $signed(temp_unsigned_rom[i]);
		end
		$display("--- [DEBUG] Fully_Connected_Layer: Checking loaded weights... ---");
		$display("--- [DEBUG] weight_ROM[0] = %h", weight_ROM[0]);
		$display("--- [DEBUG] weight_ROM[1] = %h", weight_ROM[1]);
		$display("--------------------------------------------------------------------");
	end

	MAC_unit MAC(
		.clk, .rst, .i_valid(mac_valid_d3),
		.data_in_a(data_a_d3),
		.data_in_b(data_b_d3),
		.sum_in(mac_sum_in),
		.o_valid(mac_sum_out_valid),
		.sum_out(mac_sum_out)
	);
	
	logic i_start_d1;
	logic start_pulse;
	
	always_ff@(posedge clk) begin
		if(rst) i_start_d1 <= 1'b0;
		else i_start_d1 <= i_start;
	end
	
	assign start_pulse = i_start & ~i_start_d1;
	
	always_ff@(posedge clk ) begin
		if(rst) begin
			state <= IDLE;
			mac_cnt <= '0;
			mac_valid <= 1'b0;
			accumulator_reg <= '0;
			o_result_valid <= 1'b0;
			valid_out_cnt <= '0;
			data_a_d1 <= '0;
			data_a_d2 <= '0;
			data_a_d3 <= '0;
			data_b_d1 <= '0;
			data_b_d2 <= '0;
			data_b_d3 <= '0;
			mac_valid_d2 <= 1'b0;
			mac_valid_d1 <= 1'b0;
			mac_valid_d3 <= 1'b0;
		end else begin
			o_result_valid <= 1'b0;
			
			mac_valid_d1 <= mac_valid;
			mac_valid_d2 <= mac_valid_d1;
			mac_valid_d3 <= mac_valid_d2;
	
			data_a_d1 <= i_flattened_data[mac_cnt];
			data_a_d2 <= data_a_d1;
			data_a_d3 <= data_a_d2;
				
			data_b_d1 <= weight_ROM[mac_cnt];
			data_b_d2 <= data_b_d1;
			data_b_d3 <= data_b_d2;
			
			case(state) 
			IDLE : begin
				mac_valid <= 1'b0;
				if(start_pulse) begin
					accumulator_reg <= '0;
					mac_cnt <= '0;
					mac_valid <= 1'b1;
					valid_out_cnt <= '0;
					state <= COMPUTE;
					$display("[FC_DEBUG] Starting FC computation...");
				end
			end
			COMPUTE : begin
				if(mac_sum_out_valid) begin
					accumulator_reg <= mac_sum_out;
					valid_out_cnt <= valid_out_cnt + 1'b1;
					if (valid_out_cnt < 5 || valid_out_cnt >= 220) begin
						$display("[FC_DEBUG] MAC[%0d]: acc = %0d", valid_out_cnt, mac_sum_out);
					end
				end
				if(mac_cnt == 224) begin
					state <= FLUSH;
					mac_valid <= 1'b0;
					$display("[FC_DEBUG] Moving to FLUSH state...");
				end else begin
					mac_cnt <= mac_cnt + 1'b1;
					mac_valid <= 1'b1;
				end
			end
			FLUSH : begin
				mac_valid <= 1'b0;
				if(mac_sum_out_valid) begin
					accumulator_reg <= mac_sum_out;
					valid_out_cnt <= valid_out_cnt + 1'b1;
					$display("[FC_DEBUG] FLUSH: final_acc = %0d", mac_sum_out);
				end
				if(valid_out_cnt == 225) begin
					state <= DONE;
					$display("[FC_DEBUG] FC computation complete!");
				end
			end
			DONE : begin
				o_result_valid <= 1'b1;
				state <= IDLE;
			end
			endcase
		end
	end
	
	assign mac_sum_in = accumulator_reg;
	assign o_result_data = accumulator_reg;
endmodule