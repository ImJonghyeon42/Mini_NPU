`timescale 1ns/1ps
module simple_conv_test;
    logic clk, rst, start_signal;
    logic [7:0] pixel_count;
    logic done;
    
    enum logic [1:0] {IDLE, PROCESSING, DONE_STATE} state;
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            state <= IDLE;
            pixel_count <= 0;
            done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    pixel_count <= 0;
                    done <= 0;
                    if (start_signal) begin
                        state <= PROCESSING;
                        $display("[TEST] 시작!");
                    end
                end
                
                PROCESSING: begin
                    pixel_count <= pixel_count + 1;
                    if (pixel_count % 10 == 0) begin
                        $display("[TEST] 픽셀 %0d 처리", pixel_count);
                    end
                    
                    if (pixel_count == 100) begin  // 100개만 테스트
                        state <= DONE_STATE;
                        done <= 1;
                        $display("[TEST] 완료!");
                    end
                end
                
                DONE_STATE: begin
                    state <= IDLE;
                end
            endcase
        end
    end
    
    initial begin
        $display("=== 단순 카운터 테스트 ===");
        rst = 1;
        start_signal = 0;
        #100;
        rst = 0;
        
        repeat(10) @(posedge clk);
        start_signal = 1;
        @(posedge clk);
        start_signal = 0;
        
        wait (done == 1);
        $display("성공: 카운터 동작 확인");
        $finish;
    end
    
endmodule