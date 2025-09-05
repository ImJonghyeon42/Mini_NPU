`timescale 1ns/1ps

module cnn_control_logic_simple (
    input logic clk,
    input logic rst_n,
    
    // AXI Control Interface
    input logic [31:0] control_reg,      // Control register from AXI
    input logic [31:0] pixel_reg,        // Pixel data register from AXI
    output logic [31:0] status_reg,      // Status register to AXI
    output logic [31:0] frame_count_reg, // Frame count register
    output logic [31:0] error_code_reg,  // Error code register
    
    // CNN Interface
    output logic cnn_start,              // Start CNN processing
    output logic cnn_reset,              // Reset CNN
    input logic cnn_busy,                // CNN is busy
    input logic cnn_result_valid,        // CNN result valid
    
    // Pixel Interface (MicroBlaze controlled)
    output logic pixel_valid,            // Valid pixel data
    output logic [7:0] pixel_data,       // Pixel data to CNN
    output logic frame_start,            // Frame start signal
    output logic frame_complete,         // Frame complete signal
    
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
    localparam CTRL_PIXEL_VALID     = 2;    // Bit 2: Pixel valid
    localparam CTRL_FRAME_START     = 3;    // Bit 3: Frame start
    localparam CTRL_FRAME_COMPLETE  = 4;    // Bit 4: Frame complete
    
    // ===== Internal Signals =====
    logic [31:0] frame_count_internal;
    logic [31:0] error_code_internal;
    
    logic cnn_start_d1, cnn_reset_d1, pixel_valid_d1;
    logic frame_start_d1, frame_complete_d1;
    
    logic cnn_start_pulse, cnn_reset_pulse, pixel_valid_pulse;
    logic frame_start_pulse, frame_complete_pulse;
    
    logic cnn_result_valid_d1;
    logic cnn_result_valid_pulse;

    // ===== Edge Detection =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnn_start_d1 <= '0;
            cnn_reset_d1 <= '0;
            pixel_valid_d1 <= '0;
            frame_start_d1 <= '0;
            frame_complete_d1 <= '0;
            cnn_result_valid_d1 <= '0;
        end else begin
            cnn_start_d1 <= control_reg[CTRL_CNN_START];
            cnn_reset_d1 <= control_reg[CTRL_CNN_RESET];
            pixel_valid_d1 <= control_reg[CTRL_PIXEL_VALID];
            frame_start_d1 <= control_reg[CTRL_FRAME_START];
            frame_complete_d1 <= control_reg[CTRL_FRAME_COMPLETE];
            cnn_result_valid_d1 <= cnn_result_valid;
        end
    end
    
    assign cnn_start_pulse = control_reg[CTRL_CNN_START] && !cnn_start_d1;
    assign cnn_reset_pulse = control_reg[CTRL_CNN_RESET] && !cnn_reset_d1;
    assign pixel_valid_pulse = control_reg[CTRL_PIXEL_VALID] && !pixel_valid_d1;
    assign frame_start_pulse = control_reg[CTRL_FRAME_START] && !frame_start_d1;
    assign frame_complete_pulse = control_reg[CTRL_FRAME_COMPLETE] && !frame_complete_d1;
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
                $display("[CNN_CTRL_SIMPLE] CNN Reset");
            end
            
            // Frame start handling
            if (frame_start_pulse) begin
                $display("[CNN_CTRL_SIMPLE] Frame start");
            end
            
            // CNN start handling
            if (cnn_start_pulse) begin
                $display("[CNN_CTRL_SIMPLE] CNN start");
            end
            
            // CNN result handling
            if (cnn_result_valid_pulse) begin
                frame_count_internal <= frame_count_internal + 1;
                $display("[CNN_CTRL_SIMPLE] CNN complete - Frame %0d", frame_count_internal + 1);
            end
            
            // Frame complete handling
            if (frame_complete_pulse) begin
                $display("[CNN_CTRL_SIMPLE] Frame complete");
            end
        end
    end

    // ===== Output Assignments =====
    
    // Direct control assignments
    assign cnn_start = cnn_start_pulse;
    assign cnn_reset = cnn_reset_pulse;
    
    // Pixel interface (직접 MicroBlaze 제어)
    assign pixel_valid = pixel_valid_pulse;
    assign pixel_data = pixel_reg[7:0];  // LSB 8-bit
    assign frame_start = frame_start_pulse;
    assign frame_complete = frame_complete_pulse;
    
    // Status register
    assign status_reg = {
        27'b0,                    // Reserved [31:5]
        frame_complete_pulse,     // FRAME_COMPLETE [4]
        frame_start_pulse,        // FRAME_START [3]
        pixel_valid_pulse,        // PIXEL_VALID [2]
        cnn_result_valid,         // RESULT_VALID [1]
        cnn_busy                  // CNN_BUSY [0]
    };
    
    // Counter outputs
    assign frame_counter = frame_count_internal;
    assign error_code = error_code_internal;
    assign frame_count_reg = frame_count_internal;
    assign error_code_reg = error_code_internal;

    // ===== Debug Monitoring =====
    integer pixel_count = 0;
    
    always @(posedge clk) begin
        if (pixel_valid_pulse) begin
            pixel_count++;
            if (pixel_count <= 5 || (pixel_count % 100 == 0)) begin
                $display("[CNN_CTRL_SIMPLE] Pixel[%0d] = 0x%02h", pixel_count, pixel_data);
            end
        end
        
        if (frame_start_pulse) begin
            pixel_count = 0;
        end
    end

endmodule