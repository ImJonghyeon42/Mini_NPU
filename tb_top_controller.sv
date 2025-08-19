`timescale 1ns/1ps

module tb_top_controller;

    // --- 신호 선언 (confidence 추가) ---
    logic clk, rst, start, rx_valid;
    logic [7:0] rx_data;
    logic [7:0] tx_data;
    logic [7:0] confidence;
    logic done_signal;
    
    logic [7:0] test_pixels [0:31]; 

    // --- DUT(테스트 대상 모듈) 인스턴스화 ---
    top_controller dut (
        .clk, .rst, .start,
        .rx_data, .rx_valid,
        .tx_data, .done_signal, .confidence
    );

    // --- 클럭 생성 ---
    initial clk = 0;
    always #5 clk = ~clk; // 100MHz 클럭

    // --- [핵심] 데이터 주입 및 결과 확인을 위한 태스크 ---
    task run_test(string test_name, int expected_center);
        begin
            $display("--------------------------------------------------");
            $display("--- Starting Test: %s ---", test_name);

            // 1. Start 신호 주기
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            // 2. 32바이트 픽셀 데이터 주입
            $display("Injecting pixel data...");
            for (int i=0; i<32; i++) begin
                rx_valid = 1;
                rx_data = test_pixels[i];
                @(posedge clk);
            end
            rx_valid = 0;
            
            // 3. done_signal이 1이 될 때까지 대기
            $display("Data injection complete. Waiting for result...");
            wait (done_signal == 1);
            @(posedge clk); 

            // 4. 결과 확인
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

    // --- 메인 테스트 시나리오 ---
    initial begin
        // 1. 초기화
        rst = 1; start = 0; rx_valid = 0; rx_data = '0;
        #20;
        rst = 0;
        
        // --- 시나리오 1: 기본 직선 주행 ---
        // 두 차선(8, 22)이 명확하게 보임. 예상 중앙값: (8+22)/2 = 15
        for (int i=0; i<32; i++) test_pixels[i] = 0;
        test_pixels[8] = 200; test_pixels[22] = 200;
        run_test("1. Straight Road", 15);
        #20;

        // --- 시나리오 2: 좌회전 (이전 프레임 중앙값 15 기준) ---
        // 왼쪽에 후보 2개(5, 9), 오른쪽에 후보 1개(21)
        // (5,9) 중앙: 7 (차이: 8) / (5,21) 중앙: 13 (차이: 2) / (9,21) 중앙: 15 (차이: 0)
        // 이전 중앙값 15와 가장 가까운 (9, 21) 쌍을 선택해야 함. 예상 중앙값: 15
        for (int i=0; i<32; i++) test_pixels[i] = 0;
        test_pixels[5] = 180; test_pixels[9] = 200; test_pixels[21] = 220;
        run_test("2. Left Curve", 15);
        #20;

        // --- 시나리오 3: 차선 하나만 보일 때 (오른쪽 차선 사라짐) ---
        // 유효한 쌍을 찾지 못하므로, 이전 프레임의 중앙값(15)을 그대로 유지해야 함.
        for (int i=0; i<32; i++) test_pixels[i] = 0;
        test_pixels[9] = 200; // 왼쪽 차선 하나만 보임
        run_test("3. Single Lane Visible", 15);
        #20;

        // --- 시나리오 4: 노이즈가 많을 때 ---
        // THRESHOLD(100) 이하의 약한 신호들은 무시되어야 함.
        // 유효한 쌍을 못 찾으므로, 이전 중앙값(15)을 유지해야 함.
        for (int i=0; i<32; i++) test_pixels[i] = 0;
        test_pixels[5] = 90; test_pixels[15] = 80; test_pixels[25] = 95; // 모두 100 이하
        run_test("4. Noisy Data", 15);
        #20;
        
        $finish;
    end

endmodule