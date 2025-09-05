`timescale 1ns/1ps

module axi_quad_spi_reader (
    input logic clk,
    input logic rst_n,
    
    // AXI Quad SPI Interface (읽기 전용)
    output logic [31:0] spi_read_addr,     // SPI 레지스터 주소
    input logic [31:0] spi_read_data,      // SPI 레지스터 데이터  
    output logic spi_read_valid,           // 읽기 요청
    input logic spi_data_available,        // 데이터 준비됨
    input logic [10:0] spi_rx_occupancy,   // RX FIFO 점유율 (0-1024)
    
    // Output to CNN
    output logic pixel_valid,              // 유효한 픽셀 데이터
    output logic [7:0] pixel_data,         // 픽셀 데이터 (8-bit)
    output logic frame_complete,           // 프레임 완료
    output logic frame_start,              // 프레임 시작
    
    // Control
    input logic start_reading              // 읽기 시작 신호
);

    // ===== Parameters =====
    localparam FRAME_SIZE = 1024;          // 32x32 = 1024 pixels
    localparam SPI_RX_FIFO_ADDR = 32'h6C;  // AXI Quad SPI RX FIFO 주소 (예시)
    localparam SPI_STATUS_ADDR = 32'h64;   // AXI Quad SPI 상태 레지스터 주소
    
    // FIFO 임계값
    localparam MIN_FIFO_DATA = 4;          // 최소 FIFO 데이터 (연속 읽기용)
    localparam FIFO_FULL_THRESHOLD = 1020; // FIFO 거의 가득참
    
    // ===== Internal Signals =====
    logic [10:0] pixel_counter;            // 픽셀 카운터 (0-1023)
    logic [3:0] read_delay_counter;        // 읽기 지연 카운터
    logic reading_active;                  // 읽기 활성 상태
    logic start_reading_d1;                // 시작 신호 지연
    logic start_pulse;                     // 시작 펄스
    
    enum logic [3:0] {
        IDLE,
        WAIT_DATA,
        CHECK_FIFO,
        READ_REQUEST,
        READ_WAIT,
        PROCESS_DATA,
        FRAME_DONE,
        ERROR_STATE
    } state, next_state;

    // ===== Edge Detection =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_reading_d1 <= '0;
        end else begin
            start_reading_d1 <= start_reading;
        end
    end
    
    assign start_pulse = start_reading && !start_reading_d1;

    // ===== State Machine =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (start_pulse) begin
                    next_state = WAIT_DATA;
                end
            end
            
            WAIT_DATA: begin
                if (spi_data_available && spi_rx_occupancy >= MIN_FIFO_DATA) begin
                    next_state = CHECK_FIFO;
                end
            end
            
            CHECK_FIFO: begin
                if (spi_rx_occupancy > 0) begin
                    next_state = READ_REQUEST;
                end else if (pixel_counter >= FRAME_SIZE) begin
                    next_state = FRAME_DONE;
                end else begin
                    next_state = WAIT_DATA;
                end
            end
            
            READ_REQUEST: begin
                next_state = READ_WAIT;
            end
            
            READ_WAIT: begin
                if (read_delay_counter >= 2) begin  // AXI 읽기 지연
                    next_state = PROCESS_DATA;
                end
            end
            
            PROCESS_DATA: begin
                if (pixel_counter >= FRAME_SIZE - 1) begin
                    next_state = FRAME_DONE;
                end else begin
                    next_state = CHECK_FIFO;
                end
            end
            
            FRAME_DONE: begin
                next_state = IDLE;
            end
            
            ERROR_STATE: begin
                if (start_pulse) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

    // ===== Control Logic =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_counter <= '0;
            read_delay_counter <= '0;
            reading_active <= '0;
            spi_read_addr <= '0;
            spi_read_valid <= '0;
            pixel_valid <= '0;
            pixel_data <= '0;
            frame_complete <= '0;
            frame_start <= '0;
        end else begin
            // Default values
            spi_read_valid <= '0;
            pixel_valid <= '0;
            frame_complete <= '0;
            frame_start <= '0;
            
            case (state)
                IDLE: begin
                    if (start_pulse) begin
                        pixel_counter <= '0;
                        reading_active <= '1;
                        frame_start <= '1;
                        $display("[SPI_READER] Frame reading started");
                    end else begin
                        reading_active <= '0;
                    end
                end
                
                WAIT_DATA: begin
                    // Wait for sufficient data in FIFO
                    if (spi_rx_occupancy >= FIFO_FULL_THRESHOLD) begin
                        $display("[SPI_READER] Warning: FIFO almost full (%0d)", spi_rx_occupancy);
                    end
                end
                
                CHECK_FIFO: begin
                    read_delay_counter <= '0;
                end
                
                READ_REQUEST: begin
                    spi_read_addr <= SPI_RX_FIFO_ADDR;
                    spi_read_valid <= '1;
                    read_delay_counter <= '0;
                    $display("[SPI_READER] Reading pixel[%0d], FIFO: %0d", pixel_counter, spi_rx_occupancy);
                end
                
                READ_WAIT: begin
                    read_delay_counter <= read_delay_counter + 1;
                end
                
                PROCESS_DATA: begin
                    // Extract 8-bit pixel data (LSB)
                    pixel_data <= spi_read_data[7:0];
                    pixel_valid <= '1;
                    pixel_counter <= pixel_counter + 1;
                    
                    // Debug output for first few pixels
                    if (pixel_counter < 10 || pixel_counter >= FRAME_SIZE - 5) begin
                        $display("[SPI_READER] Pixel[%0d] = 0x%02h", pixel_counter, spi_read_data[7:0]);
                    end
                end
                
                FRAME_DONE: begin
                    frame_complete <= '1;
                    reading_active <= '0;
                    $display("[SPI_READER] Frame complete - %0d pixels read", pixel_counter);
                end
                
                ERROR_STATE: begin
                    reading_active <= '0;
                    $display("[SPI_READER] Error state");
                end
            endcase
        end
    end

    // ===== FIFO Monitoring =====
    always @(posedge clk) begin
        if (reading_active) begin
            if (spi_rx_occupancy == 0 && pixel_counter < FRAME_SIZE && state != FRAME_DONE) begin
                $display("[SPI_READER] Warning: FIFO empty during read at pixel %0d", pixel_counter);
            end
        end
    end

    // ===== Output Status =====
    logic frame_in_progress;
    assign frame_in_progress = reading_active && (state != IDLE) && (state != FRAME_DONE);

endmodule