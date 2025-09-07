`timescale 1ns/1ps
module Fully_Connected_Layer(
	input logic clk,
	input logic rst,
	input logic i_start,
	input logic signed [21:0] i_flattened_data [0:224],
	output logic o_result_valid,
	output logic signed [47:0] o_result_data
);

	// ===== 상태 정의 =====
	enum logic [2:0] {
		IDLE, 
		COMPUTE, 
		FLUSH, 
		RESULT_VALID,
		DONE
	} state;
	
	// ===== 내부 신호들 =====
	logic [7:0] mac_cnt;
	logic mac_valid;
	
	logic signed [21:0] weight_ROM [0:224];
	logic signed [47:0] accumulator_reg;
	logic signed [47:0] mac_sum_in;
	logic signed [47:0] mac_sum_out;
	logic mac_sum_out_valid;
	
	logic [7:0] valid_out_cnt;
	logic signed [21:0] data_a_d1, data_a_d2, data_a_d3;
	logic signed [21:0] data_b_d1, data_b_d2, data_b_d3;
	logic mac_valid_d1, mac_valid_d2, mac_valid_d3;
	
	// 결과 유지용 카운터 (16클럭 동안 유지)
	logic [4:0] result_hold_counter;

	// ===== MAC Unit =====
	MAC_unit MAC(
		.clk(clk), 
		.rst(rst), 
		.i_valid(mac_valid_d3),
		.data_in_a(data_a_d3),
		.data_in_b(data_b_d3),
		.sum_in(mac_sum_in),
		.o_valid(mac_sum_out_valid),
		.sum_out(mac_sum_out)
	);
	
	// ===== 시작 펄스 감지 =====
	logic i_start_d1;
	logic start_pulse;
	
	always_ff @(posedge clk or negedge rst) begin 
		if(!rst) 
			i_start_d1 <= 1'b0; 
		else 
			i_start_d1 <= i_start;
	end
	
	assign start_pulse = i_start & ~i_start_d1;
	
	// ===== 메인 상태 머신 =====
	always_ff @(posedge clk or negedge rst) begin  
		if(!rst) begin  
			state <= IDLE;
			mac_cnt <= 8'h0;
			mac_valid <= 1'b0;
			accumulator_reg <= 48'h0;
			o_result_valid <= 1'b0;
			valid_out_cnt <= 8'h0;
			result_hold_counter <= 5'h0;
			
			// 파이프라인 레지스터 초기화
			data_a_d1 <= 22'h0;
			data_a_d2 <= 22'h0;
			data_a_d3 <= 22'h0;
			data_b_d1 <= 22'h0;
			data_b_d2 <= 22'h0;
			data_b_d3 <= 22'h0;
			mac_valid_d1 <= 1'b0;
			mac_valid_d2 <= 1'b0;
			mac_valid_d3 <= 1'b0;
		end else begin
			
			// ===== 파이프라인 레지스터 업데이트 =====
			mac_valid_d1 <= mac_valid;
			mac_valid_d2 <= mac_valid_d1;
			mac_valid_d3 <= mac_valid_d2;

			data_a_d1 <= i_flattened_data[mac_cnt];
			data_a_d2 <= data_a_d1;
			data_a_d3 <= data_a_d2;
				
			data_b_d1 <= weight_ROM[mac_cnt];
			data_b_d2 <= data_b_d1;
			data_b_d3 <= data_b_d2;
			
			// ===== 상태별 처리 =====
			case(state) 
				IDLE: begin
					mac_valid <= 1'b0;
					o_result_valid <= 1'b0;
					result_hold_counter <= 5'h0;
					
					if(start_pulse) begin
						accumulator_reg <= 48'h0;
						mac_cnt <= 8'h0;
						mac_valid <= 1'b1;
						valid_out_cnt <= 8'h0;
						state <= COMPUTE;
					end
				end
				
				COMPUTE: begin
					// MAC 결과 누적
					if(mac_sum_out_valid) begin
						accumulator_reg <= mac_sum_out;
						valid_out_cnt <= valid_out_cnt + 1'b1;
					end
					
					// 모든 가중치 처리 완료?
					if(mac_cnt == 224) begin
						state <= FLUSH;
						mac_valid <= 1'b0;
					end else begin
						mac_cnt <= mac_cnt + 1'b1;
						mac_valid <= 1'b1;
					end
				end
				
				FLUSH: begin
					mac_valid <= 1'b0;
					
					// 마지막 MAC 결과 처리
					if(mac_sum_out_valid) begin
						accumulator_reg <= mac_sum_out;
						valid_out_cnt <= valid_out_cnt + 1'b1;
					end
					
					// 모든 MAC 출력 완료?
					if(valid_out_cnt >= 225) begin
						state <= RESULT_VALID;
						result_hold_counter <= 5'h0;
						o_result_valid <= 1'b1;
					end
				end
				
				RESULT_VALID: begin
					// 결과를 16클럭 동안 유지
					o_result_valid <= 1'b1;
					result_hold_counter <= result_hold_counter + 1'b1;
					
					if(result_hold_counter >= 15) begin
						state <= DONE;
					end
				end
				
				DONE: begin
					// 마지막 1클럭 더 유지 후 IDLE로
					o_result_valid <= 1'b1;
					state <= IDLE;
				end
				
				default: begin
					state <= IDLE;
				end
			endcase
		end
	end
	
	// ===== 출력 할당 =====
	assign mac_sum_in = accumulator_reg;
	assign o_result_data = accumulator_reg;
	
endmodule