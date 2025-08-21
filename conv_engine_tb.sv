`timescale 1ns/1ps
module conv_engine_tb;
    
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
    conv_engine_2d U0 (.*);
    
    // 클럭 생성
    always #5 clk = ~clk;
    
    // 결과 수집
    always @(posedge clk) begin
        if (result_valid) begin
            actual_results[result_row][result_col] = result_out;
            $display("결과 [%2d,%2d]: %d", result_row, result_col, result_out);
            
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
                        input_image[y][x] = 8'd0;    // 왼쪽은 검은색
                    else
                        input_image[y][x] = 8'd255;  // 오른쪽은 흰색
                end
            end
        end
    endtask
    
    // 예상 결과 계산 태스크
    task calculate_expected_vertical_edge;
        begin
            $display("수직 에지 예상 결과 계산 중...");
            for (int y = 1; y < 31; y++) begin
                for (int x = 1; x < 31; x++) begin
                    // Sobel X 커널 적용
                    expected_result[y-1][x-1] = 
                        -1 * input_image[y-1][x-1] + 0 * input_image[y-1][x] + 1 * input_image[y-1][x+1] +
                        -2 * input_image[y][x-1]   + 0 * input_image[y][x]   + 2 * input_image[y][x+1] +
                        -1 * input_image[y+1][x-1] + 0 * input_image[y+1][x] + 1 * input_image[y+1][x+1];
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
        begin
            $display("체크보드 예상 결과 계산 중...");
            for (int y = 1; y < 31; y++) begin
                for (int x = 1; x < 31; x++) begin
                    expected_result[y-1][x-1] = 
                        -1 * input_image[y-1][x-1] + 0 * input_image[y-1][x] + 1 * input_image[y-1][x+1] +
                        -2 * input_image[y][x-1]   + 0 * input_image[y][x]   + 2 * input_image[y][x+1] +
                        -1 * input_image[y+1][x-1] + 0 * input_image[y+1][x] + 1 * input_image[y+1][x+1];
                end
            end
        end
    endtask
    
    // 테스트 실행 태스크
    task run_test(string test_name);
        begin
            $display("\n=== %s 테스트 시작 ===", test_name);
            
            // 초기화
            error_count = 0;
            result_row = 0;
            result_col = 0;
            pixel_count = 0;
            result_count = 0;
            
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
                    
                    if (pixel_count % 100 == 0) begin
                        $display("진행률: %4d/1024 픽셀 처리", pixel_count);
                    end
                end
            end
            
            @(posedge clk);
            pixel_valid = 0;
            
            $display("모든 픽셀 입력 완료. done 신호 대기 중...");
            wait (done_signal == 1);
            
            // 결과 검증
            $display("결과 검증 중...");
            for (int y = 0; y < 30; y++) begin
                for (int x = 0; x < 30; x++) begin
                    if (actual_results[y][x] !== expected_result[y][x]) begin
                        if (error_count < 10) begin  // 처음 10개 에러만 출력
                            $display("❌ 오류 [%2d,%2d]: 예상=%d, 실제=%d, 차이=%d", 
                                   y, x, expected_result[y][x], actual_results[y][x], 
                                   expected_result[y][x] - actual_results[y][x]);
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
            
            // 샘플 출력 (첫 5x5 영역)
            $display("\n샘플 결과 (첫 5x5 영역):");
            $display("실제 결과:");
            for (int y = 0; y < 5; y++) begin
                $write("  ");
                for (int x = 0; x < 5; x++) begin
                    $write("%6d ", actual_results[y][x]);
                end
                $display("");
            end
            
            $display("예상 결과:");
            for (int y = 0; y < 5; y++) begin
                $write("  ");
                for (int x = 0; x < 5; x++) begin
                    $write("%6d ", expected_result[y][x]);
                end
                $display("");
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
        generate_vertical_edge();
        calculate_expected_vertical_edge();
        run_test("수직 에지");
        #100;
        
        // 테스트 2: 체크보드
        generate_checkerboard();
        calculate_expected_checkerboard();
        run_test("체크보드");
        #100;
        
        $display("=== 모든 테스트 완료 ===");
        $finish;
    end
    
endmodule