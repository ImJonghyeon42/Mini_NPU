
`timescale 1ns/1ps

module RELU_POOL_TOP_tb;

    // DUT 신호 선언
    logic clk = 0;
    logic rst;
    logic start_signal;
    logic pixel_valid;
    logic signed [21:0] pixel_in;
    logic signed [21:0] result_out;
    logic             result_valid;
    logic             done_signal;
    
    logic signed [21:0] val1 ; 
logic signed [21:0] val2 ; 
logic signed [21:0] val3 ; 
logic signed [21:0] val4 ;
logic signed [21:0] max_val;
    

    // 테스트벤치 내부 변수
    localparam IMG_WIDTH  = 32;
    localparam IMG_HEIGHT = 32;
    localparam POOL_OUT_WIDTH = IMG_WIDTH / 2;
    localparam POOL_OUT_HEIGHT = IMG_HEIGHT / 2;

    logic signed [21:0] input_image[0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    logic signed [21:0] expected_results[0:POOL_OUT_HEIGHT-1][0:POOL_OUT_WIDTH-1];
    logic signed [21:0] actual_results[0:POOL_OUT_HEIGHT-1][0:POOL_OUT_WIDTH-1];
    
    integer result_row = 0;
    integer result_col = 0;
    integer error_count = 0;

    // DUT 인스턴스
    RELU_POOL_TOP UUT (.*);

    // 클럭 생성
    always #5 clk = ~clk;

    // 테스트 패턴 생성 태스크
    task generate_test_pattern;
        $display("[TB] Generating test pattern...");
        for (int y = 0; y < IMG_HEIGHT; y++) begin
            for (int x = 0; x < IMG_WIDTH; x++) begin
                // 2x2 블록마다 다른 값을 가지는 패턴 생성
                // {10, -5}, {-20, 8} 패턴 반복
                case ({y%2, x%2})
                    2'b00: input_image[y][x] = 10;
                    2'b01: input_image[y][x] = -5;
                    2'b10: input_image[y][x] = -20;
                    2'b11: input_image[y][x] = 8;
                endcase
            end
        end
    endtask

    // 예상 결과 계산 태스크
    task calculate_expected_results;
        logic signed [21:0] relu_image[0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
        $display("[TB] Calculating expected results...");

        // 1. ReLU 적용
        for (int y = 0; y < IMG_HEIGHT; y++) begin
            for (int x = 0; x < IMG_WIDTH; x++) begin
                relu_image[y][x] = (input_image[y][x][21] == 1'b1) ? '0 : input_image[y][x];
            end
        end

        // 2. 2x2 Max Pooling 적용
        for (int y = 0; y < POOL_OUT_HEIGHT; y++) begin
            for (int x = 0; x < POOL_OUT_WIDTH; x++) begin
                val1 = relu_image[y*2][x*2];
                val2 = relu_image[y*2][x*2+1];
                val3 = relu_image[y*2+1][x*2];
                val4 = relu_image[y*2+1][x*2+1];
                max_val = val1;
                if (val2 > max_val) max_val = val2;
                if (val3 > max_val) max_val = val3;
                if (val4 > max_val) max_val = val4;
                expected_results[y][x] = max_val;
            end
        end
        // 예시: 첫번째 2x2 블록
        // 입력: {10, -5}, {-20, 8}
        // ReLU 후: {10, 0}, {0, 8}
        // Max Pooling 후: 10
        $display("[TB] Expected result for [0][0] is %d", expected_results[0][0]);
    endtask

    // DUT 출력 결과 수집
    always @(posedge clk) begin
        if (result_valid) begin
            if (result_row < POOL_OUT_HEIGHT && result_col < POOL_OUT_WIDTH) begin
                actual_results[result_row][result_col] = result_out;
                result_col++;
                if (result_col >= POOL_OUT_WIDTH) begin
                    result_col = 0;
                    result_row++;
                end
            end
        end
    end

    // 메인 테스트 시퀀스
    initial begin
        $display("=== RELU + Max Pooling Test Start ===");
        
        // 1. 테스트 준비
        generate_test_pattern();
        calculate_expected_results();

        // 2. DUT 초기화
        rst = 1;
        start_signal = 0;
        pixel_valid = 0;
        pixel_in = '0;
        #20;
        rst = 0;
        #10;

        // 3. 테스트 시작 및 데이터 입력
        $display("[TB] Asserting start_signal...");
        @(posedge clk);
        start_signal = 1;
        @(posedge clk);
        start_signal = 0;
        
        $display("[TB] Streaming input image data (%0d pixels)...", IMG_WIDTH * IMG_HEIGHT);
        for (int y = 0; y < IMG_HEIGHT; y++) begin
            for (int x = 0; x < IMG_WIDTH; x++) begin
                @(posedge clk);
                pixel_valid = 1;
                pixel_in = input_image[y][x];
            end
        end
        
        @(posedge clk);
        pixel_valid = 0;
        pixel_in = '0;
        $display("[TB] All pixels sent. Waiting for done_signal...");

        // 4. DUT 처리 완료 대기
        wait (done_signal == 1);
        $display("[TB] done_signal received.");
        #100; // 파이프라인의 남은 데이터가 모두 처리될 때까지 충분히 대기

        // 5. 결과 검증
        $display("[TB] Verifying results...");
        error_count = 0;
        for (int y = 0; y < POOL_OUT_HEIGHT; y++) begin
            for (int x = 0; x < POOL_OUT_WIDTH; x++) begin
                if (actual_results[y][x] !== expected_results[y][x]) begin
                    $display("ERROR at [%2d][%2d]: Expected=%d, Actual=%d", y, x, expected_results[y][x], actual_results[y][x]);
                    error_count++;
                end
            end
        end

        if (error_count == 0) begin
            $display("✅✅✅ TEST PASSED! ✅✅✅");
        end else begin
            $display("❌❌❌ TEST FAILED with %0d errors. ❌❌❌", error_count);
        end

        $display("=== Test Finished ===");
        $finish; 

    end
endmodule