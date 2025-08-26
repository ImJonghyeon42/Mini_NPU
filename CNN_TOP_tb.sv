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
    
    // Test control variables
    int pixel_count;
    int cycle_count;
    
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
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Initialize test weights
    initial begin
        for (int i = 0; i <= 224; i++) begin
            weight_mem[i] = $urandom_range(0, 255); // 8-bit 안정 범위
        end
        $writememh("weight.mem", weight_mem);
    end
    
    // Initialize test image data (0~255 범위)
    initial begin
        for (int i = 0; i < TOTAL_PIXELS; i++) begin
            test_image[i] = $urandom_range(0, 255);
        end
    end
    
    // Main test procedure
    initial begin
        $display("=== CNN_TOP Testbench Started ===");
        
        rst = 1'b1;
        start_signal = 1'b0;
        pixel_valid = 1'b0;
        pixel_in = 8'b0;
        pixel_count = 0;
        cycle_count = 0;
        
        // Reset
        repeat(10) @(posedge clk);
        rst = 1'b0;
        $display("Reset released at time: %0t", $time);
        repeat(5) @(posedge clk);
        
        // Start signal
        @(posedge clk);
        start_signal = 1'b1;
        @(posedge clk);
        start_signal = 1'b0;
        $display("Start signal asserted at time: %0t", $time);
        
        // Feed image data
        for (int i = 0; i < TOTAL_PIXELS; i++) begin
            @(posedge clk);
            pixel_valid = 1'b1;
            pixel_in = test_image[i];
            pixel_count = i + 1;
            
            if (pixel_count % 128 == 0) 
                $display("Fed %0d pixels at time: %0t", pixel_count, $time);
        end
        
        @(posedge clk);
        pixel_valid = 1'b0;
        $display("All %0d pixels fed at time: %0t", TOTAL_PIXELS, $time);
        
        // Wait for final result
        wait(final_result_valid);
        $display("Final result: %0d (0x%h)", $signed(final_lane_result), final_lane_result);
        $display("Total cycles: %0d", cycle_count);
        
        $display("=== Testbench Completed Successfully ===");
        $finish;
    end
    
    // Cycle counter for monitoring
    always @(posedge clk) begin
        if (!rst)
            cycle_count <= cycle_count + 1;
    end
    
    // Waveform dumping
    initial begin
        $dumpfile("cnn_top_tb.vcd");
        $dumpvars(0, CNN_TOP_tb);
    end

endmodule
