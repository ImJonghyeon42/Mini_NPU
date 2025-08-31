`timescale 1ns/1ps
module Max_Pooling(
    input logic clk, 
    input logic rst,
    input logic start_signal,
    input logic pixel_valid,
    input logic signed [21:0] pixel_in,
    output logic signed [21:0] result_out,
    output logic result_valid,
    output logic done_signal
);
    parameter IMG_WIDTH = 30;
    parameter IMG_HEIGHT = 30;
    
    // 전체 이미지 저장 메모리
    logic signed [21:0] image_buffer [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    
    // 입력 카운터
    logic [5:0] input_x, input_y;
    logic input_complete;
    
    // 출력 카운터 (15x15 출력)
    logic [4:0] output_x, output_y;
    logic output_complete;
    
    // 상태 머신
    enum logic [2:0] {IDLE, INPUT_PHASE, PROCESSING_PHASE, DONE} state, next_state;
    
    // 상태 머신 로직
    always_comb begin
        next_state = state;
        case(state)
            IDLE: if(start_signal) next_state = INPUT_PHASE;
            INPUT_PHASE: if(input_complete) next_state = PROCESSING_PHASE;
            PROCESSING_PHASE: if(output_complete) next_state = DONE;
            DONE: next_state = IDLE;
        endcase
    end
    
    always_ff@(posedge clk) begin
        if(rst) state <= IDLE;
        else state <= next_state;
    end
    
    // 입력 단계: 전체 이미지 수집
    always_ff@(posedge clk) begin
        if(rst) begin
            input_x <= '0;
            input_y <= '0;
            input_complete <= '0;
        end else if(state == INPUT_PHASE && pixel_valid) begin
            // 이미지 버퍼에 저장
            image_buffer[input_y][input_x] <= pixel_in;
            
            // 카운터 업데이트
            if(input_x == IMG_WIDTH-1) begin
                input_x <= '0;
                if(input_y == IMG_HEIGHT-1) begin
                    input_y <= '0;
                    input_complete <= 1'b1;
                end else begin
                    input_y <= input_y + 1;
                end
            end else begin
                input_x <= input_x + 1;
            end
        end else if(state == IDLE) begin
            input_complete <= '0;
            input_x <= '0;
            input_y <= '0;
        end
    end
    
    // 처리 단계: 2x2 블록 처리
    logic processing_enable;
    logic signed [21:0] block_00, block_01, block_10, block_11;
    logic signed [21:0] block_max;
    
    assign processing_enable = (state == PROCESSING_PHASE);
    
    // 2x2 블록 추출 (완전히 안전한 메모리 읽기)
    always_comb begin
        if(processing_enable) begin
            block_00 = image_buffer[output_y*2][output_x*2];
            block_01 = image_buffer[output_y*2][output_x*2+1];
            block_10 = image_buffer[output_y*2+1][output_x*2];
            block_11 = image_buffer[output_y*2+1][output_x*2+1];
        end else begin
            block_00 = '0;
            block_01 = '0;
            block_10 = '0;
            block_11 = '0;
        end
    end
    
    // Max 계산
    logic signed [21:0] max_top, max_bot;
    always_comb begin
        max_top = (block_00 >= block_01) ? block_00 : block_01;
        max_bot = (block_10 >= block_11) ? block_10 : block_11;
        block_max = (max_top >= max_bot) ? max_top : max_bot;
    end
    
    // 출력 카운터 및 출력 생성
    always_ff@(posedge clk) begin
        if(rst) begin
            output_x <= '0;
            output_y <= '0;
            output_complete <= '0;
            result_out <= '0;
            result_valid <= '0;
        end else if(state == PROCESSING_PHASE) begin
            result_valid <= 1'b1;
            result_out <= block_max;
            
            // 출력 카운터 업데이트
            if(output_x == 14) begin  // 15x15 출력
                output_x <= '0;
                if(output_y == 14) begin
                    output_y <= '0;
                    output_complete <= 1'b1;
                end else begin
                    output_y <= output_y + 1;
                end
            end else begin
                output_x <= output_x + 1;
            end
        end else begin
            result_valid <= '0;
            if(state == IDLE) begin
                output_complete <= '0;
                output_x <= '0;
                output_y <= '0;
            end
        end
    end
    
    // 디버깅 (처음 몇 개만)
    always @(posedge clk) begin
        if (result_valid && output_y < 2) begin
            $display("BLOCK_POOL[%0t]: out(%0d,%0d) block=[%h,%h,%h,%h] → max=%h", 
                     $time, output_x, output_y, 
                     block_00, block_01, block_10, block_11, block_max);
        end
    end
    
    assign done_signal = (state == DONE);
    
endmodule