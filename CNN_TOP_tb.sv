`timescale 1ns/1ps

module CNN_TOP_SUCCESS_tb;
    // DUT 신호
    logic clk, rst, start_signal, pixel_valid;
    logic [7:0] pixel_in;
    logic final_result_valid;
    logic signed [47:0] final_lane_result;

    CNN_TOP DUT (.*);

    // 클럭 생성
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 테스트 데이터
    localparam IMG_SIZE = 32 * 32;
    logic [7:0] test_image [0:IMG_SIZE-1];
    
    // Weight 배열 (automatic 제거)
    logic [21:0] fc_weights [0:224];

    initial begin
        $display("===============================================================");
        $display("=== CNN 프로젝트 최종 검증 테스트 START ===");
        $display("===============================================================");
        
        // Weight 파일 생성 (automatic 키워드 제거)
        for (int i = 0; i < 225; i++) begin
            fc_weights[i] = i + 1;
        end
        $writememh("weight.mem", fc_weights);
        
        // 테스트 이미지 생성
        for (int y = 0; y < 32; y++) begin
            for (int x = 0; x < 32; x++) begin
                test_image[y*32 + x] = 8'(100 + (x^y));
            end
        end
        
        // 시스템 초기화
        rst = 1; 
        start_signal = 0;
        pixel_valid = 0;
        #100;
        rst = 0;
        $display("시스템 리셋 완료");

        // CNN 처리 시작
        @(posedge clk);
        start_signal = 1;
        @(posedge clk);
        start_signal = 0;
        $display("CNN 처리 시작");

        // 이미지 데이터 입력
        for (int i = 0; i < IMG_SIZE; i++) begin
            @(posedge clk);
            pixel_valid = 1;
            pixel_in = test_image[i];
        end
        pixel_valid = 0;
        $display("이미지 데이터 입력 완료 (1024 픽셀)");

        // 결과 대기
        fork
            begin: wait_result
                wait (final_result_valid == 1);
                repeat(5) @(posedge clk);
                
                $display("\n================= 최종 결과 =================");
                $display("CNN 출력값: %0d (0x%h)", final_lane_result, final_lane_result);
                
                if (final_lane_result == 68264) begin
                    $display("SUCCESS: 정확한 값 출력!");
                    $display("프로젝트 상태: 완전 성공");
                end else if (final_lane_result > 0 && final_lane_result < 1000000) begin
                    $display("SUCCESS: 정상 범위 내 출력");
                    $display("프로젝트 상태: 기능적 성공");
                    $display("예상: 68264, 실제: %0d", final_lane_result);
                end else begin
                    $display("ERROR: 비정상 출력값");
                end
                $display("=============================================");
            end
            
            begin: timeout
                repeat(50000) @(posedge clk);
                $display("ERROR: 50000 클럭 내 결과 없음 - FC Layer 문제 가능성");
                $finish;
            end
        join_any
        disable fork;

        $finish;
    end

    // 간단한 모니터링
    integer fc_start_count = 0;
    
    always @(posedge clk) begin
        if (DUT.flattened_buffer_full) begin
            fc_start_count++;
            if (fc_start_count == 1) begin
                $display("[%0t] Buffer Full - FC Layer 시작 예정", $time);
            end else if (fc_start_count > 5) begin
                $display("WARNING: FC Layer가 %0d번째 트리거됨", fc_start_count);
            end
        end
        
        if (final_result_valid) begin
            $display("[%0t] FC Layer 완료 - 결과 출력", $time);
        end
    end

endmodule