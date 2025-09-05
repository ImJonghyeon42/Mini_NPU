// 파일명: simple_spi_receiver.sv
`timescale 1ns / 1ps

module simple_spi_receiver (
    input logic        clk,               // 시스템 클럭 (s00_axi_cnn_aclk)
    input logic        rst,               // 리셋 신호
    
    // 외부 Physical SPI 핀
    input logic        spi_sclk,
    input logic        spi_mosi,
    input logic        spi_cs_n,
    
    // CNN 내부 모듈로 전달할 출력
    output logic [7:0] o_pixel_data,
    output logic       o_pixel_valid,
    output logic       o_frame_start
);

    // SPI SCLK는 비동기 신호이므로, 시스템 클럭으로 샘플링하여 엣지를 검출
    logic spi_sclk_d1, spi_sclk_d2;
    logic sclk_posedge;

    always_ff @(posedge clk) begin
        if (rst) begin
            spi_sclk_d1 <= 0;
            spi_sclk_d2 <= 0;
        end else begin
            spi_sclk_d1 <= spi_sclk;
            spi_sclk_d2 <= spi_sclk_d1;
        end
    end
    // SPI 클럭의 상승 엣지를 한 사이클 펄스로 검출 (CPHA=0 기준)
    assign sclk_posedge = ~spi_sclk_d2 && spi_sclk_d1;

    // SPI 데이터 수신 로직
    logic [2:0] bit_count;
    logic [9:0] byte_count;
    logic [7:0] shift_reg;
    logic       is_receiving;

    always_ff @(posedge clk) begin
        if (rst) begin
            bit_count     <= '0;
            byte_count    <= '0;
            shift_reg     <= '0;
            is_receiving  <= 1'b0;
            o_pixel_valid <= 1'b0;
            o_frame_start <= 1'b0;
        end else begin
            // 기본적으로 출력 펄스는 한 클럭 후에 Low가 됨
            o_pixel_valid <= 1'b0;
            o_frame_start <= 1'b0;

            if (!spi_cs_n && !is_receiving) begin // CS가 Low가 되면 수신 시작
                is_receiving <= 1'b1;
                bit_count    <= '0;
                byte_count   <= '0;
            end else if (spi_cs_n) begin // CS가 High가 되면 수신 중단 및 초기화
                is_receiving <= 1'b0;
            end

            if (is_receiving && sclk_posedge) begin
                shift_reg <= {shift_reg[6:0], spi_mosi}; // MSB부터 수신
                
                if (bit_count == 3'd7) begin // 8비트 수신 완료
                    bit_count     <= '0;
                    o_pixel_valid <= 1'b1; // 1-cycle valid 펄스 생성
                    
                    if (byte_count == 10'd0) begin
                        o_frame_start <= 1'b1; // 첫 바이트일 때 frame_start 펄스 생성
                    end
                    
                    if (byte_count < 1023) begin
                        byte_count <= byte_count + 1;
                    end else begin
                        // 마지막 바이트 수신 후 카운터 리셋
                        byte_count <= '0; 
                    end
                end else begin
                    bit_count <= bit_count + 1;
                end
            end
        end
    end

    assign o_pixel_data = shift_reg;

endmodule