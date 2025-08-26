`timescale 1ns/1ps
module CNN_TOP_tb();

    // Clock and Reset
    logic clk;
    logic rst;

    // Input signals
    logic start_signal;
    logic pixel_valid;
    logic [7:0] pixel_in;

    // Output signals
    logic final_result_valid;
    logic signed [47:0] final_lane_result;

    // DUT instantiation
    CNN_TOP dut (
        .clk(clk),
        .rst(rst),
        .start_signal(start_signal),
        .pixel_valid(pixel_valid),
        .pixel_in(pixel_in),
        .final_result_valid(final_result_valid),
        .final_lane_result(final_lane_result)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz clock

    // Test data
    parameter IMG_SIZE = 32*32;
    logic [7:0] test_image [0:IMG_SIZE-1];
    logic signed [47:0] expected_result;

    initial begin
        // 간단한 테스트 패턴
        for(int i=0;i<IMG_SIZE;i++) test_image[i] = i%256;
        // Python reference 연산 결과 입력
        expected_result = 1315356; // 실제 CNN reference 결과로 바꿀 것
    end

    // Main test
    initial begin
        $display("=== CNN_TOP Testbench Started ===");
        
        // Reset sequence
        rst = 1'b1;
        start_signal = 1'b0;
        pixel_valid = 1'b0;
        pixel_in = 8'b0;
        repeat(10) @(posedge clk);
        rst = 1'b0;

        // Wait a few cycles
        repeat(5) @(posedge clk);

        // Start DUT
        @(posedge clk);
        start_signal = 1'b1;
        @(posedge clk);
        start_signal = 1'b0;

        // Feed image pixels
        int idx = 0;
        while(idx < IMG_SIZE) begin
            @(posedge clk);
            pixel_valid = 1'b1;
            pixel_in = test_image[idx];
            idx++;
        end
        @(posedge clk);
        pixel_valid = 1'b0;

        // Wait for final result
        wait(final_result_valid);
        $display("Final result: %0d (0x%h)", final_lane_result, final_lane_result);

        // Verification
        if(final_lane_result === expected_result) begin
            $display("✓ Test PASSED");
        end else begin
            $display("? Test FAILED: expected %0d (0x%h)", expected_result, expected_result);
        end

        $finish;
    end

    // Waveform dumping
    initial begin
        $dumpfile("cnn_top_tb.vcd");
        $dumpvars(0, CNN_TOP_tb);
    end

endmodule
