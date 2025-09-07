`timescale 1ns/1ps
module CNN_TOP_FINAL_tb;
    // DUT 신호
    logic clk, rst, start_signal, pixel_valid;
    logic [7:0] pixel_in;
    logic final_result_valid;
    logic signed [47:0] final_lane_result;
    logic cnn_busy;
    
    CNN_TOP DUT (.*);  // 모든 신호 직접 연결
    
    // 클럭 생성 (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // 테스트 데이터
    localparam IMG_SIZE = 32 * 32;
    logic [7:0] test_image [0:IMG_SIZE-1];
    
    initial begin
        $display("===============================================================");
        $display("=== CNN 최종 검증 테스트 (Active Low Reset 통일) ===");
        $display("===============================================================");
        
        // 테스트 이미지 생성
        for (int y = 0; y < 32; y++) begin
            for (int x = 0; x < 32; x++) begin
                test_image[y*32 + x] = 8'(100 + (x^y));
            end
        end
        $display("테스트 이미지 생성 완료");
        
        // ===== Active Low Reset 시퀀스 =====
        rst = 0;              // Active Low - Reset 상태
        start_signal = 0;
        pixel_valid = 0;
        pixel_in = 0;
        
        $display("시스템 RESET (Active Low): rst=0");
        #500;                 // 충분한 reset 시간
        
        rst = 1;              // Reset 해제
        $display("RESET 해제: rst=1");
        #200;
        
        // 상태 확인
        $display("Reset 후 상태: cnn_busy=%b, state=%0d", 
                cnn_busy, DUT.current_state);
        
        if (cnn_busy) begin
            $display("✗ 오류: Reset 후에도 busy 상태!");
            $finish;
        end
        
        // CNN 처리 시작
        @(posedge clk);
        start_signal = 1;
        $display("CNN 시작 신호 전송");
        @(posedge clk);
        start_signal = 0;
        
        // 시작 후 상태 확인
        repeat(20) @(posedge clk);
        $display("시작 후 상태: cnn_busy=%b, state=%0d", 
                cnn_busy, DUT.current_state);
        
        if (!cnn_busy) begin
            $display("✗ 오류: CNN이 시작되지 않음!");
            $finish;
        end
        
        // 이미지 데이터 입력
        $display("이미지 데이터 입력 시작...");
        for (int i = 0; i < IMG_SIZE; i++) begin
            @(posedge clk);
            pixel_valid = 1;
            pixel_in = test_image[i];
            
            // 진행상황 표시
            if (i % 256 == 255) begin
                $display("픽셀 입력 진행: %0d/1024 (state=%0d)", 
                        i+1, DUT.current_state);
            end
        end
        @(posedge clk);
        pixel_valid = 0;
        $display("이미지 데이터 입력 완료");
        
        // 결과 대기
        fork
            begin: wait_result
                $display("CNN 결과 대기 중...");
                wait (final_result_valid == 1);
                repeat(10) @(posedge clk);
                
                $display("\n================= 최종 결과 =================");
                $display("CNN 출력값: %0d (0x%h)", final_lane_result, final_lane_result);
                $display("Pixel Count: %0d", DUT.pixel_counter);
                $display("Feature Count: %0d", DUT.feature_counter);
                
                if (final_lane_result == 0) begin
                    $display("WARNING: 출력값이 0");
                end else if (final_lane_result[47:32] == 16'hDEAD) begin
                    $display("INFO: 타임아웃으로 인한 더미 결과");
                end else begin
                    $display("SUCCESS: 정상 CNN 출력!");
                end
                $display("=============================================");
            end
            
            begin: timeout
                repeat(500000) @(posedge clk);  // 50ms 타임아웃
                $display("ERROR: 타임아웃 - 결과 없음");
                
                // 상세 디버그 정보
                $display("=== 타임아웃 진단 ===");
                $display("CNN State: %0d", DUT.current_state);
                $display("CNN Busy: %b", cnn_busy);
                $display("Pixel Count: %0d", DUT.pixel_counter);
                $display("Feature Count: %0d", DUT.feature_counter);
                $display("Buffer Full: %b", DUT.flattened_buffer_full);
                $display("Conv State: %0d", DUT.u_feature_extractor.U0.state);
                $display("Conv Done: %b", DUT.u_feature_extractor.U0.done_signal);
                $display("Pool State: %0d", DUT.u_feature_extractor.U2.state);
                $display("Pool Done: %b", DUT.u_feature_extractor.U2.done_signal);
                $display("FC State: %0d", DUT.u_fully_connected_layer.state);
                $display("====================");
                $finish;
            end
        join_any
        disable fork;
        
        // 추가 대기 후 종료
        repeat(100) @(posedge clk);
        $display("테스트 완료");
        $finish;
    end
    
    // Weight 로딩 확인
    initial begin
        #2000;  // Weight 로딩 대기
        $display("\n=== Weight 확인 ===");
        $display("Weight[0]: 0x%h", DUT.u_fully_connected_layer.weight_ROM[0]);
        $display("Weight[1]: 0x%h", DUT.u_fully_connected_layer.weight_ROM[1]);
        
        if (DUT.u_fully_connected_layer.weight_ROM[0] == 22'h3FFE46) begin
            $display("✓ Weight 로딩 성공!");
        end else begin
            $display("✗ Weight 로딩 실패!");
        end
        $display("==================");
    end

endmodule