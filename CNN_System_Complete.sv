`timescale 1ns/1ps
module CNN_System_Complete(
    // ===== 기본 입력 =====
    input logic clk_100mhz,
    input logic sys_rst_n,
    
    // ===== SPI 인터페이스 =====
    input logic spi_sclk,
    input logic spi_mosi,
    output logic spi_miso,
    input logic spi_cs_n,
    
    // ===== 디버깅 출력 =====
    output logic [15:0] status_leds,
    output logic [6:0] seg_display,
    output logic [3:0] seg_select,
    output logic uart_tx
);

    // ===== 내부 클록 및 리셋 =====
    logic clk_cnn;               // 150MHz CNN 클록
    logic clk_axi;               // 100MHz AXI 클록
    logic rst_cnn_n, rst_axi_n;
    logic locked;
    logic reset_for_clk_wiz;     // Clock Wizard용 리셋 신호
    
    // ===== CNN 제어 신호 =====
    logic cnn_start;
    logic cnn_busy;
    logic cnn_done;
    logic [47:0] cnn_result;
    logic cnn_result_valid;
    
    // ===== 이미지 스트림 =====
    logic pixel_valid;
    logic [7:0] pixel_data;
    
    // ===== SPI 관련 신호 =====
    logic [7:0] spi_rx_data;
    logic spi_rx_valid;
    logic spi_tx_ready;
    
    // ===== 리셋 신호 변환 (active low → active high) =====
    assign reset_for_clk_wiz = ~sys_rst_n;
    
    // ===== Clock Wizard IP (수정된 포트) =====
    clk_wiz_0 u_clk_wizard (
        .clk_in1(clk_100mhz),
        .clk_out1(clk_cnn),          // 150MHz
        .clk_out2(clk_axi),          // 100MHz  
        .locked(locked),
        .reset(reset_for_clk_wiz)    // Active High Reset
    );
    
    // ===== 리셋 동기화 =====
    reset_sync u_rst_cnn_sync (
        .clk(clk_cnn),
        .async_rst_n(sys_rst_n & locked),
        .sync_rst_n(rst_cnn_n)
    );
    
    reset_sync u_rst_axi_sync (
        .clk(clk_axi),
        .async_rst_n(sys_rst_n & locked),
        .sync_rst_n(rst_axi_n)
    );
    
    // ===== 간단한 SPI Slave 인터페이스 =====
    Simple_SPI_Slave u_spi_slave (
        .clk(clk_axi),
        .rst_n(rst_axi_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs_n(spi_cs_n),
        .rx_data(spi_rx_data),
        .rx_valid(spi_rx_valid),
        .tx_ready(spi_tx_ready)
    );
    
    // ===== SPI-CNN 어댑터 (단순화) =====
    Simple_SPI_CNN_Adapter u_adapter (
        .clk_axi(clk_axi),
        .clk_cnn(clk_cnn),
        .rst_axi_n(rst_axi_n),
        .rst_cnn_n(rst_cnn_n),
        
        // SPI Interface
        .spi_rx_data(spi_rx_data),
        .spi_rx_valid(spi_rx_valid),
        .spi_tx_ready(spi_tx_ready),
        
        // CNN Stream Interface
        .pixel_valid_out(pixel_valid),
        .pixel_data_out(pixel_data),
        .cnn_start(cnn_start),
        .cnn_result(cnn_result),
        .cnn_result_valid(cnn_result_valid)
    );
    
    // ===== 기존 CNN 엔진 =====
    CNN_TOP u_cnn_engine (
        .clk(clk_cnn),               // 150MHz
        .rst(rst_cnn_n),
        .start_signal(cnn_start),
        .pixel_valid(pixel_valid),
        .pixel_in(pixel_data),
        .final_result_valid(cnn_result_valid),
        .final_lane_result(cnn_result),
        .cnn_busy(cnn_busy)
    );
    
    // ===== CNN 완료 신호 생성 =====
    logic cnn_result_valid_d1;
    always_ff @(posedge clk_cnn or negedge rst_cnn_n) begin
        if (!rst_cnn_n) begin
            cnn_result_valid_d1 <= 1'b0;
            cnn_done <= 1'b0;
        end else begin
            cnn_result_valid_d1 <= cnn_result_valid;
            cnn_done <= cnn_result_valid && !cnn_result_valid_d1;
        end
    end
    
    // ===== 상태 LED (클록 신호 제거) =====
    logic [15:0] status_counter;
    
    // 상태 카운터 (디버깅용)
    always_ff @(posedge clk_axi or negedge rst_axi_n) begin
        if (!rst_axi_n) begin
            status_counter <= 16'h0;
        end else begin
            status_counter <= status_counter + 1;
        end
    end
    
    assign status_leds = {
        status_counter[7:0],         // 상위 8비트: 카운터 (시스템 동작 확인용)
        locked,                      // bit 7 - PLL 락
        cnn_busy,                    // bit 6 - CNN 처리 중
        cnn_result_valid,            // bit 5 - CNN 결과 유효
        spi_rx_valid,                // bit 4 - SPI 데이터 수신
        rst_cnn_n,                   // bit 3 - CNN 리셋 상태
        rst_axi_n,                   // bit 2 - AXI 리셋 상태
        1'b0,                        // bit 1 - 예약
        frame_counter[0]             // bit 0 - 프레임 카운터 LSB
    };
    
    // ===== 7-Segment 디스플레이 =====
    logic [31:0] frame_counter;
    always_ff @(posedge clk_cnn or negedge rst_cnn_n) begin
        if (!rst_cnn_n) begin
            frame_counter <= 32'h0;
        end else if (cnn_done) begin
            frame_counter <= frame_counter + 1;
        end
    end
    
    Seven_Segment_Display u_7seg (
        .clk(clk_axi),
        .rst_n(rst_axi_n),
        .display_value(frame_counter[15:0]),
        .seg_out(seg_display),
        .seg_sel(seg_select)
    );
    
    // ===== UART 디버그 =====
    assign uart_tx = 1'b1;
    
endmodule