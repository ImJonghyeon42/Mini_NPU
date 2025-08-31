`timescale 1ns/1ps
module tb_max_pooling;

    // 1. DUT(테스트 대상) 신호 선언
    logic clk;
    logic rst;
    logic start_signal;
    logic pixel_valid;
    logic signed [21:0] pixel_in;
    logic signed [21:0] result_out;
    logic result_valid;
    logic done_signal;

    // --- Max_Pooling DUT 인스턴스 ---
    Max_Pooling #(
        .IMG_WIDTH(4),  // [핵심] 테스트를 위해 이미지 크기를 4x4로 대폭 축소
        .IMG_HEIGHT(4)
    ) dut (.*);

    // 2. 클럭 생성
    initial clk = 0;
    always #5 clk = ~clk;

    // 3. 테스트 시나리오
    initial begin
        $display("--- Max_Pooling Unit Test START ---");

        // --- 초기화 ---
        rst = 1;
        start_signal = 0;
        pixel_valid = 0;
        pixel_in = 0;
        #20;
        rst = 0;
        #10;

        // --- 시작 신호 ---
        @(posedge clk);
        start_signal = 1;
        @(posedge clk);
        start_signal = 0;

        // --- 4x4 이미지 데이터 주입 ---
        // 2x2 Max Pooling의 첫 결과는 (x=1, y=1)에서 나옴
        for (int y = 0; y < 4; y = y + 1) begin
            for (int x = 0; x < 4; x = x + 1) begin
                @(posedge clk);
                pixel_valid = 1;
                pixel_in = y * 4 + x + 1; // 1, 2, 3, ... 16 순서로 데이터 주입
                $display("Time=%0t, Injecting pixel (%0d, %0d) = %d", $time, x, y, pixel_in);
            end
        end
        @(posedge clk);
        pixel_valid = 0;

        $display("Data injection complete. Waiting for done signal...");

        wait(done_signal);
        #20;

        $display("--- Max_Pooling Unit Test FINISHED ---");
        $finish;
    end

    // 4. 결과 모니터링
    always @(posedge clk) begin
        if (result_valid) begin
            // 결과가 유효할 때마다 입력 윈도우와 최종 결과를 출력
            $display("----------------------------------------------------");
            $display("Time=%0t, Result Valid!", $time);
            $display("  >> Window Top Left  (line_buffer[cnt_x-1]) = %d", dut.win_top_left);
            $display("  >> Window Top Right (line_buffer[cnt_x])   = %d", dut.win_top_right);
            $display("  >> Window Bot Left  (pixel_d1)             = %d", dut.win_bot_left);
            $display("  >> Window Bot Right (pixel_in)             = %d", dut.win_bot_right);
            $display("  >> MAX Result                               = %d", result_out);
            $display("----------------------------------------------------");
        end
    end

endmodule