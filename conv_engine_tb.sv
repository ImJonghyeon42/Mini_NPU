`timescale 1ns/1ps
module conv_engine_tb;

    // --- DUT 신호 선언 ---
	logic clk = 0, rst, start_signal, pixel_valid;
	logic [7:0] pixel_in;
	logic signed [21:0] result_out;
	logic result_valid, done_signal;

    // --- 테스트벤치 내부 변수 ---
    // FIX 2: 입력/정답 데이터를 위한 전체 크기 메모리 선언
    logic [7:0]               input_image_mem [0:32*32-1];
    logic signed [21:0]       golden_image_mem[0:32*32-1];
    integer                   error_count;
    integer                   result_idx;

	conv_engine_2d U0 (.*);
	
	always #5 clk = ~clk;
	
    // FIX 1 & 2: 태스크를 파일 기반으로 수정
	task run_test(string test_name, string input_file, string golden_file);
		begin
			 string base_path = "C:/JS/"; // 기본 폴더 경로를 변수로 지정
			string full_input_path;
			string full_golden_path;
		
			$display("--------------------------------------------");
			$display("--- Starting Test : %s ---", test_name);
            error_count = 0;
            result_idx = 0;

        full_input_path  = {base_path, input_file}; 
        full_golden_path = {base_path, golden_file};

        $display("Loading input file: %s", full_input_path);
        $display("Loading golden file: %s", full_golden_path);

        $readmemh(full_input_path, input_image_mem);
        $readmemh(full_golden_path, golden_image_mem);
	
            // DUT 시작
            @(posedge clk); start_signal = 1;
            @(posedge clk); start_signal = 0;
	
            // 데이터 주입
            for (int i = 0; i < U0.IMG_WIDTH * U0.IMG_HEIGHT; i++) begin
                @(posedge clk);
                pixel_valid = 1;
                pixel_in = input_image_mem[i];
            end
	
            @(posedge clk); pixel_valid = 0;
            $display("Data injection complete. Waiting for done signal...");
            wait (done_signal == 1);
            @(posedge clk); #10; // 마지막 출력이 나올 때까지 조금 더 대기

            if (error_count == 0) begin
                $display("******************* TEST PASSED! *******************");
            end else begin
                $display("******************* TEST FAILED! (%0d errors) *******************", error_count);
            end
		end
	endtask
	
    // FIX 1: 실시간 결과 검증 로직
    always @(posedge clk) begin
        if (result_valid) begin
            if (result_out !== golden_image_mem[result_idx]) begin
                $display("ERROR at index %0d: Expected=%h, Got=%h", result_idx, golden_image_mem[result_idx], result_out);
                error_count++;
            end
            result_idx++;
        end
    end

	initial begin
		rst = 1; start_signal = 0; pixel_valid = 0; pixel_in = '0;
		#20; rst = 0;
		
        // 각 테스트 케이스에 맞는 입력/정답 파일을 미리 생성해야 함
		run_test("1. Ramp Pattern", "ramp_in.hex", "ramp_golden.hex");
		#20;
		
		run_test("2. V-Stripe Pattern", "vstripe_in.hex", "vstripe_golden.hex");
		#20;

		run_test("3. Box Pattern", "box_in.hex", "box_golden.hex");
		#20;		
		
		$finish;
	end
endmodule