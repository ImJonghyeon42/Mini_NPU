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
    
    // CNN Interface (INPUT ONLY - NO DRIVING)
    output wire cnn_start,              // Start CNN processing
    output wire cnn_reset,              // Reset CNN
    input wire cnn_busy,                // CNN is busy
    input wire cnn_result_valid,        // CNN result valid (INPUT ONLY)
    
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
    
    // 입력 신호만 동기화 (출력 신호는 절대 건드리지 않음)
    reg [31:0] control_sync1, control_sync2;
    reg [31:0] pixel_sync1, pixel_sync2;
    
    // CNN 결과는 edge detection만 (재구동 절대 금지)
    reg cnn_valid_prev1, cnn_valid_prev2;
    wire cnn_valid_edge;
    
    // Control edge detection
    wire start_cmd, reset_cmd, pixel_cmd, frame_start_cmd, frame_end_cmd;
    
    // 출력 레지스터들 (완전 분리된 이름)
    reg output_cnn_start, output_cnn_reset, output_pixel_valid;
    reg output_frame_start, output_frame_complete;
    reg [7:0] output_pixel_data;

    // ===== 입력 신호 동기화만 (출력은 절대 건드리지 않음) =====
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            control_sync1 <= 32'h0;
            control_sync2 <= 32'h0;
            pixel_sync1 <= 32'h0;
            pixel_sync2 <= 32'h0;
            cnn_valid_prev1 <= 1'b0;
            cnn_valid_prev2 <= 1'b0;
        end else begin
            // Control register 동기화
            control_sync1 <= control_reg;
            control_sync2 <= control_sync1;
            
            // Pixel register 동기화
            pixel_sync1 <= pixel_reg;
            pixel_sync2 <= pixel_sync1;
            
            // CNN result valid는 edge detection만 (재구동 금지)
            cnn_valid_prev1 <= cnn_result_valid;
            cnn_valid_prev2 <= cnn_valid_prev1;
        end
    end

    // ===== Edge Detection (조합 논리) =====
    assign start_cmd = control_sync2[CTRL_CNN_START] & ~control_sync1[CTRL_CNN_START];
    assign reset_cmd = control_sync2[CTRL_CNN_RESET] & ~control_sync1[CTRL_CNN_RESET];
    assign pixel_cmd = control_sync2[CTRL_PIXEL_VALID] & ~control_sync1[CTRL_PIXEL_VALID];
    assign frame_start_cmd = control_sync2[CTRL_FRAME_START] & ~control_sync1[CTRL_FRAME_START];
    assign frame_end_cmd = control_sync2[CTRL_FRAME_COMPLETE] & ~control_sync1[CTRL_FRAME_COMPLETE];
    assign cnn_valid_edge = cnn_valid_prev1 & ~cnn_valid_prev2;

    // ===== Internal Logic =====
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_count_internal <= 32'h0;
            error_code_internal <= ERROR_NONE;
        end else begin
            if (reset_cmd) begin
                error_code_internal <= ERROR_NONE;
            end
            
            if (cnn_valid_edge) begin
                frame_count_internal <= frame_count_internal + 1;
            end
        end
    end

    // ===== 출력 생성 (완전 분리) =====
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_cnn_start <= 1'b0;
            output_cnn_reset <= 1'b0;
            output_pixel_valid <= 1'b0;
            output_pixel_data <= 8'h0;
            output_frame_start <= 1'b0;
            output_frame_complete <= 1'b0;
        end else begin
            // Pulse signals (1 cycle only)
            output_cnn_start <= start_cmd;
            output_cnn_reset <= reset_cmd;
            output_pixel_valid <= pixel_cmd;
            output_frame_start <= frame_start_cmd;
            output_frame_complete <= frame_end_cmd;
            
            // Data signal (stable)
            output_pixel_data <= pixel_sync2[7:0];
        end
    end

    // ===== 최종 출력 (단일 드라이버) =====
    assign cnn_start = output_cnn_start;
    assign cnn_reset = output_cnn_reset;
    assign pixel_valid = output_pixel_valid;
    assign pixel_data = output_pixel_data;
    assign frame_start = output_frame_start;
    assign frame_complete = output_frame_complete;
    
    // Status register (읽기 전용, 절대 구동하지 않음)
    assign status_reg = {
        27'b0,                    // Reserved [31:5]
        output_frame_complete,    // FRAME_COMPLETE [4]
        output_frame_start,       // FRAME_START [3]
        output_pixel_valid,       // PIXEL_VALID [2]
        cnn_result_valid,         // RESULT_VALID [1] - 원본 사용 (재구동 금지)
        cnn_busy                  // CNN_BUSY [0] - 원본 사용 (재구동 금지)
    };
    
    // Counter outputs
    assign frame_counter = frame_count_internal;
    assign error_code = error_code_internal;
    assign frame_count_reg = frame_count_internal;
    assign error_code_reg = error_code_internal;

endmodule