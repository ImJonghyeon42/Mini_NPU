`timescale 1ns/1ps

module cnn_control_logic_simple (
    input logic clk,
    input logic rst_n,
    
    // AXI Control Interface (제어 전용)
    input logic [31:0] control_reg,      // Control register from AXI
    output logic [31:0] status_reg,      // Status register to AXI
    output logic [31:0] frame_count_reg, // Frame count register
    output logic [31:0] error_code_reg,  // Error code register
    
    // CNN Interface
    output logic cnn_start,              // Start CNN processing
    output logic cnn_reset,              // Reset CNN
    input logic cnn_busy,                // CNN is busy
    input logic cnn_result_valid,        // CNN result valid
    
    // SPI Frame 모니터링 (픽셀 처리 제거)
    input logic spi_frame_start,         // SPI frame start signal
    input logic spi_pixel_valid,         // SPI pixel valid signal
    
    // Output counters
    output logic [31:0] frame_counter,   // Processed frame counter
    output logic [31:0] error_code       // Error code
);

    // ===== Parameters =====
    localparam ERROR_NONE           = 32'h00000000;
    localparam ERROR_CNN_TIMEOUT    = 32'h00000001;
    localparam ERROR_INVALID_START  = 32'h00000002;
    
    // Control register bit definitions
    localparam CTRL_CNN_START       = 0;    // Bit 0: Start CNN
    localparam CTRL_CNN_RESET       = 1;    // Bit 1: Reset CNN
    
    // ===== Internal Signals =====
    logic [31:0] frame_count_internal;
    logic [31:0] error_code_internal;
    
    logic cnn_start_d1, cnn_reset_d1;
    logic spi_frame_start_d1;
    
    logic cnn_start_pulse, cnn_reset_pulse;
    logic spi_frame_start_pulse;
    
    logic cnn_result_valid_d1;
    logic cnn_result_valid_pulse;

    // ===== Edge Detection =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnn_start_d1 <= '0;
            cnn_reset_d1 <= '0;
            spi_frame_start_d1 <= '0;
            cnn_result_valid_d1 <= '0;
        end else begin
            cnn_start_d1 <= control_reg[CTRL_CNN_START];
            cnn_reset_d1 <= control_reg[CTRL_CNN_RESET];
            spi_frame_start_d1 <= spi_frame_start;
            cnn_result_valid_d1 <= cnn_result_valid;
        end
    end
    
    assign cnn_start_pulse = control_reg[CTRL_CNN_START] && !cnn_start_d1;
    assign cnn_reset_pulse = control_reg[CTRL_CNN_RESET] && !cnn_reset_d1;
    assign spi_frame_start_pulse = spi_frame_start && !spi_frame_start_d1;
    assign cnn_result_valid_pulse = cnn_result_valid && !cnn_result_valid_d1;

    // ===== Control Logic =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_count_internal <= '0;
            error_code_internal <= ERROR_NONE;
        end else begin
            // Reset handling
            if (cnn_reset_pulse) begin
                error_code_internal <= ERROR_NONE;
                $display("[CNN_CTRL] CNN Reset");
            end
            
            // SPI Frame start monitoring
            if (spi_frame_start_pulse) begin
                $display("[CNN_CTRL] SPI Frame start detected");
            end
            
            // CNN start handling
            if (cnn_start_pulse) begin
                $display("[CNN_CTRL] CNN start command");
            end
            
            // CNN result handling
            if (cnn_result_valid_pulse) begin
                frame_count_internal <= frame_count_internal + 1;
                $display("[CNN_CTRL] CNN complete - Frame %0d", frame_count_internal + 1);
            end
        end
    end

    // ===== Output Assignments =====
    
    // Direct control assignments
    assign cnn_start = cnn_start_pulse;
    assign cnn_reset = cnn_reset_pulse;
    
    // Status register (SPI 기반)
    assign status_reg = {
        26'b0,                    // Reserved [31:6]
        spi_frame_start,          // SPI_FRAME_START [5]
        spi_pixel_valid,          // SPI_PIXEL_VALID [4]
        cnn_result_valid,         // RESULT_VALID [3]
        cnn_busy,                 // CNN_BUSY [2]
        1'b0,                     // Reserved [1]
        rst_n                     // SYSTEM_READY [0]
    };
    
    // Counter outputs
    assign frame_counter = frame_count_internal;
    assign error_code = error_code_internal;
    assign frame_count_reg = frame_count_internal;
    assign error_code_reg = error_code_internal;

    // ===== SPI Monitoring (디버깅용) =====
    integer spi_pixel_count = 0;
    
    always @(posedge clk) begin
        if (spi_pixel_valid) begin
            spi_pixel_count++;
            if (spi_pixel_count <= 5 || (spi_pixel_count % 200 == 0)) begin
                $display("[CNN_CTRL] SPI Pixel[%0d] received", spi_pixel_count);
            end
        end
        
        if (spi_frame_start_pulse) begin
            spi_pixel_count = 0;
            $display("[CNN_CTRL] SPI Frame started - pixel count reset");
        end
    end

endmodule