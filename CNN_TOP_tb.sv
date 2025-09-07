`timescale 1ns/1ps

module tb_CNN_System_Complete();

    // ===== 시스템 파라미터 =====
    localparam CLK_100_PERIOD = 10.0;   // 100MHz
    localparam SPI_CLK_PERIOD = 125.0;  // 8MHz
    
    localparam IMAGE_WIDTH = 32;
    localparam IMAGE_HEIGHT = 32;
    localparam TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    
    // ===== 시스템 신호들 =====
    logic clk_100mhz;
    logic sys_rst_n;
    
    // SPI 인터페이스
    logic spi_sclk;
    logic spi_mosi;
    logic spi_miso;
    logic spi_cs_n;
    
    // 출력 신호들
    logic uart_tx;
    logic [15:0] status_leds;
    logic [6:0] seg_display;
    logic [3:0] seg_select;
    
    // ===== 테스트 변수들 =====
    logic [7:0] test_image [0:TOTAL_PIXELS-1];
    logic [47:0] cnn_results [0:4];  // 5개 테스트 결과 저장
    integer test_count;
    
    // ===== DUT 인스턴스 =====
    CNN_System_Complete u_dut (
        .clk_100mhz(clk_100mhz),
        .sys_rst_n(sys_rst_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs_n(spi_cs_n),
        .status_leds(status_leds),
        .seg_display(seg_display),
        .seg_select(seg_select),
        .uart_tx(uart_tx)
    );
    
    // ===== 클록 생성 =====
    initial begin
        clk_100mhz = 0;
        forever #(CLK_100_PERIOD/2) clk_100mhz = ~clk_100mhz;
    end
    
    initial begin
        spi_sclk = 0;
        forever #(SPI_CLK_PERIOD/2) spi_sclk = ~spi_sclk;
    end
    
    // ===== 메인 테스트 시퀀스 =====
    initial begin
        $display("CNN 시스템 테스트 시작");
        
        // 초기화
        initialize_system();
        
        // 단순한 CNN 테스트만 실행
        $display("CNN 처리 테스트 시작...");
        test_cnn_processing();
        
        $display("테스트 완료!");
        $finish;
    end
    
    // ===== 초기화 태스크 =====
    task initialize_system();
        begin
            // 신호 초기화
            sys_rst_n = 0;
            spi_cs_n = 1;
            spi_mosi = 0;
            test_count = 0;
            
            // 테스트 이미지 패턴 생성
            generate_test_patterns();
            
            // 리셋 해제
            repeat(10) @(posedge clk_100mhz);
            sys_rst_n = 1;
            repeat(100) @(posedge clk_100mhz);  // PLL 락 대기
            
            $display("시스템 초기화 완료");
        end
    endtask
    
    // ===== 테스트 패턴 생성 =====
    task generate_test_patterns();
        integer i, x, y;
        begin
            // 간단한 수직 엣지 패턴
            for (i = 0; i < TOTAL_PIXELS; i++) begin
                x = i % IMAGE_WIDTH;
                y = i / IMAGE_WIDTH;
                if (x < IMAGE_WIDTH/2) 
                    test_image[i] = 8'h00;  // 검은색
                else
                    test_image[i] = 8'hFF;  // 흰색
            end
        end
    endtask
    
    // ===== CNN 처리 테스트 =====
    task test_cnn_processing();
        integer frame_count;
        logic timeout_success;
        integer wait_cycles;
        begin
            for (frame_count = 0; frame_count < 1; frame_count++) begin  // 1프레임만 테스트
                $display("프레임 %d 처리 중...", frame_count + 1);
                
                // 이미지 전송
                $display("SPI 이미지 전송 시작...");
                send_full_image_via_spi();
                $display("SPI 이미지 전송 완료");
                
                // 상태 확인
                $display("전송 후 상태: status_leds=0x%04X", status_leds);
                
                // CNN 시작
                $display("CNN 시작 명령 전송...");
                trigger_cnn_processing();
                $display("CNN 시작 명령 완료");
                
                // 짧은 대기 후 상태 확인
                repeat(1000) @(posedge clk_100mhz);
                $display("CNN 시작 후 상태: status_leds=0x%04X", status_leds);
                $display("  - PLL Locked: %b", status_leds[7]);
                $display("  - CNN Busy: %b", status_leds[6]);
                $display("  - CNN Result Valid: %b", status_leds[5]);
                $display("  - SPI RX Valid: %b", status_leds[4]);
                
                // 완료 대기 (더 긴 타임아웃과 주기적 상태 출력)
                $display("CNN 완료 대기 중...");
                wait_cycles = 0;
                timeout_success = 1'b0;
                
                while (wait_cycles < 1000000 && !timeout_success) begin  // 10ms 타임아웃
                    if (status_leds[5] == 1'b1) begin  // CNN result valid
                        timeout_success = 1'b1;
                        $display("CNN 완료 감지! 대기 사이클: %d", wait_cycles);
                    end else begin
                        wait_cycles = wait_cycles + 1;
                        @(posedge clk_100mhz);
                        
                        // 1000 사이클마다 상태 출력
                        if (wait_cycles % 1000 == 0) begin
                            $display("대기 중... %d/1000000 사이클, 상태=0x%04X", 
                                     wait_cycles, status_leds);
                        end
                    end
                end
                
                if (timeout_success) begin
                    cnn_results[frame_count] = read_cnn_result();
                    $display("프레임 %d 완료 - 결과: 0x%012X", 
                             frame_count + 1, cnn_results[frame_count]);
                end else begin
                    $display("프레임 %d 타임아웃 - %d 사이클 대기", frame_count + 1, wait_cycles);
                    $display("최종 상태: status_leds=0x%04X", status_leds);
                end
                
                // 프레임간 간격
                repeat(1000) @(posedge clk_100mhz);
            end
            
            // 최종 결과 요약
            $display("\n=== 테스트 결과 요약 ===");
            $display("프레임 1: 0x%012X", cnn_results[0]);
            $display("최종 상태 LED: 0x%04X", status_leds);
            $display("PLL 상태: %s", status_leds[7] ? "Locked" : "Unlocked");
        end
    endtask
    
    // ===== 지원 태스크들 =====
    task send_full_image_via_spi();
        integer i;
        begin
            spi_cs_n = 0;
            send_spi_byte(8'hAA);  // IMAGE_DATA 명령
            send_spi_byte(8'h04);  // 길이 상위
            send_spi_byte(8'h00);  // 길이 하위
            
            for (i = 0; i < TOTAL_PIXELS; i++) begin
                send_spi_byte(test_image[i]);
            end
            
            // CRC (더미)
            send_spi_byte(8'h00);
            send_spi_byte(8'h00);
            send_spi_byte(8'h00);
            send_spi_byte(8'h00);
            
            spi_cs_n = 1;
            repeat(10) @(posedge spi_sclk);
        end
    endtask
    
    task trigger_cnn_processing();
        begin
            spi_cs_n = 0;
            send_spi_byte(8'hBB);  // START_CNN 명령
            send_spi_byte(8'h00);  // 길이
            send_spi_byte(8'h00);
            spi_cs_n = 1;
            repeat(5) @(posedge spi_sclk);
        end
    endtask
    
    task send_spi_byte(input [7:0] data);
        integer bit_idx;
        begin
            for (bit_idx = 7; bit_idx >= 0; bit_idx--) begin
                @(negedge spi_sclk);
                spi_mosi = data[bit_idx];
                @(posedge spi_sclk);
            end
        end
    endtask
    
    task wait_for_cnn_completion_with_timeout(input real timeout_ms, output logic success);
        integer timeout_cycles;
        integer cycle_count;
        begin
            timeout_cycles = timeout_ms * 1000000 / CLK_100_PERIOD;
            cycle_count = 0;
            
            while (status_leds[5] == 1'b0 && cycle_count < timeout_cycles) begin  // CNN result valid 대기
                @(posedge clk_100mhz);
                cycle_count++;
            end
            
            success = (cycle_count < timeout_cycles);
            
            if (success) begin
                @(posedge clk_100mhz);  // 한 사이클 더 대기
            end
        end
    endtask
    
    function [47:0] read_cnn_result();
        begin
            // 시뮬레이션용 결과 읽기
            read_cnn_result = {status_leds, status_leds, seg_display, seg_select, 9'h0};
        end
    endfunction
    
    // ===== 시뮬레이션 제어 =====
    initial begin
        // VCD 파일 생성
        $dumpfile("cnn_system_tb.vcd");
        $dumpvars(0, tb_CNN_System_Complete);
        
        // 시뮬레이션 타임아웃 (짧게 설정)
        #100_000_000;  // 100ms
        $display("시뮬레이션 타임아웃");
        $finish;
    end
    
    // ===== 모든 연속 모니터링 제거 =====
    // 어떤 always 블록도 연속적인 출력을 하지 않음
    
endmodule