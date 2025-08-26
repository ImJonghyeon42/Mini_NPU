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
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Create weight.mem file for fully connected layer
    initial begin
        // Generate simple test weights (can be modified for specific test cases)
        for (int i = 0; i <= 224; i++) begin
            weight_mem[i] = $random % 256; // Random 8-bit values
        end
        
        // Write to file
        $writememh("weight.mem", weight_mem);
    end
    
    // Initialize test image data
    initial begin
        // Generate test pattern - simple gradient or checkerboard
        for (int i = 0; i < TOTAL_PIXELS; i++) begin
            // Create a simple test pattern
            test_image[i] = (i % 256); // Simple incrementing pattern
        end
    end
    
    // Main test procedure
    initial begin
        $display("=== CNN_TOP Testbench Started ===");
        $display("Time: %0t", $time);
        
        // Initialize signals
        rst = 1'b1;
        start_signal = 1'b0;
        pixel_valid = 1'b0;
        pixel_in = 8'b0;
        pixel_count = 0;
        cycle_count = 0;
        
        // Reset sequence
        repeat(10) @(posedge clk);
        rst = 1'b0;
        $display("Reset released at time: %0t", $time);
        
        // Wait a few cycles before starting
        repeat(5) @(posedge clk);
        
        // Start the CNN processing
        @(posedge clk);
        start_signal = 1'b1;
        @(posedge clk);
        start_signal = 1'b0;
        $display("Start signal asserted at time: %0t", $time);
        
        // Feed image data
        fork
            // Input data process
            begin
                for (int i = 0; i < TOTAL_PIXELS; i++) begin
                    @(posedge clk);
                    pixel_valid = 1'b1;
                    pixel_in = test_image[i];
                    pixel_count = i + 1;
                    
                    if ((i + 1) % (IMG_WIDTH * 4) == 0) begin
                        $display("Fed %0d pixels at time: %0t", i + 1, $time);
                    end
                end
                @(posedge clk);
                pixel_valid = 1'b0;
                $display("All %0d pixels fed at time: %0t", TOTAL_PIXELS, $time);
            end
            
            // Monitor process
            begin
                while (!final_result_valid) begin
                    @(posedge clk);
                    cycle_count++;
                    
                    // Monitor intermediate signals
                    if (dut.feature_valid) begin
                        $display("Feature output: %0d at time: %0t", 
                                $signed(dut.feature_result), $time);
                    end
                    
                    if (dut.flattened_buffer_full) begin
                        $display("Flatten buffer full at time: %0t", $time);
                    end
                end
            end
        join
        
        // Wait for final result
        $display("Waiting for final result...");
        wait(final_result_valid);
        
        $display("=== Final Results ===");
        $display("Final result: %0d (0x%h)", $signed(final_lane_result), final_lane_result);
        $display("Total cycles: %0d", cycle_count);
        $display("Processing completed at time: %0t", $time);
        
        // Additional verification
        verify_results();
        
        // Wait a few more cycles
        repeat(10) @(posedge clk);
        
        $display("=== Testbench Completed Successfully ===");
        $finish;
    end
    
    // Verification task
    task verify_results();
        begin
            $display("=== Verification ===");
            
            // Check if final result is within expected range
            if (final_result_valid) begin
                $display("✓ Final result valid asserted correctly");
            end else begin
                $display("✗ Final result valid not asserted");
            end
            
            // Check flatten buffer contents (first few values)
            $display("Flatten buffer first 5 values:");
            for (int i = 0; i < 5; i++) begin
                $display("  [%0d]: %0d", i, $signed(dut.flatten_data[i]));
            end
            
            $display("Flatten buffer last 5 values:");
            for (int i = 220; i < 225; i++) begin
                $display("  [%0d]: %0d", i, $signed(dut.flatten_data[i]));
            end
        end
    endtask
    
    // Timeout mechanism
    initial begin
        #(CLK_PERIOD * 100000); // 100k cycles timeout
        $display("ERROR: Testbench timeout!");
        $finish;
    end
    
    // Waveform dumping
    initial begin
        $dumpfile("cnn_top_tb.vcd");
        $dumpvars(0, CNN_TOP_tb);
    end
    
    // Performance monitoring
    always @(posedge clk) begin
        if (!rst && cycle_count > 0 && cycle_count % 1000 == 0) begin
            $display("Cycle %0d - Time: %0t", cycle_count, $time);
        end
    end

endmodule