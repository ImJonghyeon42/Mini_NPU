`timescale 1ns/1ps
// ===================================================================================
//  Module: CNN_TOP_tb_advanced
//  Author: FPGA Debugging Master (for the Client)
//  Description:
//    - 'CNN_TOP' 모듈을 위한 지능형 시나리오 기반 테스트벤치입니다.
//    - 라즈베리 파이의 동작을 모방하여 이미지 데이터를 주입하고,
//    - C/Python 모델의 결과를 모방한 Golden Reference와 자동으로 비교하여
//    - PASS/FAIL을 판정하는 '감독관' 역할을 수행합니다.
// ===================================================================================
module CNN_TOP_tb_advanced;

    // =================================================================
    // 1. DUT(Design Under Test) 신호 선언
    // =================================================================
    logic clk;
    logic rst;
    logic start_signal;
    logic pixel_valid;
    logic [7:0] pixel_in;
    logic final_result_valid;
    logic signed [47:0] final_lane_result;

    // --- DUT 인스턴스 ---
    // dut 라는 이름으로 CNN_TOP 모듈을 불러옵니다.
    // .*(.*) 문법은 이름이 같은 포트를 자동으로 연결해줍니다.
    CNN_TOP dut (.*);


    // =================================================================
    // 2. 시뮬레이션 환경 설정
    // =================================================================
    // --- 클럭 생성 (100MHz, 10ns 주기) ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 5ns 마다 클럭 반전
    end

    // --- 테스트 데이터 및 Golden Reference 메모리 ---
    localparam IMG_WIDTH  = 32;
    localparam IMG_HEIGHT = 32;
    localparam IMG_SIZE   = IMG_WIDTH * IMG_HEIGHT; // 1024

    // 테스트 이미지 픽셀(1024개)을 저장할 메모리
    logic [7:0] image_mem [0:IMG_SIZE-1];
    // '정답' 결과를 저장할 변수
    logic signed [47:0] golden_result;


    // =================================================================
    // 3. [핵심] 시나리오 실행 태스크 (Task)
    // =================================================================
    task run_scenario(string image_file, string golden_file);
    integer file_handle;
    begin
        $display("\n//--------------------------------------------------------------//");
        $display("--- [SCENARIO START] Image: %s ---", image_file);

        // --- 파일로부터 이미지와 Golden 데이터 로드 ---
       $readmemh(image_file, image_mem);

    // [수정] 여기서는 선언 없이 값만 할당합니다.
    file_handle = $fopen(golden_file, "r"); 
    if (file_handle) begin
        // golden 파일에서 10진수 형태의 정답 값을 읽어옴
        void'($fscanf(file_handle, "%d", golden_result));
        $fclose(file_handle);
        $display("Golden Result Loaded: %0d", golden_result);
    end else begin
        $error("FATAL: Golden file not found -> %s", golden_file);
        $finish;
    end

        // --- 1. 리셋 및 초기화 ---
        rst = 1;
        start_signal = 0;
        pixel_valid  = 0;
        pixel_in     = 0;
        repeat(10) @(posedge clk);
        rst = 0;
        $display("Reset sequence complete.");

        // --- 2. 시작 신호 (start_signal) 펄스 ---
        @(posedge clk);
        start_signal = 1;
        @(posedge clk);
        start_signal = 0;
        $display("Start signal pulsed. Injecting image data...");

        // --- 3. 이미지 데이터 주입 (32x32 = 1024 픽셀) ---
        for (int i = 0; i < IMG_SIZE; i++) begin
            @(posedge clk);
            pixel_valid = 1;
            pixel_in = image_mem[i];
        end
        @(posedge clk);
        pixel_valid = 0;
        $display("Image data injection complete. Waiting for DUT to finish...");

        // --- 4. 최종 결과가 나올 때까지 대기 (Timeout 추가) ---
        fork
            begin
                wait (final_result_valid == 1);
            end
            begin
                // 무한정 기다리는 것을 방지하기 위한 Timeout 설정 (50000 클럭)
                repeat(50000) @(posedge clk);
                $error("TIMEOUT: final_result_valid was not asserted!");
                $finish;
            end
        join_any
        disable fork; // 둘 중 하나가 완료되면 다른 하나는 종료

        @(posedge clk); // 안정적인 결과 캡처를 위해 1클럭 대기

        // --- 5. 결과 자동 비교 및 판정 ---
        if (final_lane_result === golden_result) begin
            $display("    >> DUT Result: %0d", final_lane_result);
            $display("    >> Expected:   %0d", golden_result);
            $display("    >> [VERDICT] ? SCENARIO PASSED!");
        end else begin
            $display("    >> DUT Result: %0d (%h)", final_lane_result, final_lane_result);
            $display("    >> Expected:   %0d (%h)", golden_result, golden_result);
            $display("    >> [VERDICT] ? SCENARIO FAILED!");
        end
        $display("//--------------------------------------------------------------//\n");
    end
    endtask


    // =================================================================
    // 4. 메인 테스트 시퀀스
    // =================================================================
    initial begin
        // 시뮬레이션 시작 메시지
        $display("===============================================================");
        $display("=== CNN Hardware Accelerator Advanced Testbench START ===");
        $display("===============================================================");
        #100; // 초기 안정화 시간

        // --- [1단계] 기초 기능 검증 시나리오 ---
        run_scenario("vertical_edge.hex", "golden_vertical_edge.txt");
        #2000; // 다음 시나리오 전 충분한 시간 확보

        // 여기에 수평선, 대각선 등 다른 1단계 시나리오를 추가할 수 있습니다.
        // run_scenario("horizontal_edge.hex", "golden_horizontal_edge.txt");
        // #2000;

        // --- [2단계] 실제 주행 데이터 검증 시나리오 (준비되면 주석 해제) ---
        // run_scenario("real_straight.hex", "golden_real_straight.txt");
        // #2000;
        // run_scenario("real_curve.hex", "golden_real_curve.txt");
        // #2000;


        $display("=== All scenarios completed. ===");
        $finish;
    end

    // =================================================================
    // 5. 파형(Waveform) 저장을 위한 설정
    // =================================================================
    initial begin
        // vcd (Value Change Dump) 파일 이름 설정
        $dumpfile("cnn_top_advanced_tb.vcd");
        // 0: 모든 레벨의 신호를, tb 모듈을 기준으로 덤프
        $dumpvars(0, CNN_TOP_tb_advanced);
    end

endmodule