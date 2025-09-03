`timescale 1ns/1ps
module CNN_TOP_with_SPI(
    // SPI 슬레이브 인터페이스
    input logic spi_clk,
    input logic spi_mosi,
    input logic spi_cs_n,
    
    // 시스템 인터페이스
    input logic sys_clk,
    input logic sys_rst,
    input logic start_signal,
    
    // 결과 출력
    output logic final_result_valid,
    output logic signed [47:0] final_lane_result
);

    // SPI 수신 버퍼
    logic [7:0] spi_rx_buffer [0:1023];
    logic [9:0] spi_byte_counter;
    logic [2:0] spi_bit_counter;
    logic [7:0] spi_shift_reg;
    logic spi_data_ready;
    
    // CNN 인터페이스 신호
    logic [7:0] pixel_data;
    logic pixel_valid;
    logic [9:0] pixel_counter;
    logic cnn_processing;
    
    // SPI 수신 로직
    always_ff @(posedge spi_clk or posedge spi_cs_n)
    begin
        if (spi_cs_n)  // SPI 비활성
        begin
            spi_bit_counter <= 0;
            spi_byte_counter <= 0;
            spi_shift_reg <= 0;
        end
        else  // SPI 활성
        begin
            spi_shift_reg <= {spi_shift_reg[6:0], spi_mosi};
            spi_bit_counter <= spi_bit_counter + 1;
            
            if (spi_bit_counter == 7)  // 8비트 완성
            begin
                spi_rx_buffer[spi_byte_counter] <= {spi_shift_reg[6:0], spi_mosi};
                spi_byte_counter <= spi_byte_counter + 1;
                spi_bit_counter <= 0;
            end
        end
    end
    
    // SPI 데이터 완료 검출
    always_ff @(posedge sys_clk)
    begin
        if (sys_rst)
            spi_data_ready <= 0;
        else if (spi_byte_counter == 1024 && spi_cs_n)
            spi_data_ready <= 1;
        else if (start_signal)
            spi_data_ready <= 0;
    end
    
    // CNN 데이터 전송 로직
    always_ff @(posedge sys_clk)
    begin
        if (sys_rst)
        begin
            pixel_counter <= 0;
            pixel_valid <= 0;
            pixel_data <= 0;
            cnn_processing <= 0;
        end
        else if (start_signal && spi_data_ready && !cnn_processing)
        begin
            cnn_processing <= 1;
            pixel_counter <= 0;
            pixel_valid <= 1;
            pixel_data <= spi_rx_buffer[0];
        end
        else if (cnn_processing)
        begin
            if (pixel_counter < 1023)
            begin
                pixel_counter <= pixel_counter + 1;
                pixel_data <= spi_rx_buffer[pixel_counter + 1];
                pixel_valid <= 1;
            end
            else
            begin
                pixel_valid <= 0;
                cnn_processing <= 0;
            end
        end
        else
        begin
            pixel_valid <= 0;
        end
    end

    // 기존 CNN_TOP 인스턴스
    CNN_TOP u_cnn_core (
        .clk(sys_clk),
        .rst(sys_rst),
        .start_signal(start_signal),
        .pixel_valid(pixel_valid),
        .pixel_in(pixel_data),
        .final_result_valid(final_result_valid),
        .final_lane_result(final_lane_result)
    );

endmodule