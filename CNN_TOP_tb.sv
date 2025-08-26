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

    // Test parameters
    parameter IMG_WIDTH = 32;
    parameter IMG_HEIGHT = 32;
    parameter TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;
    parameter CLK_PERIOD = 10;

    // Test data storage
    logic [7:0] test_image [0:TOTAL_PIXELS-1];
    logic [7:0] weight_mem [0:224];

    // Expected output
    logic signed [47:0] expected_result;

    // Test control variables
    int pixel_count;
    int cycle_count;
    bit test_passed;

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
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Initialize test image and weights
    initial begin
        // Simple test pattern: all pixels = 1
        for (int i = 0; i < TOTAL_PIXELS; i++) begin
            test_image[i] = 8'd1;
        end

        // Simple weights: all weights = 1
        for (int i = 0; i <= 224; i++) begin
            weight_mem[i] = 8'd1;
        end

        // Expected CNN output (수동 계산)
        // conv + activation + pooling + flatten + fully connected 계산 후 예상값
        expected_result = 1315356; // 예시 값 (실제 CNN 계산에 맞춰 수정 필요)
    end

    // Main test procedure
    initial begin
        $display("=== CNN_TOP Testbench Started ===");

        // Initialize signals
        rst = 1'b1;
        start_signal = 1'b0;
        pixel_valid = 1'b0;
        pixel_in = 8'b0;
        pixel_count = 0;
        cycle_count = 0;
        test_passed = 1'b1;

        // Reset sequence
        repeat(10) @(posedge clk);
        rst = 1'b0;
        repeat(5) @(posedge clk);

        // Start the CNN processing
        @(posedge clk);
        start_signal = 1'b1;
        @(posedge clk);
        start_signal = 1'b0;

        // Feed image data
        for (int i = 0; i < TOTAL_PIXELS; i++) begin
            @(posedge clk);
            pixel_valid = 1'b1;
            pixel_in = test_image[i];
            pixel_count = i + 1;
        end
        @(posedge clk);
        pixel_valid = 1'b0;

        // Wait for final result
        wait(final_result_valid);
        $display("Final result: %0d (0x%h)", $signed(final_lane_result), final_lane_result);

        // Compare with expected value
        if (final_lane_result !== expected_result) begin
            $display("✗ Test FAILED: output mismatch!");
            $display("Expected: %0d (0x%h)", expected_result, expected_result);
            test_passed = 1'b0;
        end else begin
            $display("✓ Test PASSED: output matches expected value");
        end

        $display("=== Testbench Completed ===");
        if (!test_passed) $fatal(1);
        $finish;
    end

    // Waveform dumping
    initial begin
        $dumpfile("cnn_top_tb.vcd");
        $dumpvars(0, CNN_TOP_tb);
    end

endmodule
