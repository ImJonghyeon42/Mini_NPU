`timescale 1ns/1ps

module MAC_unit_tb();

    // Testbench signals
    logic clk;
    logic rst;
    logic i_valid;
    logic signed [21:0] data_in_a;
    logic signed [21:0] data_in_b;
    logic signed [47:0] sum_in;
    logic o_valid;
    logic signed [47:0] sum_out;
    
    parameter CLK_PERIOD = 10;
    
    // DUT instantiation
    MAC_unit dut (
        .clk(clk),
        .rst(rst),
        .i_valid(i_valid),
        .data_in_a(data_in_a),
        .data_in_b(data_in_b),
        .sum_in(sum_in),
        .o_valid(o_valid),
        .sum_out(sum_out)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Test vectors
    typedef struct {
        logic signed [21:0] a;
        logic signed [21:0] b;
        logic signed [47:0] sum_in_val;
        logic signed [47:0] expected;
    } test_vector_t;
    
    test_vector_t test_vectors[] = '{
        '{22'h100, 22'h200, 48'h0, 48'h20000},        // 256 * 512 + 0 = 131072
        '{22'h001, 22'h001, 48'h0, 48'h1},            // 1 * 1 + 0 = 1
        '{-22'h100, 22'h200, 48'h0, -48'h20000},      // -256 * 512 + 0 = -131072
        '{22'h100, -22'h200, 48'h0, -48'h20000},      // 256 * -512 + 0 = -131072
        '{22'h100, 22'h200, 48'h1000, 48'h21000},     // 256 * 512 + 4096 = 135168
        '{22'h0, 22'h0, 48'h12345678, 48'h12345678}   // 0 * 0 + 0x12345678 = 0x12345678
    };
    
    // Test procedure
    initial begin
        $display("=== MAC Unit Testbench Started ===");
        
        // Initialize signals
        rst = 1'b1;
        i_valid = 1'b0;
        data_in_a = 22'b0;
        data_in_b = 22'b0;
        sum_in = 48'b0;
        
        // Reset sequence
        repeat(5) @(posedge clk);
        rst = 1'b0;
        repeat(2) @(posedge clk);
        
        // Test each vector
        for (int i = 0; i < test_vectors.size(); i++) begin
            $display("Running test vector %0d", i);
            
            // Apply inputs
            @(posedge clk);
            i_valid = 1'b1;
            data_in_a = test_vectors[i].a;
            data_in_b = test_vectors[i].b;
            sum_in = test_vectors[i].sum_in_val;
            
            @(posedge clk);
            i_valid = 1'b0;
            
            // Wait for output (MAC has 3-cycle latency)
            repeat(3) @(posedge clk);
            
            // Check result
            if (o_valid && sum_out === test_vectors[i].expected) begin
                $display("✓ Test %0d PASSED: %0d * %0d + %0d = %0d", 
                        i, $signed(test_vectors[i].a), $signed(test_vectors[i].b), 
                        $signed(test_vectors[i].sum_in_val), $signed(sum_out));
            end else begin
                $display("✗ Test %0d FAILED: Expected %0d, Got %0d (valid: %b)", 
                        i, $signed(test_vectors[i].expected), $signed(sum_out), o_valid);
            end
            
            repeat(2) @(posedge clk);
        end
        
        // Test continuous operation
        $display("Testing continuous MAC operations...");
        for (int i = 0; i < 10; i++) begin
            @(posedge clk);
            i_valid = 1'b1;
            data_in_a = $random;
            data_in_b = $random;
            sum_in = $random;
        end
        
        @(posedge clk);
        i_valid = 1'b0;
        
        repeat(10) @(posedge clk);
        
        $display("=== MAC Unit Testbench Completed ===");
        $finish;
    end
    
    // Waveform dumping
    initial begin
        $dumpfile("mac_unit_tb.vcd");
        $dumpvars(0, MAC_unit_tb);
    end

endmodule