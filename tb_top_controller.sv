`timescale 1ns/1ps

module tb_top_controller;

    // -- 1. 占쎈뻿占쎌깈 獄쏉옙 占쎈?믭옙?뮞占쎈뱜 占쎈쑓占쎌뵠占쎄숲 占쎄퐨占쎈섧 (Scope ?눧紐꾩젫 占쎈퉸野껓옙) --
    logic clk, rst, start, rx_valid;
    logic [7:0] rx_data;
    logic [7:0] tx_data;
    logic [7:0] confidence;
    logic done_signal;
    
    // test_pixels?몴占? 筌뤴뫀諭? 占쎌쟿甕겸뫀以? 占쎌뵠占쎈짗
    logic [7:0] test_pixels [0:31]; 

    // -- 2. DUT 占쎌뵥占쎈뮞占쎄쉘占쎈뮞占쎌넅 --
    top_controller dut (
        .clk, .rst, .start,
        .rx_data, .rx_valid, // rx_valibe 占쎌궎占쏙옙 占쎈땾占쎌젟
        .tx_data, .done_signal, .confidence
    );

    // -- 3. 占쎄깻占쎌쑏 占쎄문占쎄쉐 --
    initial clk = 0;
    always #5 clk = ~clk; // 10ns 雅뚯눊由? (100MHz)

    // -- 4. 占쎈뼊占쎌뵬 占쎈?믭옙?뮞占쎈뱜 占쎈뻻占쎄돌?뵳?딆궎 ?뇡遺얠쨯 (initial ?뇡遺얠쨯 占쎈꽰占쎈?) --
    initial begin
        // ----- [1占쎈뼊?⑨옙: ?룯?뜃由곤옙?넅] -----
        rst = 1;
        start = 0;
        rx_valid = 0;
        rx_data = '0;
        
        $display("Simulation Start: Resetting DUT...");
        #20;
        rst = 0;

        // ----- [2占쎈뼊?⑨옙: 占쎈?믭옙?뮞占쎈뱜 占쎈쑓占쎌뵠占쎄숲 餓ο옙?뜮占?] -----
        for (int i=0; i<32; i++) test_pixels[i] = 0;
        
        test_pixels[15] = 100;
        test_pixels[16] = 200; // 占쎌굙占쎄맒 筌ㅼ뮆?솊揶쏉옙
        test_pixels[17] = 250;
        
        // ----- [3占쎈뼊?⑨옙: 占쎈쑓占쎌뵠占쎄숲 雅뚯눘?뿯] -----
        @(posedge clk);
        start = 1; // Start 占쎈뻿占쎌깈 獄쏆뮇源?
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

        // ----- [4占쎈뼊?⑨옙: 野껉퀗?궢 占쏙옙疫뀐옙 獄쏉옙 占쎌넇占쎌뵥] -----
        wait (dut.done_signal == 1);
        @(posedge clk); 

        if (dut.tx_data == 8'd200) begin
            $display("*************** TEST PASSED! ***************");
        end 
        else begin
            $display("*************** TEST FAILED! ***************");
            $display("Expected: %d, Got: %d", 200, dut.tx_data);
        end
        
        // ----- [5占쎈뼊?⑨옙: 占쎈뻻獒뺁됱쟿占쎌뵠占쎈?? ?넫?굝利?] -----
        #100;
        $finish;
    end

endmodule