`timescale 1ns/1ps
module Fully_Connected_Layer(
	input logic clk,
	input logic rst,
	input logic i_start,
	input logic signed [21:0] i_flattened_data [0:224],
	output logic o_result_valid,
	output logic signed [47:0] o_result_data
);

	// ===== 가중치 ROM (22비트 signed, weight.mem 파일에서 읽기) =====
	logic signed [21:0] weight_ROM [0 : 224];
	
	// ===== 상태 정의 (단순화) =====
	enum logic [1:0] {
		IDLE, 
		COMPUTE, 
		DONE
	} state;
	
	// ===== 내부 신호들 (최소화) =====
	logic [7:0] mac_cnt;
	logic mac_valid;
	logic signed [47:0] accumulator_reg;
	logic signed [47:0] mac_sum_in;
	logic signed [47:0] mac_sum_out;
	logic mac_sum_out_valid;
	
	// ===== MAC Unit =====
	MAC_unit MAC(
		.clk(clk), 
		.rst(rst), 
		.i_valid(mac_valid),
		.data_in_a(i_flattened_data[mac_cnt]),
		.data_in_b(weight_ROM[mac_cnt]),
		.sum_in(mac_sum_in),
		.o_valid(mac_sum_out_valid),
		.sum_out(mac_sum_out)
	);
	
	// ===== 시작 펄스 감지 =====
	logic i_start_d1;
	always_ff @(posedge clk or negedge rst) begin 
		if(!rst) 
			i_start_d1 <= 1'b0; 
		else 
			i_start_d1 <= i_start;
	end
	
	logic start_pulse = i_start & ~i_start_d1;
	
	// ===== 메인 상태 머신 (단순화) =====
	always_ff @(posedge clk or negedge rst) begin  
		if(!rst) begin  
			state <= IDLE;
			mac_cnt <= 8'h0;
			mac_valid <= 1'b0;
			accumulator_reg <= 48'h0;
			o_result_valid <= 1'b0;
		end else begin
			case(state) 
				IDLE: begin
					mac_valid <= 1'b0;
					o_result_valid <= 1'b0;
					
					if(start_pulse) begin
						accumulator_reg <= 48'h0;
						mac_cnt <= 8'h0;
						mac_valid <= 1'b1;
						state <= COMPUTE;
					end
				end
				
				COMPUTE: begin
					// MAC 결과 누적
					if(mac_sum_out_valid) begin
						accumulator_reg <= mac_sum_out;
					end
					
					// 모든 가중치 처리 완료?
					if(mac_cnt == 224) begin
						state <= DONE;
						mac_valid <= 1'b0;
						o_result_valid <= 1'b1;
					end else begin
						mac_cnt <= mac_cnt + 1'b1;
						mac_valid <= 1'b1;
					end
				end
				
				DONE: begin
					o_result_valid <= 1'b1;
					if(!i_start) begin  // start 해제되면 IDLE로
						state <= IDLE;
						o_result_valid <= 1'b0;
					end
				end
			endcase
		end
	end
	
	// ===== 출력 할당 =====
	assign mac_sum_in = accumulator_reg;
	assign o_result_data = accumulator_reg;
	
	// ===== weight.mem 파일에서 가중치 초기화 =====
	initial begin
		$readmemh("weight.mem", weight_ROM);
		$display("가중치 파일 로드 완료: weight.mem");
		
		// 처음 몇 개 가중치 확인 (디버깅용)
		$display("Weight[0] = 0x%06X", weight_ROM[0]);
		$display("Weight[1] = 0x%06X", weight_ROM[1]);
		$display("Weight[2] = 0x%06X", weight_ROM[2]);
		$display("Weight[224] = 0x%06X", weight_ROM[224]);
	end
	
endmodule