`timescale 1ns/1ps

module tb_top_controller;

    // -- 1. �떊�샇 諛� ��?��?���듃 �뜲�씠�꽣 �꽑�뼵 (Scope ?��몄젣 �빐寃�) --
    logic clk, rst, start, rx_valid;
    logic [7:0] rx_data;
    logic [7:0] tx_data;
    logic done_signal;
    
    // test_pixels?���? 紐⑤�? �젅踰⑤�? �씠�룞
    logic [7:0] test_pixels [0:31]; 

    // -- 2. DUT �씤�뒪�꽩�뒪�솕 --
    top_controller dut (
        .clk, .rst, .start,
        .rx_data, .rx_valid, // rx_valibe �삤�� �닔�젙
        .tx_data, .done_signal
    );

    // -- 3. �겢�윮 �깮�꽦 --
    initial clk = 0;
    always #5 clk = ~clk; // 10ns 二쇨�? (100MHz)

    // -- 4. �떒�씪 ��?��?���듃 �떆�굹?��?�삤 ?��붾줉 (initial ?��붾줉 �넻��?) --
    initial begin
        // ----- [1�떒?��: ?��?��린�?��] -----
        rst = 1;
        start = 0;
        rx_valid = 0;
        rx_data = '0;
        
        $display("Simulation Start: Resetting DUT...");
        #20;
        rst = 0;

        // ----- [2�떒?��: ��?��?���듃 �뜲�씠�꽣 以�?���?] -----
        for (int i=0; i<32; i++) test_pixels[i] = 0;
        
        test_pixels[15] = 100;
        test_pixels[16] = 200; // �삁�긽 理쒕?��媛�
        test_pixels[17] = 100;
        
        // ----- [3�떒?��: �뜲�씠�꽣 二쇱?��] -----
        @(posedge clk);
        start = 1; // Start �떊�샇 諛쒖�?
        @(posedge clk);
        start = 0;

        $display("Injecting 32 bytes of pixel data...");
        for (int i=0; i<32; i++) begin
            rx_valid = 1;
            rx_data = test_pixels[i];
            @(posedge clk);
        end
        rx_valid = 0;
        
        $display("Data injection complete. Waiting for result...");

        // ----- [4�떒?��: 寃곌?�� ��湲� 諛� �솗�씤] -----
        wait (dut.done_signal == 1);
        @(posedge clk); 

        if (dut.tx_data == 8'd200) begin
            $display("*************** TEST PASSED! ***************");
        end 
        else begin
            $display("*************** TEST FAILED! ***************");
            $display("Expected: %d, Got: %d", 200, dut.tx_data);
        end
        
        // ----- [5�떒?��: �떆裕щ젅�씠��?? ?��?���?] -----
        #100;
        $finish;
    end

endmodule