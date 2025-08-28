`timescale 1ns/1ps
module Max_Pooling #(
	parameter DATA_WIDTH  = 22,// 데이터 정밀도를 위한 비트 폭. 세부사항과 하드웨어 효율성의 균형을 맞춥니다.
	parameter IMG_SIZE    = 30,// 입력 특징 맵의 크기. 
	parameter POOL_SIZE   = 2 // 풀링 윈도우의 크기. 2x2는 데이터 크기 감소를 위한 표준입니다
)(
    input logic clk, 
    input logic rst,
    //input logic start_signal,
    input logic pixel_valid,
	input logic [1:0] pool_type,
    input logic signed [DATA_WIDTH-1:0] pixel_in,
    output logic signed [DATA_WIDTH-1:0] result_out,
    output logic result_valid,
    output logic done_signal
);	
	logic signed [21:0] pixel_d1;
	logic signed [21:0] line_buffer [0:IMG_SIZE-1];
	
	logic signed [21:0] win_00, win_01, win_10, win_11;
	
	logic signed [DATA_WIDTH-1:0] max_result, avg_result;  // 풀링 계산 로직: 풀링 타입에 따라 결과를 결정합니다.
	
	logic [5:0] cnt_x, cnt_y;
	logic [4:0] out_x, out_y;  // 출력 카운터 (15x15)
	
	logic pool_enable;
	
	enum logic [1:0] {IDLE, PROCESSING, DONE} state, next_state;
	
	// 픽셀 지연 및 라인 버퍼
	always_ff@(posedge clk) begin
		if(rst) begin
			pixel_d1 <= '0;
			line_buffer <= '{default: '0};
		end else if(pixel_valid && state == PROCESSING) begin
			pixel_d1 <= pixel_in;
			if(cnt_x < IMG_SIZE-1 || cnt_y < IMG_SIZE-1) begin
				line_buffer[cnt_x] <= pixel_d1;  // 지연된 픽셀 사용
			end
		end
	end
	
	// 입력 위치 카운터
	always_ff@(posedge clk) begin
		if(rst) begin
			cnt_x <= '0;
			cnt_y <= '0;
		end else if(state == PROCESSING && pixel_valid) begin
			if(cnt_x == IMG_SIZE-1) begin
				cnt_x <= '0;
				cnt_y <= cnt_y + 1'd1;
			end else begin
				cnt_x <= cnt_x + 1'd1;
			end
		end
	end
	
	// 출력 위치 카운터
	always_ff@(posedge clk) begin
		if(rst) begin
			out_x <= '0;
			out_y <= '0;
		end else if(result_valid) begin
			if(out_x == 14) begin  // 15개 출력 후
				out_x <= '0;
				out_y <= out_y + 1'd1;
			end else begin
				out_x <= out_x + 1'd1;
			end
		end
	end
	
	// 상태 머신
	always_comb begin
		next_state = state;
		case(state)
		IDLE: if(pixel_valid) next_state = PROCESSING;
		PROCESSING: if(cnt_y == IMG_SIZE-1 && cnt_x == IMG_SIZE-1 && pixel_valid) 
					next_state = DONE;
		DONE: next_state = IDLE;
		endcase
	end
	
	always_ff@(posedge clk) begin
		if(rst) state <= IDLE;
		else state <= next_state;
	end
	
	// 2x2 윈도우 생성 (올바른 로직)
	always_comb begin
		win_00 = '0; win_01 = '0; win_10 = '0; win_11 = '0;
		
		if(cnt_y == 0) begin
			// 첫 번째 행: 위쪽 데이터 없음
			win_10 = (cnt_x == 0) ? '0 : pixel_d1;
			win_11 = pixel_in;
		end else begin
			// 두 번째 행 이후: 2x2 윈도우 구성
			win_00 = (cnt_x == 0) ? '0 : line_buffer[cnt_x-1];
			win_01 = line_buffer[cnt_x];
			win_10 = (cnt_x == 0) ? '0 : pixel_d1;
			win_11 = pixel_in;
		end
	end
	
	// Max 계산
	logic signed [21:0] max_top, max_bot;
	assign max_top = (win_00 >= win_01) ? win_00 : win_01;
	assign max_bot = (win_10 >= win_11) ? win_10 : win_11;
	assign max_result = (max_top >= max_bot) ? max_top : max_bot;
	
	assign avg_result = (win_00 + win_01 + win_10 + win_11) >>> 2;
	
	// Pool 활성화 조건: 홀수 위치에서만 출력 (stride=2)
	assign pool_enable = pixel_valid && (cnt_x[0] == 1'b1) && (cnt_y[0] == 1'b1) && (state == PROCESSING);
	
	// 출력 등록
	always_ff@(posedge clk) begin
		if(rst) begin
			result_out <= '0;
			result_valid <= 1'b0;
		end else begin
			result_valid <= pool_enable;
			if(pool_enable) begin
				case (pool_type)
					2'b00: result_out <= max_result;
					2'b01: result_out <= avg_result;
					default: result_out <= max_result;
				endcase
			end
		end
	end
	
	assign done_signal = (state == DONE);
	
endmodule