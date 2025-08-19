`timescale 1ns/1ps

module tb_top_controller;

    // --- ��ȣ ���� (confidence �߰�) ---
    logic clk, rst, start, rx_valid;
    logic [7:0] rx_data;
    logic [7:0] tx_data;
    logic [7:0] confidence;
    logic done_signal;
    
    logic [7:0] test_pixels [0:31]; 

    // --- DUT(�׽�Ʈ ��� ���) �ν��Ͻ�ȭ ---
    top_controller dut (
        .clk, .rst, .start,
        .rx_data, .rx_valid,
        .tx_data, .done_signal, .confidence
    );

    // --- Ŭ�� ���� ---
    initial clk = 0;
    always #5 clk = ~clk; // 100MHz Ŭ��

    // --- [�ٽ�] ������ ���� �� ��� Ȯ���� ���� �½�ũ ---
    task run_test(string test_name, int expected_center);
        begin
            $display("--------------------------------------------------");
            $display("--- Starting Test: %s ---", test_name);

            // 1. Start ��ȣ �ֱ�
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            // 2. 32����Ʈ �ȼ� ������ ����
            $display("Injecting pixel data...");
            for (int i=0; i<32; i++) begin
                rx_valid = 1;
                rx_data = test_pixels[i];
                @(posedge clk);
            end
            rx_valid = 0;
            
            // 3. done_signal�� 1�� �� ������ ���
            $display("Data injection complete. Waiting for result...");
            wait (done_signal == 1);
            @(posedge clk); 

            // 4. ��� Ȯ��
            if (tx_data == expected_center) begin
                $display("*************** TEST PASSED! ***************");
                $display("Expected Center: %d, Got: %d", expected_center, tx_data);
            end else begin
                $display("*************** TEST FAILED! ***************");
                $display("Expected Center: %d, Got: %d", expected_center, tx_data);
            end
            $display("Confidence: %d", confidence);
            $display("--------------------------------------------------");
        end
		
		$display("Result data: ");
	for(int i=0; i<30; i++) begin
		$display("Position %d: %d", i, $signed(dut.result_data[i]));
	end
		$display("Detected peaks: %d", dut.peak_count);
	for(int i=0; i<dut.peak_count; i++) begin
		$display("Peak %d: Position=%d, Value=%d", i, dut.peak_positions[i], dut.peak_values[i]);
	end

    endtask

    // --- ���� �׽�Ʈ �ó����� ---
    initial begin
        // 1. �ʱ�ȭ
        rst = 1; start = 0; rx_valid = 0; rx_data = '0;
        #20;
        rst = 0;
        
        // --- �ó����� 1: �⺻ ���� ���� ---
        // �� ����(8, 22)�� ��Ȯ�ϰ� ����. ���� �߾Ӱ�: (8+22)/2 = 15
        for (int i=0; i<32; i++) test_pixels[i] = 0;
        test_pixels[8] = 200; test_pixels[22] = 200;
        run_test("1. Straight Road", 15);
        #20;

        // --- �ó����� 2: ��ȸ�� (���� ������ �߾Ӱ� 15 ����) ---
        // ���ʿ� �ĺ� 2��(5, 9), �����ʿ� �ĺ� 1��(21)
        // (5,9) �߾�: 7 (����: 8) / (5,21) �߾�: 13 (����: 2) / (9,21) �߾�: 15 (����: 0)
        // ���� �߾Ӱ� 15�� ���� ����� (9, 21) ���� �����ؾ� ��. ���� �߾Ӱ�: 15
        for (int i=0; i<32; i++) test_pixels[i] = 0;
        test_pixels[5] = 180; test_pixels[9] = 200; test_pixels[21] = 220;
        run_test("2. Left Curve", 15);
        #20;

        // --- �ó����� 3: ���� �ϳ��� ���� �� (������ ���� �����) ---
        // ��ȿ�� ���� ã�� ���ϹǷ�, ���� �������� �߾Ӱ�(15)�� �״�� �����ؾ� ��.
        for (int i=0; i<32; i++) test_pixels[i] = 0;
        test_pixels[9] = 200; // ���� ���� �ϳ��� ����
        run_test("3. Single Lane Visible", 15);
        #20;

        // --- �ó����� 4: ����� ���� �� ---
        // THRESHOLD(100) ������ ���� ��ȣ���� ���õǾ�� ��.
        // ��ȿ�� ���� �� ã���Ƿ�, ���� �߾Ӱ�(15)�� �����ؾ� ��.
        for (int i=0; i<32; i++) test_pixels[i] = 0;
        test_pixels[5] = 90; test_pixels[15] = 80; test_pixels[25] = 95; // ��� 100 ����
        run_test("4. Noisy Data", 15);
        #20;
        
        $finish;
    end

endmodule