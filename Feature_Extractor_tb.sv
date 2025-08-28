`timescale 1ns/1ps
module Feature_Extractor_tb;

    // =================================================================
    // == 1. 환경 설정 및 DUT 인스턴스화
    // =================================================================
    logic clk;
    logic rst;
    logic start_signal;
    logic pixel_valid_in;
    logic [7:0] pixel_in;

    logic signed [21:0] final_result_out;
    logic                 final_result_valid;
    logic                 final_done_signal;

    Feature_Extractor DUT (.*);

    // 클럭 생성
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // =================================================================
    // == 2. 테스트 파라미터 및 데이터 저장 공간
    // =================================================================
    localparam IMG_WIDTH  = 32;
    localparam IMG_HEIGHT = 32;
    localparam CONV_OUT_SIZE = IMG_WIDTH - 2; // 30
    localparam POOL_OUT_SIZE = CONV_OUT_SIZE / 2; // 15
    localparam EXPECTED_OUTPUT_COUNT = POOL_OUT_SIZE * POOL_OUT_SIZE; // 225

    // 테스트를 위한 데이터 배열
    logic [7:0] input_image [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    logic signed [21:0] dut_results [0:EXPECTED_OUTPUT_COUNT-1];
    logic signed [21:0] expected_results [0:EXPECTED_OUTPUT_COUNT-1];
    integer error_count = 0;
    integer result_count = 0;

    // =================================================================
    // == 3. 골든 모델 (Golden Model) - 정답을 계산하는 함수
    // =================================================================
    // DUT의 동작(Conv -> ReLU -> MaxPool)을 수학적으로 똑같이 구현
    function void golden_model_feature_extractor(
        input logic [7:0] image [0:IMG_HEIGHT-1][0:IMG_WIDTH-1],
        output logic signed [21:0] result [0:EXPECTED_OUTPUT_COUNT-1]
    );
        logic signed [7:0] kernel [0:2][0:2] = '{'{1,0,-1}, '{2,0,-2}, '{1,0,-1}};
        logic signed [21:0] conv_relu_map [0:CONV_OUT_SIZE-1][0:CONV_OUT_SIZE-1];
        int pool_idx = 0;

        // --- 1. Convolution + ReLU 단계 ---
        for (int y = 0; y < CONV_OUT_SIZE; y++) begin
            for (int x = 0; x < CONV_OUT_SIZE; x++) begin
                logic signed [21:0] mac_sum = 0;
                // 3x3 MAC 연산
                for (int ky = 0; ky < 3; ky++) begin
                    for (int kx = 0; kx < 3; kx++) begin
                        mac_sum += image[y+ky][x+kx] * kernel[ky][kx];
                    end
                end
                // ReLU 적용
                conv_relu_map[y][x] = (mac_sum < 0) ? 0 : mac_sum;
            end
        end

        // --- 2. Max Pooling 단계 ---
        for (int y = 0; y < POOL_OUT_SIZE; y++) begin
            for (int x = 0; x < POOL_OUT_SIZE; x++) begin
                int map_y = y * 2;
                int map_x = x * 2;
                logic signed [21:0] max_val = -1; // 최댓값 초기화
                
                // 2x2 윈도우에서 최댓값 찾기
                for (int py = 0; py < 2; py++) begin
                    for (int px = 0; px < 2; px++) begin
                        if (conv_relu_map[map_y+py][map_x+px] > max_val) begin
                            max_val = conv_relu_map[map_y+py][map_x+px];
                        end
                    end
                end
                result[pool_idx++] = max_val;
            end
        end
    endfunction
    
    // =================================================================
    // == 4. 테스트 절차를 위한 Task
    // =================================================================
    
    // DUT 리셋 Task
    task apply_reset;
        rst = 1;
        start_signal = 0;
        pixel_valid_in = 0;
        pixel_in = 0;
        #20;
        rst = 0;
    endtask

    // 이미지 데이터 주입 Task
    task drive_image;
        start_signal = 1;
        @(posedge clk);
        start_signal = 0;
        
        for (int y = 0; y < IMG_HEIGHT; y++) begin
            for (int x = 0; x < IMG_WIDTH; x++) begin
                pixel_valid_in = 1;
                pixel_in = input_image[y][x];
                @(posedge clk);
            end
        end
        pixel_valid_in = 0;
    endtask

    // DUT 결과 수집 Task
    task collect_results;
        result_count = 0;
        while (!final_done_signal) begin
            if (final_result_valid) begin
                if (result_count < EXPECTED_OUTPUT_COUNT) begin
                    dut_results[result_count] = final_result_out;
                    result_count++;
                end
            end
            @(posedge clk);
        end
    endtask

    // =================================================================
    // == 5. 메인 테스트 시나리오
    // =================================================================
    initial begin
        $display("=== Feature Extractor Self-Checking Test START ===");

        // 1. 테스트용 입력 이미지 생성
        for (int y = 0; y < IMG_HEIGHT; y++) begin
            for (int x = 0; x < IMG_WIDTH; x++) begin
                // XOR 패턴 이미지 생성
                input_image[y][x] = 8'(100 + (x^y));
            end
        end

        // 2. 골든 모델을 통해 '정답' 미리 계산
        golden_model_feature_extractor(input_image, expected_results);

        // 3. 테스트 실행
        apply_reset();
        drive_image();
        collect_results();

        // 4. 결과 자동 비교
        #10; // 최종 신호 안정화를 위해 잠시 대기
        $display("\n=== FINAL ANALYSIS ===");
        if (result_count != EXPECTED_OUTPUT_COUNT) begin
            $display("✗ TEST FAILED: Result count mismatch! Expected %0d, Got %0d", EXPECTED_OUTPUT_COUNT, result_count);
        
        end else begin
            for (int i = 0; i < EXPECTED_OUTPUT_COUNT; i++) begin
                if (dut_results[i] !== expected_results[i]) begin
                    $display("✗ MISMATCH at Result[%0d]: DUT = %0d, Expected = %0d", i, dut_results[i], expected_results[i]);
                    error_count++;
                end
            end
            
            if (error_count == 0) begin
                $display("✓ TEST PASSED: All %0d results match the golden model.", EXPECTED_OUTPUT_COUNT);
            else
                $display("✗ TEST FAILED: Found %0d mismatches.", error_count);
            end
        end

        $display("=== TEST COMPLETE ===");
        $finish;
    end

endmodule