`timescale 1ns/1ps

module tb_top_controller;

    // -- 1. ï¿½ë–Šï¿½ìƒ‡ è«›ï¿½ ï¿½ë?’ï¿½?’ªï¿½ë“ƒ ï¿½ëœ²ï¿½ì” ï¿½ê½£ ï¿½ê½‘ï¿½ë¼µ (Scope ?‡¾ëª„ì £ ï¿½ë¹å¯ƒï¿½) --
    logic clk, rst, start, rx_valid;
    logic [7:0] rx_data;
    logic [7:0] tx_data;
    logic done_signal;
    
    // test_pixels?‘œï¿? ï§â‘¤ë±? ï¿½ì …è¸°â‘¤ì¤? ï¿½ì” ï¿½ë£
    logic [7:0] test_pixels [0:31]; 

    // -- 2. DUT ï¿½ì”¤ï¿½ë’ªï¿½ê½©ï¿½ë’ªï¿½ì†• --
    top_controller dut (
        .clk, .rst, .start,
        .rx_data, .rx_valid, // rx_valibe ï¿½ì‚¤ï¿½ï¿½ ï¿½ë‹”ï¿½ì ™
        .tx_data, .done_signal
    );

    // -- 3. ï¿½ê²¢ï¿½ìœ® ï¿½ê¹®ï¿½ê½¦ --
    initial clk = 0;
    always #5 clk = ~clk; // 10ns äºŒì‡¨ë¦? (100MHz)

    // -- 4. ï¿½ë–’ï¿½ì”ª ï¿½ë?’ï¿½?’ªï¿½ë“ƒ ï¿½ë–†ï¿½êµ¹?”±?Šì‚¤ ?‡‰ë¶¾ì¤‰ (initial ?‡‰ë¶¾ì¤‰ ï¿½ë„»ï¿½ë?) --
    initial begin
        // ----- [1ï¿½ë–’?¨ï¿½: ?¥?‡ë¦°ï¿½?†•] -----
        rst = 1;
        start = 0;
        rx_valid = 0;
        rx_data = '0;
        
        $display("Simulation Start: Resetting DUT...");
        #20;
        rst = 0;

        // ----- [2ï¿½ë–’?¨ï¿½: ï¿½ë?’ï¿½?’ªï¿½ë“ƒ ï¿½ëœ²ï¿½ì” ï¿½ê½£ ä»¥ï¿½?®ï¿?] -----
        for (int i=0; i<32; i++) test_pixels[i] = 0;
        
        test_pixels[15] = 100;
        test_pixels[16] = 200; // ï¿½ì‚ï¿½ê¸½ ï§¤ì’•?™åª›ï¿½
        test_pixels[17] = 100;
        
        // ----- [3ï¿½ë–’?¨ï¿½: ï¿½ëœ²ï¿½ì” ï¿½ê½£ äºŒì‡±?—¯] -----
        @(posedge clk);
        start = 1; // Start ï¿½ë–Šï¿½ìƒ‡ è«›ì’–ê¹?
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

        // ----- [4ï¿½ë–’?¨ï¿½: å¯ƒê³Œ?‚µ ï¿½ï¿½æ¹²ï¿½ è«›ï¿½ ï¿½ì†—ï¿½ì”¤] -----
        wait (dut.done_signal == 1);
        @(posedge clk); 

        if (dut.tx_data == 8'd200) begin
            $display("*************** TEST PASSED! ***************");
        end 
        else begin
            $display("*************** TEST FAILED! ***************");
            $display("Expected: %d, Got: %d", 200, dut.tx_data);
        end
        
        // ----- [5ï¿½ë–’?¨ï¿½: ï¿½ë–†è£•Ñ‰ì …ï¿½ì” ï¿½ë?? ?†«?‚…ì¦?] -----
        #100;
        $finish;
    end

endmodule