`timescale 1ns/1ps
module Feature_Extractor_tb;

    // 1. 환경 설정
    logic clk;
    logic rst;
    logic start_signal;
    logic pixel_valid_in;
    logic [7:0] pixel_in;

    logic signed [21:0] final_result_out;
    logic             final_result_valid;
    logic             final_done_signal;

    // DUT 인스턴스화
    Feature_Extractor DUT (.*);

    // 클럭 및 리셋 생성
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 2. 데이터 준비 (메모리 선언)
    localparam IMG_WIDTH  = 32;
    localparam IMG_HEIGHT = 32;
    localparam POOL_OUT_WIDTH = 16;
    localparam POOL_OUT_HEIGHT = 16;

    logic [7:0] image_mem [0:IMG_WIDTH*IMG_HEIGHT-1];
    logic signed [21:0] golden_mem [0:POOL_OUT_WIDTH*POOL_OUT_HEIGHT-1];

    // 3. 테스트 시나리오
    initial begin
        // 초기화
        rst = 1;
        start_signal = 0;
        pixel_valid_in = 0;
        pixel_in = 0;
        #20 rst = 0;

        // 데이터 로딩
        $readmemh("image_in.hex", image_mem);
        $readmemh("golden_out.hex", golden_mem);

        // 입력 데이터 주입
        start_signal = 1;
        #10 start_signal = 0;

        for (int i = 0; i < IMG_WIDTH*IMG_HEIGHT; i++) begin
            @(posedge clk);
            pixel_valid_in = 1;
            pixel_in = image_mem[i];
        end
        @(posedge clk);
        pixel_valid_in = 0;
    end

    // 4. 결과 비교
    integer error_count = 0;
    integer golden_idx = 0;
    always @(posedge clk) begin
        if (!rst && final_result_valid) begin
            if (final_result_out !== golden_mem[golden_idx]) begin
                $display("ERROR at index %d: DUT=%h, GOLDEN=%h", golden_idx, final_result_out, golden_mem[golden_idx]);
                error_count++;
            end
            golden_idx++;
        end
    end

    // 최종 결과 판정
    always @(posedge clk) begin
        if (final_done_signal) begin
            #10;
            if (error_count == 0) begin
                $display("******************************");
                $display("****** TEST PASSED!   ******");
                $display("******************************");
            end else begin
                $display("******************************");
                $display("****** TEST FAILED!   ******");
                $display("******************************");
            end
            $finish;
        end
    end

endmodule