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
    
    // Safe edge detection registers - 2단계로 안전하게 처리
    logic [31:0] control_reg_d1, control_reg_d2;
    logic cnn_result_valid_d1, cnn_result_valid_d2;
    
    // Pulse generation - 완전히 분리된 신호들
    logic cnn_start_internal, cnn_reset_internal, pixel_valid_internal;
    logic frame_start_internal, frame_complete_internal;

    // ===== 안전한 Edge Detection (2단계 지연) =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            control_reg_d1 <= '0;
            control_reg_d2 <= '0;
            cnn_result_valid_d1 <= '0;
            cnn_result_valid_d2 <= '0;
        end else begin
            control_reg_d1 <= control_reg;
            control_reg_d2 <= control_reg_d1;
            cnn_result_valid_d1 <= cnn_result_valid;
            cnn_result_valid_d2 <= cnn_result_valid_d1;
        end
    end

    // ===== 안전한 Pulse 생성 (Combinatorial Loop 방지) =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnn_start_internal <= '0;
            cnn_reset_internal <= '0;
            pixel_valid_internal <= '0;
            frame_start_internal <= '0;
            frame_complete_internal <= '0;
        end else begin
            // Rising edge detection with 2-stage delay for safety
            cnn_start_internal <= control_reg_d1[CTRL_CNN_START] && !control_reg_d2[CTRL_CNN_START];
            cnn_reset_internal <= control_reg_d1[CTRL_CNN_RESET] && !control_reg_d2[CTRL_CNN_RESET];
            pixel_valid_internal <= control_reg_d1[CTRL_PIXEL_VALID] && !control_reg_d2[CTRL_PIXEL_VALID];
            frame_start_internal <= control_reg_d1[CTRL_FRAME_START] && !control_reg_d2[CTRL_FRAME_START];
            frame_complete_internal <= control_reg_d1[CTRL_FRAME_COMPLETE] && !control_reg_d2[CTRL_FRAME_COMPLETE];
        end
    end

    // ===== CNN Result Edge Detection =====
    logic cnn_result_valid_pulse;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnn_result_valid_pulse <= '0;
        end else begin
            cnn_result_valid_pulse <= cnn_result_valid_d1 && !cnn_result_valid_d2;
        end
    end

    // ===== Control Logic =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_count_internal <= '0;
            error_code_internal <= ERROR_NONE;
        end else begin
            // Reset handling
            if (cnn_reset_internal) begin
                error_code_internal <= ERROR_NONE;
                $display("[CNN_CTRL] CNN Reset");
            end
            
            // Frame start handling
            if (frame_start_internal) begin
                $display("[CNN_CTRL] Frame start - MicroBlaze controlled");
            end
            
            // CNN start handling
            if (cnn_start_internal) begin
                $display("[CNN_CTRL] CNN start command");
            end
            
            // Pixel handling
            if (pixel_valid_internal) begin
                $display("[CNN_CTRL] Pixel received: 0x%02h", pixel_reg[7:0]);
            end
            
            // CNN result handling
            if (cnn_result_valid_pulse) begin
                frame_count_internal <= frame_count_internal + 1;
                $display("[CNN_CTRL] CNN complete - Frame %0d", frame_count_internal + 1);
            end
            
            // Frame complete handling
            if (frame_complete_internal) begin
                $display("[CNN_CTRL] Frame complete - MicroBlaze controlled");
            end
        end
    end

    // ===== 완전히 분리된 Output Assignments (No Combinatorial Path) =====
    
    // Sequential output으로 변경하여 combinatorial loop 완전 차단
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnn_start <= '0;
            cnn_reset <= '0;
            pixel_valid <= '0;
            pixel_data <= '0;
            frame_start <= '0;
            frame_complete <= '0;
        end else begin
            cnn_start <= cnn_start_internal;
            cnn_reset <= cnn_reset_internal;
            pixel_valid <= pixel_valid_internal;
            pixel_data <= pixel_reg[7:0];  // LSB 8-bit
            frame_start <= frame_start_internal;
            frame_complete <= frame_complete_internal;
        end
    end
    
    // Status register (Read-only, no feedback possible)
    assign status_reg = {
        27'b0,                    // Reserved [31:5]
        frame_complete_internal,  // FRAME_COMPLETE [4]
        frame_start_internal,     // FRAME_START [3]
        pixel_valid_internal,     // PIXEL_VALID [2]
        cnn_result_valid,         // RESULT_VALID [1]
        cnn_busy                  // CNN_BUSY [0]
    };
    
    // Counter outputs (Read-only)
    assign frame_counter = frame_count_internal;
    assign error_code = error_code_internal;
    assign frame_count_reg = frame_count_internal;
    assign error_code_reg = error_code_internal;

    // ===== Debug Monitoring =====
    integer pixel_count = 0;
    
    always @(posedge clk) begin
        if (pixel_valid_internal) begin
            pixel_count++;
            if (pixel_count <= 5 || (pixel_count % 100 == 0)) begin
                $display("[CNN_CTRL] MicroBlaze Pixel[%0d] = 0x%02h", pixel_count, pixel_data);
            end
        end
        
        if (frame_start_internal) begin
            pixel_count = 0;
            $display("[CNN_CTRL] MicroBlaze Frame started - pixel count reset");
        end
    end

endmodule