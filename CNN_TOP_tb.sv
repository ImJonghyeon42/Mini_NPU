`timescale 1ns/1ps
// ===================================================================================
//  Module: CNN_TOP_Final_tb (안정적인 최종 테스트벤치)
//  Description:
//    - 원래 검증된 구조를 기반으로 한 안정적 테스트
//    - SystemVerilog 문법 오류 완전 제거
//    - 프로젝트 성공에 집중한 실용적 접근
// ===================================================================================
module CNN_TOP_Final_tb;

    // =================================================================
    // 1. DUT 신호 선언 및 인스턴스화
    // =================================================================
    logic clk;
    logic rst;
    logic start_signal;
    logic pixel_valid;
    logic [7:0] pixel_in;
    logic final_result_valid;
    logic signed [47:0] final_lane_result;

    CNN_TOP DUT (.*);

    // 클럭 생성
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // =================================================================
    // 2. 테스트 파라미터 및 데이터 저장 공간
    // =================================================================
    localparam IMG_WIDTH  = 32;
    localparam IMG_HEIGHT = 32;
    localparam CONV_OUT_SIZE = IMG_WIDTH - 2;      // 30
    localparam POOL_OUT_SIZE = CONV_OUT_SIZE / 2;  // 15
    localparam FLATTEN_SIZE  = POOL_OUT_SIZE * POOL_OUT_SIZE; // 225

    // 테스트를 위한 데이터 배열
    logic [7:0]               input_image [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    logic signed [21:0]       fc_weights  [0:FLATTEN_SIZE-1];
    logic signed [47:0]       dut_result;
    logic signed [47:0]       golden_result;

    // =================================================================
    // 3. [핵심] 안정적인 Golden Model - 단순하고 확실한 구조
    // =================================================================
    function automatic logic signed [47:0] golden_model_cnn_complete(
        input logic [7:0]         image[0:IMG_HEIGHT-1][0:IMG_WIDTH-1],
        input logic signed [21:0] weights[0:FLATTEN_SIZE-1]
    );
        // 모든 변수를 함수 내부에서 지역변수로 선언
        logic signed [7:0]    kernel[0:2][0:2];
        logic signed [21:0]   conv_relu_map[0:CONV_OUT_SIZE-1][0:CONV_OUT_SIZE-1];
        logic signed [21:0]   flattened_data[0:FLATTEN_SIZE-1];
        logic signed [47:0]   fc_result;
        integer pool_idx;
        
        // 커널 초기화
        kernel = '{'{1,0,-1}, '{2,0,-2}, '{1,0,-1}};
        fc_result = 0;
        
        $display("=== Golden Model: Starting CNN Processing ===");
        
        // --- 1단계: Conv + ReLU ---
        for (int y = 0; y < CONV_OUT_SIZE; y++) begin
            for (int x = 0; x < CONV_OUT_SIZE; x++) begin
                logic signed [21:0] mac_sum = 0;
                for (int ky = 0; ky < 3; ky++)
                    for (int kx = 0; kx < 3; kx++)
                        mac_sum += $signed({1'b0, image[y+ky][x+kx]}) * $signed(kernel[ky][kx]);
                conv_relu_map[y][x] = (mac_sum < 0) ? 0 : mac_sum;
            end
        end

        // --- 2단계: Max_Pooling.0.2.sv 정확한 동작 모방 ---
        pool_idx = 0;
        $display("=== Golden Model: Max Pooling (Exact Hardware Match) ===");
        
        // 실제 하드웨어와 정확히 동일한 2x2 non-overlapping pooling
        for (int output_y = 0; output_y < POOL_OUT_SIZE; output_y++) begin
            for (int output_x = 0; output_x < POOL_OUT_SIZE; output_x++) begin
                logic signed [21:0] block_00, block_01, block_10, block_11;
                logic signed [21:0] max_top, max_bot, block_max;
                
                // 하드웨어와 정확히 동일한 2x2 블록 추출
                block_00 = conv_relu_map[output_y*2][output_x*2];
                block_01 = conv_relu_map[output_y*2][output_x*2+1];
                block_10 = conv_relu_map[output_y*2+1][output_x*2];
                block_11 = conv_relu_map[output_y*2+1][output_x*2+1];
                
                // 하드웨어와 정확히 동일한 Max 계산
                max_top = (block_00 >= block_01) ? block_00 : block_01;
                max_bot = (block_10 >= block_11) ? block_10 : block_11;
                block_max = (max_top >= max_bot) ? max_top : max_bot;
                
                flattened_data[pool_idx] = block_max;
                
                if (pool_idx < 10) begin
                    $display("GOLDEN POOL[%0d] at out(%0d,%0d): block=[%h,%h,%h,%h] → max=%h", 
                             pool_idx, output_x, output_y, 
                             block_00, block_01, block_10, block_11, block_max);
                end
                
                pool_idx++;
            end
        end

        // --- 3단계: Fully Connected ---
        for (int i = 0; i < FLATTEN_SIZE; i++) begin
            fc_result += flattened_data[i] * weights[i];
        end
        
        $display("=== Golden Model: Final Result = %0d ===", fc_result);
        return fc_result;
    endfunction

    // =================================================================
    // 4. 메인 테스트 시퀀스 (검증된 구조 사용)
    // =================================================================
    initial begin
        $display("===============================================================");
        $display("=== CNN Hardware Accelerator Integration Test START ===");
        $display("===============================================================");
        
        // --- 1. 테스트 데이터 및 가중치 생성 ---
        // 테스트용 입력 이미지 생성 (XOR 패턴)
        for (int y = 0; y < IMG_HEIGHT; y++)
            for (int x = 0; x < IMG_WIDTH; x++)
                input_image[y][x] = 8'(100 + (x^y));

        // FC Layer 가중치 생성 (예: 1, 2, 3... 순차 증가)
        for (int i = 0; i < FLATTEN_SIZE; i++)
            fc_weights[i] = i + 1;
        
        // --- 2. [중요] DUT가 읽을 weight.mem 파일 자동 생성 ---
        $writememh("weight.mem", fc_weights);
        $display("--- Testbench generated 'weight.mem' for DUT ---");

        // --- 3. Golden Model을 통해 '정답' 미리 계산 ---
        golden_result = golden_model_cnn_complete(input_image, fc_weights);
        $display("--- Golden Model calculated expected result: %0d", golden_result);

        // --- 4. DUT 리셋 ---
        rst = 1; #20; rst = 0;

        // --- 5. DUT에 데이터 주입 ---
        start_signal = 1; @(posedge clk); start_signal = 0;
        for (int i = 0; i < IMG_WIDTH*IMG_HEIGHT; i++) begin
            pixel_valid = 1;
            pixel_in = input_image[i / IMG_WIDTH][i % IMG_WIDTH];
            @(posedge clk);
        end
        pixel_valid = 0;
        
        // --- 6. DUT 결과 대기 및 캡처 ---
        $display("--- Waiting for DUT result...");
        fork
            begin
                wait (final_result_valid == 1);
                @(posedge clk); // 안정적인 캡처를 위해 1클럭 대기
                dut_result = final_lane_result;
            end
            begin
                #100000; // 100us 타임아웃
                $display("[ERROR] Timeout waiting for DUT result!");
                $finish;
            end
        join_any
        disable fork;
        
        // --- 7. 결과 자동 비교 및 판정 ---
        $display("\n=== FINAL ANALYSIS ===");
        if (dut_result === golden_result) begin
            $display("    >> DUT Result: %0d (0x%h)", dut_result, dut_result);
            $display("    >> Expected:   %0d (0x%h)", golden_result, golden_result);
            $display("    >> [VERDICT] ✓ TEST PASSED!");
        end else begin
            $display("    >> DUT Result: %0d (0x%h)", dut_result, dut_result);
            $display("    >> Expected:   %0d (0x%h)", golden_result, golden_result);
            $display("    >> Difference: %0d", dut_result - golden_result);
            $display("    >> [VERDICT] ✗ TEST FAILED!");
        end
        
        $display("=== TEST COMPLETE ===");
        $finish;
    end

    // =================================================================
    // 5. 실시간 모니터링 (디버깅용)
    // =================================================================
    
    // Feature Extractor 진행 모니터링
    integer feature_count = 0;
    always @(posedge clk) begin
        if (DUT.feature_valid) begin
            if (feature_count < 5) begin
                $display("[MONITOR] Feature[%0d] = %0d", feature_count, DUT.feature_result);
            end
            feature_count = feature_count + 1;
        end
    end
    
    // Flatten Buffer 상태 모니터링
    always @(posedge clk) begin
        if (DUT.flattened_buffer_full) begin
            $display("[MONITOR] Flatten Buffer Full - Starting FC Layer");
        end
    end

endmodule