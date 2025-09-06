`timescale 1ns/1ps

module cnn_control_logic_simple (
    input wire clk,
    input wire rst_n,
    
    // AXI Control Interface
    input wire [31:0] control_reg,      // Control register from AXI
    input wire [31:0] pixel_reg,        // Pixel data register from AXI
    output wire [31:0] status_reg,      // Status register to AXI
    output wire [31:0] frame_count_reg, // Frame count register
    output wire [31:0] error_code_reg,  // Error code register
    
    // CNN Interface
    output wire cnn_start,              // Start CNN processing
    output wire cnn_reset,              // Reset CNN
    input wire cnn_busy,                // CNN is busy
    input wire cnn_result_valid,        // CNN result valid
    
    // Pixel Interface (MicroBlaze controlled)
    output wire pixel_valid,            // Valid pixel data
    output wire [7:0] pixel_data,       // Pixel data to CNN
    output wire frame_start,            // Frame start signal
    output wire frame_complete,         // Frame complete signal
    
    // Output counters
    output wire [31:0] frame_counter,   // Processed frame counter
    output wire [31:0] error_code       // Error code
);

    // ===== Parameters =====
    parameter ERROR_NONE           = 32'h00000000;
    parameter ERROR_CNN_TIMEOUT    = 32'h00000001;
    parameter ERROR_INVALID_START  = 32'h00000002;
    
    // Control register bit definitions
    parameter CTRL_CNN_START       = 0;    // Bit 0: Start CNN
    parameter CTRL_CNN_RESET       = 1;    // Bit 1: Reset CNN
    parameter CTRL_PIXEL_VALID     = 2;    // Bit 2: Pixel valid
    parameter CTRL_FRAME_START     = 3;    // Bit 3: Frame start
    parameter CTRL_FRAME_COMPLETE  = 4;    // Bit 4: Frame complete
    
    // ===== Internal Registers =====
    reg [31:0] frame_count_internal;
    reg [31:0] error_code_internal;
    
    // 이전 상태 저장용 레지스터들 (조합 논리 루프 방지)
    reg [31:0] control_reg_prev;
    reg [31:0] pixel_reg_prev;
    reg cnn_result_valid_prev;
    
    // 출력 레지스터들
    reg output_cnn_start;
    reg output_cnn_reset;
    reg output_pixel_valid;
    reg output_frame_start;
    reg output_frame_complete;
    reg [7:0] output_pixel_data;

    // ===== 순차 논리로만 구현 (조합 논리 루프 방지) =====
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 초기화
            control_reg_prev <= 32'h0;
            pixel_reg_prev <= 32'h0;
            cnn_result_valid_prev <= 1'b0;
            frame_count_internal <= 32'h0;
            error_code_internal <= ERROR_NONE;
            
            // 출력 초기화
            output_cnn_start <= 1'b0;
            output_cnn_reset <= 1'b0;
            output_pixel_valid <= 1'b0;
            output_frame_start <= 1'b0;
            output_frame_complete <= 1'b0;
            output_pixel_data <= 8'h0;
        end else begin
            // Edge detection and pulse generation
            output_cnn_start <= control_reg[CTRL_CNN_START] & ~control_reg_prev[CTRL_CNN_START];
            output_cnn_reset <= control_reg[CTRL_CNN_RESET] & ~control_reg_prev[CTRL_CNN_RESET];
            output_pixel_valid <= control_reg[CTRL_PIXEL_VALID] & ~control_reg_prev[CTRL_PIXEL_VALID];
            output_frame_start <= control_reg[CTRL_FRAME_START] & ~control_reg_prev[CTRL_FRAME_START];
            output_frame_complete <= control_reg[CTRL_FRAME_COMPLETE] & ~control_reg_prev[CTRL_FRAME_COMPLETE];
            
            // Pixel data update
            output_pixel_data <= pixel_reg[7:0];
            
            // Reset error on reset command
            if (control_reg[CTRL_CNN_RESET] & ~control_reg_prev[CTRL_CNN_RESET]) begin
                error_code_internal <= ERROR_NONE;
            end
            
            // Frame counter increment on CNN result valid edge
            if (cnn_result_valid & ~cnn_result_valid_prev) begin
                frame_count_internal <= frame_count_internal + 1;
            end
            
            // Previous state update (at the end to avoid combinational loops)
            control_reg_prev <= control_reg;
            pixel_reg_prev <= pixel_reg;
            cnn_result_valid_prev <= cnn_result_valid;
        end
    end

    // ===== 출력 할당 (단순 wire 연결) =====
    assign cnn_start = output_cnn_start;
    assign cnn_reset = output_cnn_reset;
    assign pixel_valid = output_pixel_valid;
    assign pixel_data = output_pixel_data;
    assign frame_start = output_frame_start;
    assign frame_complete = output_frame_complete;
    
    // Status register (조합 논리)
    assign status_reg = {
        27'b0,                    // Reserved [31:5]
        output_frame_complete,    // FRAME_COMPLETE [4]
        output_frame_start,       // FRAME_START [3]
        output_pixel_valid,       // PIXEL_VALID [2]
        cnn_result_valid,         // RESULT_VALID [1]
        cnn_busy                  // CNN_BUSY [0]
    };
    
    // Counter outputs
    assign frame_counter = frame_count_internal;
    assign error_code = error_code_internal;
    assign frame_count_reg = frame_count_internal;
    assign error_code_reg = error_code_internal;

endmodule