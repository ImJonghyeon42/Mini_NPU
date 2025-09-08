// 간단한 테스트벤치 - 기본 동작만 확인
module tb_cnn_system_simple;

    logic clk, rst_n;
    logic spi_slave_sclk, spi_slave_mosi, spi_slave_miso, spi_slave_ss;
    logic spi_master_sclk, spi_master_mosi, spi_master_miso, spi_master_ss;
    logic [3:0] status_led;

    // DUT 인스턴스
    IP_CNN_System_Fast_Fixed dut (
        .clk(clk),
        .rst_n(rst_n),
        .spi_slave_sclk(spi_slave_sclk),
        .spi_slave_mosi(spi_slave_mosi),
        .spi_slave_miso(spi_slave_miso),
        .spi_slave_ss(spi_slave_ss),
        .spi_master_sclk(spi_master_sclk),
        .spi_master_mosi(spi_master_mosi),
        .spi_master_miso(spi_master_miso),
        .spi_master_ss(spi_master_ss),
        .status_led(status_led)
    );

    // 클럭 생성 (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // SPI Slave 클럭 생성 (1MHz)
    initial begin
        spi_slave_sclk = 0;
        forever #500 spi_slave_sclk = ~spi_slave_sclk;
    end

    // 테스트 시나리오
    initial begin
        // 초기화
        rst_n = 0;
        spi_slave_mosi = 0;
        spi_slave_ss = 1;
        spi_master_miso = 0;
        
        // 리셋 해제
        #100;
        rst_n = 1;
        
        $display("=== CNN 시스템 테스트 시작 ===");
        
        // 기본 상태 확인
        #100;
        if (status_led == 4'b0001) begin
            $display("? IDLE 상태 확인됨");
        end else begin
            $display("? IDLE 상태 오류: %b", status_led);
        end
        
        // 간단한 SPI 전송 시뮬레이션
        spi_slave_ss = 0;  // SPI 시작
        #50;
        
        // 몇 바이트 전송 (실제로는 1024바이트 필요)
        for (int i = 0; i < 10; i++) begin
            send_spi_byte(8'hAA + i);
        end
        
        spi_slave_ss = 1;  // SPI 종료
        
        // 상태 변화 관찰
        #1000;
        $display("상태 LED: %b", status_led);
        
        // 테스트 완료
        #5000;
        $display("=== 테스트 완료 ===");
        $finish;
    end

    // SPI 바이트 전송 태스크
    task send_spi_byte(input [7:0] data);
        for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
            @(negedge spi_slave_sclk);
            spi_slave_mosi = data[bit_idx];
            @(posedge spi_slave_sclk);
        end
    endtask

    // 상태 모니터링
    always @(posedge clk) begin
        if (status_led != 4'b0001) begin
            $display("시간 %t: 상태 변경 - LED: %b", $time, status_led);
        end
    end

endmodule