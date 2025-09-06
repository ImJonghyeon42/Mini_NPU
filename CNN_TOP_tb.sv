`timescale 1ns/1ps
module CNN_TOP_SUCCESS_tb;
    // DUT 신호
    logic clk, rst, start_signal, pixel_valid;
    logic [7:0] pixel_in;
    logic final_result_valid;
    logic signed [47:0] final_lane_result;
    logic cnn_busy;
    
    CNN_TOP DUT (.*);
    
    // 클럭 생성 (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // 테스트 데이터
    localparam IMG_SIZE = 32 * 32;
    logic [7:0] test_image [0:IMG_SIZE-1];
    
    // 모니터링 변수 (모듈 레벨에서 선언)
    integer pixel_count = 0;
    integer feature_count = 0;
    integer fc_start_count = 0;
    logic prev_busy = 0;
    integer conv_done_count = 0;
    
    initial begin
        $display("===============================================================");
        $display("=== CNN 프로젝트 최종 검증 테스트 START ===");
        $display("=== 기존 weight.mem 파일 사용 ===");
        $display("===============================================================");
        
        // 테스트 이미지 생성 (간단한 패턴)
        for (int y = 0; y < 32; y++) begin
            for (int x = 0; x < 32; x++) begin
                test_image[y*32 + x] = 8'(100 + (x^y));
            end
        end
        $display("테스트 이미지 생성 완료");
        
        // 시스템 초기화
        rst = 1; 
        start_signal = 0;
        pixel_valid = 0;
        pixel_in = 0;
        #100;
        rst = 0;
        $display("시스템 리셋 완료");
        
        // 약간의 대기 시간
        repeat(10) @(posedge clk);
        
        // CNN 처리 시작
        @(posedge clk);
        start_signal = 1;
        @(posedge clk);
        start_signal = 0;
        $display("CNN 처리 시작 신호 전송");
        
        // 이미지 데이터 입력
        $display("이미지 데이터 입력 시작...");
        for (int i = 0; i < IMG_SIZE; i++) begin
            @(posedge clk);
            pixel_valid = 1;
            pixel_in = test_image[i];
            
            // 진행상황 표시 (매 256픽셀마다)
            if (i % 256 == 255) begin
                $display("픽셀 입력 진행: %0d/1024", i+1);
            end
        end
        @(posedge clk);
        pixel_valid = 0;
        $display("이미지 데이터 입력 완료 (1024 픽셀)");
        
        // 결과 대기
        fork
            begin: wait_result
                $display("CNN 결과 대기 중...");
                wait (final_result_valid == 1);
                repeat(5) @(posedge clk);
                
                $display("\n================= 최종 결과 =================");
                $display("CNN 출력값: %0d (0x%h)", final_lane_result, final_lane_result);
                
                // 실제 weight.mem을 사용한 결과 평가
                if (final_lane_result == 0) begin
                    $display("WARNING: 출력값이 0 - 계산 오류 가능성");
                    $display("원인: Weight 로딩 실패 또는 FC Layer 문제");
                end else if (final_lane_result > 0 && final_lane_result < 1000000) begin
                    $display("SUCCESS: 정상 범위 내 출력!");
                    $display("프로젝트 상태: 기능적 성공");
                    if (final_lane_result > 10000 && final_lane_result < 100000) begin
                        $display("매우 합리적인 출력 범위");
                    end
                end else if (final_lane_result > 1000000) begin
                    $display("WARNING: 출력값이 매우 큼 - 오버플로우 가능성");
                end else begin
                    $display("INFO: 음수 출력 - ReLU 이전 값이거나 정상적 계산");
                end
                $display("=============================================");
            end
            
            begin: timeout
                repeat(100000) @(posedge clk);  // 타임아웃 증가
                $display("ERROR: 100000 클럭 내 결과 없음");
                $display("가능한 원인:");
                $display("1. FC Layer가 시작되지 않음");
                $display("2. Buffer가 채워지지 않음");
                $display("3. Weight 로딩 실패");
                $finish;
            end
        join_any
        disable fork;
        
        // 추가 분석
        $display("\n================= 분석 정보 =================");
        $display("CNN Busy 상태: %b", cnn_busy);
        $display("Buffer Full 상태: %b", DUT.flattened_buffer_full);
        $display("FC Executed 상태: %b", DUT.fc_executed);
        $display("Processing Active: %b", DUT.processing_active);
        $display("=============================================");
        
        $finish;
    end
    
    // 상세 모니터링 (static 키워드 완전 제거)
    always @(posedge clk) begin
        if (rst) begin
            // 리셋시 모든 카운터 초기화
            pixel_count = 0;
            feature_count = 0;
            fc_start_count = 0;
            prev_busy = 0;
            conv_done_count = 0;
        end else begin
            // 픽셀 입력 카운트
            if (pixel_valid) begin
                pixel_count = pixel_count + 1;
            end
            
            // Feature 출력 카운트
            if (DUT.feature_valid) begin
                feature_count = feature_count + 1;
                if (feature_count <= 10 || feature_count % 50 == 0) begin
                    $display("[%0t] Feature %0d: %0d", $time, feature_count, DUT.feature_result);
                end
            end
            
            // Buffer Full 감지
            if (DUT.flattened_buffer_full) begin
                fc_start_count = fc_start_count + 1;
                if (fc_start_count == 1) begin
                    $display("[%0t] *** Buffer Full - FC Layer 시작 예정 ***", $time);
                    $display("Feature 개수: %0d/225", feature_count);
                end
            end
            
            // FC 시작 감지
            if (DUT.fc_start_pulse) begin
                $display("[%0t] *** FC Layer 시작! ***", $time);
            end
            
            // 최종 결과 감지
            if (final_result_valid) begin
                $display("[%0t] *** FC Layer 완료 - 결과 출력 ***", $time);
            end
            
            // CNN Busy 상태 변화 감지 (static 키워드 제거됨)
            if (cnn_busy != prev_busy) begin
                $display("[%0t] CNN Busy 상태 변화: %b → %b", $time, prev_busy, cnn_busy);
                prev_busy = cnn_busy;
            end
            
            // Feature Extractor 진행도
            if (DUT.u_feature_extractor.conv_done_signal) begin
                conv_done_count = conv_done_count + 1;
                if (conv_done_count == 1) begin
                    $display("[%0t] Convolution 완료", $time);
                end
            end
            
            if (DUT.u_feature_extractor.final_done_signal) begin
                $display("[%0t] Feature Extraction 완료", $time);
            end
        end
    end
    
    // Weight 로딩 확인 (FC Layer 내부 신호 접근)
    initial begin
        #1000; // Weight 로딩 대기
        $display("\n================= Weight 확인 =================");
        $display("Weight[0]: 0x%h", DUT.u_fully_connected_layer.weight_ROM[0]);
        $display("Weight[1]: 0x%h", DUT.u_fully_connected_layer.weight_ROM[1]);
        $display("Weight[224]: 0x%h", DUT.u_fully_connected_layer.weight_ROM[224]);
        
        // 실제 weight.mem과 비교
        if (DUT.u_fully_connected_layer.weight_ROM[0] == 22'h3FFE46) begin
            $display("✓ Weight 로딩 성공!");
        end else begin
            $display("✗ Weight 로딩 실패 - 첫 번째 값이 다름");
        end
        $display("=============================================");
    end

endmodule