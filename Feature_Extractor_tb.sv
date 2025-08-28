`timescale 1ns/1ps
module Feature_Extractor_tb;

    // 1. 환경 설정
    logic clk;
    logic rst;
    logic start_signal;
    logic pixel_valid_in;
    logic [7:0] pixel_in;

    logic signed [21:0] final_result_out;
    logic             final_result_valid;
    logic             final_done_signal;
    logic     signed [21:0] min_val;
    logic  signed [21:0] max_val;
    logic signed [31:0] sum;
    
  
    
    // DUT 인스턴스화
    Feature_Extractor DUT (.*);

    // 클럭 및 리셋 생성
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 2. 테스트 파라미터 (쉽게 변경 가능)
    localparam IMG_WIDTH  = 32;
    localparam IMG_HEIGHT = 32;
    // Conv output: (32-3+1) = 30x30
    // Max Pool output: 30/2 = 15x15
    localparam EXPECTED_OUTPUT_COUNT = 15 * 15;  // 225개
    
  logic signed [21:0] results_array [0:EXPECTED_OUTPUT_COUNT-1];
  
    // 3. 테스트 데이터 생성 함수
    function [7:0] generate_test_pixel(int x, int y);
        // 다양한 패턴 선택 가능
        case (2) // 패턴 선택
            0: return 8'(x + y);              // 대각선 그라데이션
            1: return 8'((x * 16 + y) % 256); // 복잡한 패턴
            2: return 8'(100 + (x^y));        // XOR 패턴
            default: return 8'(x * IMG_WIDTH + y + 1); // 순차 증가
        endcase
    endfunction

    // 4. 기대값 계산 함수 (간단한 패턴용)
    function signed [21:0] calculate_expected_result(int pool_x, int pool_y);
        // 실제 conv + relu + maxpool 결과를 예측하기는 복잡하므로
        // 일단 패턴 기반으로 예상값 생성 (추후 실제 값으로 업데이트)
        return 22'(pool_x * 15 + pool_y + 100); // 임시 기대값
    endfunction

    // 5. 테스트 시나리오
    initial begin
        $display("=== Feature Extractor Test START ===");
        $display("Input Size: %0dx%0d", IMG_WIDTH, IMG_HEIGHT);
        $display("Expected Output Count: %0d", EXPECTED_OUTPUT_COUNT);
        
        // 초기화
        rst = 1;
        start_signal = 0;
        pixel_valid_in = 0;
        pixel_in = 0;
        #20 rst = 0;

        // 시작 신호
        start_signal = 1;
        #10 start_signal = 0;

        // 이미지 데이터 주입
        $display("Starting image data injection...");
        for (int y = 0; y < IMG_HEIGHT; y++) begin
            for (int x = 0; x < IMG_WIDTH; x++) begin
                @(posedge clk);
                pixel_valid_in = 1;
                pixel_in = generate_test_pixel(x, y);
                
                // 처음 몇 개만 출력
                if (y < 3 && x < 8) begin
                    $display("Pixel[%0d,%0d] = %h", x, y, pixel_in);
                end
            end
        end
        @(posedge clk);
        pixel_valid_in = 0;
        
        $display("Data injection complete. Waiting for results...");
    end

    // 6. 결과 수집 및 분석
    integer result_count = 0;
    
    
    always @(posedge clk) begin
        if (!rst && final_result_valid) begin
            if (result_count < EXPECTED_OUTPUT_COUNT) begin
                results_array[result_count] = final_result_out;
                
                // 처음 몇 개 결과만 출력
                if (result_count < 16) begin
                    $display("Result[%0d] = %h (%0d)", result_count, final_result_out, final_result_out);
                end
                
                result_count++;
            end else begin
                $display("WARNING: More results than expected!");
            end
        end
    end

    // 7. 최종 분석
    always @(posedge clk) begin
        if (final_done_signal) begin
            #10;
            $display("\n=== FINAL ANALYSIS ===");
            $display("Total Results Received: %0d", result_count);
            $display("Expected: %0d", EXPECTED_OUTPUT_COUNT);
            
            if (result_count == EXPECTED_OUTPUT_COUNT) begin
                $display("✓ Correct number of results received");
            end else begin
                $display("✗ Result count mismatch!");
            end
            
            // 결과 통계
            min_val = results_array[0];
            max_val = results_array[0];
            sum = 0;
            
            for (int i = 0; i < result_count; i++) begin
                if (results_array[i] < min_val) min_val = results_array[i];
                if (results_array[i] > max_val) max_val = results_array[i];
                sum += results_array[i];
            end
            
            $display("Result Statistics:");
            $display("  Min: %0d, Max: %0d", min_val, max_val);
            $display("  Average: %0d", sum / result_count);
            $display("  Non-zero results: %0d", count_nonzero());
            
            $display("=== TEST COMPLETE ===");
            $finish;
        end
    end
    
    // 보조 함수: 0이 아닌 결과 개수
    function integer count_nonzero();
        integer count = 0;
        for (int i = 0; i < result_count; i++) begin
            if (results_array[i] != 0) count++;
        end
        return count;
    endfunction

endmodule