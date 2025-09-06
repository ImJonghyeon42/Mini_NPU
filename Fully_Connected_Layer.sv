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
	
	// ===== Weight ROM 초기화 =====
	initial begin
		$readmemh("weight.mem", weight_ROM);
		$display("--- [FC_DEBUG] Weight ROM 로딩 완료 ---");
		$display("--- [FC_DEBUG] weight_ROM[0] = 0x%h", weight_ROM[0]);
		$display("--- [FC_DEBUG] weight_ROM[1] = 0x%h", weight_ROM[1]);
		$display("--- [FC_DEBUG] weight_ROM[224] = 0x%h", weight_ROM[224]);
		$display("--------------------------------------");
	end

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
						$display("[FC_DEBUG] FC 연산 시작");
					end
				end
				
				COMPUTE: begin
					// MAC 결과 누적
					if(mac_sum_out_valid) begin
						accumulator_reg <= mac_sum_out;
						valid_out_cnt <= valid_out_cnt + 1'b1;
						
						// 디버깅: 처음 5개와 마지막 5개만 출력
						if (valid_out_cnt < 5 || valid_out_cnt >= 220) begin
							$display("[FC_DEBUG] MAC[%0d]: acc = %0d", valid_out_cnt, mac_sum_out);
						end
					end
					
					// 모든 가중치 처리 완료?
					if(mac_cnt == 224) begin
						state <= FLUSH;
						mac_valid <= 1'b0;
						$display("[FC_DEBUG] COMPUTE 완료, FLUSH로 이동");
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
						$display("[FC_DEBUG] FLUSH: 최종 결과 = %0d", mac_sum_out);
					end
					
					// 모든 MAC 출력 완료?
					if(valid_out_cnt >= 225) begin
						state <= RESULT_VALID;
						result_hold_counter <= 5'h0;
						o_result_valid <= 1'b1;
						$display("[FC_DEBUG] *** FC 연산 완료! 최종 결과 = %0d ***", accumulator_reg);
					end
				end
				
				RESULT_VALID: begin
					// 결과를 16클럭 동안 유지
					o_result_valid <= 1'b1;
					result_hold_counter <= result_hold_counter + 1'b1;
					
					if(result_hold_counter >= 15) begin
						state <= DONE;
						$display("[FC_DEBUG] 결과 유지 완료, DONE으로 이동");
					end
				end
				
				DONE: begin
					// 마지막 1클럭 더 유지 후 IDLE로
					o_result_valid <= 1'b1;
					state <= IDLE;
					$display("[FC_DEBUG] FC 처리 완료, IDLE로 복귀");
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
	
	// ===== 추가 디버깅 =====
	always @(posedge clk) begin
		if (start_pulse) begin
			$display("[FC_DEBUG] ===== FC Layer 시작 =====");
			$display("[FC_DEBUG] 입력 데이터 샘플:");
			$display("[FC_DEBUG] data[0] = %0d, data[1] = %0d", i_flattened_data[0], i_flattened_data[1]);
			$display("[FC_DEBUG] data[223] = %0d, data[224] = %0d", i_flattened_data[223], i_flattened_data[224]);
		end
		
		if (state == RESULT_VALID && result_hold_counter == 0) begin
			$display("[FC_DEBUG] 결과 출력 시작: valid=%b, data=%0d", o_result_valid, o_result_data);
		end
	end
	
endmodule