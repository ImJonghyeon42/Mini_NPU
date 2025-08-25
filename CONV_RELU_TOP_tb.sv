`timescale 1ns/1ps
module CONV_RELU_TOP_tb;
    
    // DUT 신호 선언
    logic clk = 0, rst, start_signal, pixel_valid;
    logic [7:0] pixel_in;
    logic signed [21:0] result_out;
    logic result_valid, done_signal;
    
    // 테스트벤치 내부 변수
    logic [7:0] input_image [0:31][0:31];
    logic signed [21:0] expected_result [0:29][0:29];
    logic signed [21:0] actual_results [0:29][0:29];
    
    integer error_count;
    integer result_row, result_col;
    integer pixel_count, result_count;
    
    // DUT 인스턴스
    CONV_RELU_TOP U0 (.*);
    
    // 클럭 생성
    always #5 clk = ~clk;
    
    // 결과 수집
    always @(posedge clk) begin
        if (result_valid) begin
            if (result_row < 30 && result_col < 30) begin
                actual_results[result_row][result_col] = result_out;
            end
            
            result_col++;
            if (result_col >= 30) begin
                result_col = 0;
                result_row++;
            end
            result_count++;
        end
    end
    
    // 수직 에지 패턴 생성 태스크
    task generate_vertical_edge;
        begin
            $display("수직 에지 패턴 생성 중...");
            for (int y = 0; y < 32; y++) begin
                for (int x = 0; x < 32; x++) begin
                    if (x < 16)
                        input_image[y][x] = 8'd0;
                    else
                        input_image[y][x] = 8'd255;
                end
            end
        end
    endtask

	
    // 예상 결과 계산 태스크
    task calculate_expected_vertical_edge;
		logic signed [21:0] temp_result;
		int signed_window [0:2][0:2];
        begin
        $display("수직 에지 예상 결과 계산 중...");
        for (int y = 1; y < 31; y++) begin
            for (int x = 1; x < 31; x++) begin

                // 2. unsigned 픽셀 값을 signed int 윈도우로 먼저 복사 (명시적 타입 변환)
                for (int i = 0; i < 3; i++) begin
                    for (int j = 0; j < 3; j++) begin
                        signed_window[i][j] = input_image[y-1+i][x-1+j];
                    end
                end

                // 3. 이제 깨끗하게 통일된 signed_window로만 계산!
                temp_result = 
                    (1 * signed_window[0][0]) + (0 * signed_window[0][1]) + (-1 * signed_window[0][2]) +
                    (2 * signed_window[1][0]) + (0 * signed_window[1][1]) + (-2 * signed_window[1][2]) +
                    (1 * signed_window[2][0]) + (0 * signed_window[2][1]) + (-1 * signed_window[2][2]);

                // 디버깅 코드 
                if (y-1 == 0 && x-1 == 14) begin
                    $display("... DEBUG after fix: temp_result = %d ...", temp_result);
                end

                if(temp_result < 0) begin
                    expected_result[y-1][x-1] = 0;
                end else begin
                    expected_result[y-1][x-1] = temp_result;
                end
            end
        end
    end
endtask
    
    // 체크보드 패턴 생성 태스크
    task generate_checkerboard;
        begin
            $display("체크보드 패턴 생성 중...");
            for (int y = 0; y < 32; y++) begin
                for (int x = 0; x < 32; x++) begin
                    if ((x + y) % 2 == 0)
                        input_image[y][x] = 8'd255;
                    else
                        input_image[y][x] = 8'd0;
                end
            end
        end
    endtask
    
    // 체크보드 예상 결과 계산
    task calculate_expected_checkerboard;
    logic signed [21:0] temp_result; // 임시 변수 추가
	int signed_window [0:2][0:2];
    begin
        $display("체크보드 예상 결과 계산 중...");
        for (int y = 1; y < 31; y++) begin
            for (int x = 1; x < 31; x++) begin

                // 2. unsigned 픽셀 값을 signed int 윈도우로 먼저 복사 (명시적 타입 변환)
                for (int i = 0; i < 3; i++) begin
                    for (int j = 0; j < 3; j++) begin
                        signed_window[i][j] = input_image[y-1+i][x-1+j];
                    end
                end

                // 3. 이제 깨끗하게 통일된 signed_window로만 계산!
                temp_result = 
                    (1 * signed_window[0][0]) + (0 * signed_window[0][1]) + (-1 * signed_window[0][2]) +
                    (2 * signed_window[1][0]) + (0 * signed_window[1][1]) + (-2 * signed_window[1][2]) +
                    (1 * signed_window[2][0]) + (0 * signed_window[2][1]) + (-1 * signed_window[2][2]);

                // 디버깅 코드 
                if (y-1 == 0 && x-1 == 14) begin
                    $display("... DEBUG after fix: temp_result = %d ...", temp_result);
                end

                if(temp_result < 0) begin
                    expected_result[y-1][x-1] = 0;
                end else begin
                    expected_result[y-1][x-1] = temp_result;
                end
            end
        end
    end
endtask
    
    // 테스트 실행 태스크
    task run_test(string test_name);
        begin
            $display("\n=== %s 테스트 시작 ===", test_name);
            
            // BUG FIX: 테스트 패턴에 맞는 예상 결과를 '실행 직전'에 계산
            if (test_name == "수직 에지") begin
                generate_vertical_edge();
                calculate_expected_vertical_edge();
            end else if (test_name == "체크보드") begin
                generate_checkerboard();
                calculate_expected_checkerboard();
            end

            // 초기화
            error_count = 0;
            result_row = 0;
            result_col = 0;
            pixel_count = 0;
            result_count = 0;
            // Good practice: Clear the actual results array before each run
            for (int y = 0; y < 30; y++) begin
                for (int x = 0; x < 30; x++) begin
                    actual_results[y][x] = 'x;
                end
            end
            
            // 리셋
            rst = 1;
            #20;
            rst = 0;
            #10;
            
            // 시작 신호
            @(posedge clk);
            start_signal = 1;
            @(posedge clk);
            start_signal = 0;
            
            // 데이터 입력
            for (int y = 0; y < 32; y++) begin
                for (int x = 0; x < 32; x++) begin
                    @(posedge clk);
                    pixel_valid = 1;
                    pixel_in = input_image[y][x];
                    pixel_count++;
                end
            end
            
            @(posedge clk);
            pixel_valid = 0;
            
            $display("모든 픽셀 입력 완료. done 신호 및 파이프라인 flush 대기 중...");
            wait (result_count == 900);//wait (done_signal == 1);
			@(posedge clk);
            // BUG FIX: Wait for the pipeline to be fully flushed.
            #100; // Wait 10 clock cycles
            
            // 결과 검증
            $display("결과 검증 중...");
            for (int y = 0; y < 30; y++) begin
                for (int x = 0; x < 30; x++) begin
                    if (actual_results[y][x] !== expected_result[y][x]) begin
                        if (error_count < 10) begin
                            $display("❌ 오류 [%2d,%2d]: 예상=%d, 실제=%d", y, x, expected_result[y][x], actual_results[y][x]);
                        end
                        error_count++;
                    end
                end
            end
            
            if (error_count == 0) begin
                $display("✅ 테스트 통과!");
            end else begin
                $display("❌ %d개 오류 발생", error_count);
            end
            
            $display("=== %s 테스트 완료 ===\n", test_name);
        end
    endtask
    
    // 메인 테스트 시퀀스
    initial begin
        $display("=== 2D 컨볼루션 엔진 테스트 시작 ===");
        
        // 초기화
        rst = 1;
        start_signal = 0;
        pixel_valid = 0;
        pixel_in = '0;
        #20;
        
        // 테스트 1: 수직 에지
        run_test("수직 에지");
        #100;
        
        // 테스트 2: 체크보드
        run_test("체크보드");
        #100;
        
        $display("=== 모든 테스트 완료 ===");
        $finish;
    end
    
endmodule
