`timescale 1ns/1ps
module conv_engine(
	input logic clk,
	input logic rst,
	input logic start,
	input logic [255:0] pixel_row_data,
	output logic done_signal,
	output logic signed [17:0] result_data [0:29]
);
	enum logic [1:0] {IDLE, LOAD, PROCESSING, DONE} state;
	logic [5:0] count;
	logic [7:0] memory_data [0:31];  // 메모리 대신 배열 사용
	logic [7:0] pixel_window [0:2];   // 3개 원소만 필요
	
	logic [7:0] pixel_reg1 [0:2];
	logic [7:0] pixel_reg2 [0:2];
	
	logic signed [17:0] pipe1_out,pipe2_out,pipe3_out;
	logic signed [7:0] kernel [0:2] = '{-1,2,-1};
	
	
	always_ff@(posedge clk) begin
	   if(rst) begin
	      pixel_reg1 <= '{default: '0};
		  pixel_reg2 <= '{default: '0};
	   end
	   else begin
		  pixel_reg1 <= pixel_window;
		  pixel_reg2 <= pixel_reg1;
	   end
	end
	      
	compute_unit U0(
		.clk,.rst,
		.pixel_a(pixel_window[0]),
		.weight_b(kernel[0]),
		.sum_in('0),
		.sum_out(pipe1_out)
	);
	compute_unit U1(
		.clk,.rst,
		.pixel_a(pixel_reg1[1]),
		.weight_b(kernel[1]),
		.sum_in(pipe1_out),
		.sum_out(pipe2_out)
	);
	compute_unit U2(
		.clk,.rst,
		.pixel_a(pixel_reg2[2]),
		.weight_b(kernel[2]),
		.sum_in(pipe2_out),
		.sum_out(pipe3_out)
	);
	
	always_ff@(posedge clk) begin
		if(rst) begin
			state <= IDLE;
			count <= '0;
			done_signal <= '0;
			pixel_window <= '{default: '0};
			result_data <= '{default: '0};
			memory_data <= '{default: '0};
			
		end else begin		
		    done_signal <= '0;
			case(state)
				IDLE : begin
					if(start) begin
						state <= LOAD;
						count <= 6'd0;
					end
				end
				LOAD: begin
					// 입력 데이터를 메모리 배열에 저장
					memory_data[count[4:0]] <= pixel_row_data[count[4:0]*8 +: 8];
					
					if(count[4:0] == 5'd31) begin
						state <= PROCESSING;
						count <= 6'd0;
						// 첫 번째 window 초기화 [0,0,데이터[0]]
						pixel_window[0] <= 8'd0;
						pixel_window[1] <= 8'd0;  
						pixel_window[2] <= memory_data[0];
					end
					else count <= count + 6'd1;
				end
				PROCESSING : begin
					// Window sliding: 매 클록마다 한 칸씩 이동
					if(count < 6'd30) begin  // 30개 결과 생성
						// Window 업데이트
						if(count == 0) begin
							// 첫 번째: [0,0,data[0]]는 이미 LOAD에서 설정됨
						end else if(count == 1) begin
							// 두 번째: [0,data[0],data[1]]
							pixel_window[0] <= 8'd0;
							pixel_window[1] <= memory_data[0];
							pixel_window[2] <= memory_data[1];
						end else begin
							// 일반적인 경우: [data[i-2],data[i-1],data[i]]
							if((count-2) < 32) pixel_window[0] <= memory_data[count-2];
							else pixel_window[0] <= 8'd0;
							
							if((count-1) < 32) pixel_window[1] <= memory_data[count-1];
							else pixel_window[1] <= 8'd0;
							
							if(count < 32) pixel_window[2] <= memory_data[count];
							else pixel_window[2] <= 8'd0;
						end
						
						// 결과 저장 (1클록 지연 고려)
						if(count >= 3) begin
							result_data[count-3] <= pipe3_out;
						end
						
						count <= count + 6'd1;
					end else begin
						// 마지막 결과 저장
						if(count >= 3 && (count-3) < 30) begin
						  result_data[count-3] <= pipe3_out;
						end
						if(count >= 32) begin
						  state <= DONE;
						end else begin
						  count <= count + 6'd1;
						end											
					end
				end
				DONE: begin
					done_signal <= 1'b1;
					state <= IDLE;
				end
			endcase
		end
	end
endmodule