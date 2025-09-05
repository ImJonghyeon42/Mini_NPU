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
    
    // 입력 신호 격리 (이름 충돌 방지)
    reg [31:0] ctrl_sync_stage1, ctrl_sync_stage2;
    reg [31:0] pixel_sync_stage1, pixel_sync_stage2;
    reg result_sync_stage1, result_sync_stage2, result_sync_stage3;
    
    // Edge detection (완전히 다른 이름)
    reg start_edge_detect, reset_edge_detect, pixel_edge_detect;
    reg frame_start_detect, frame_end_detect, result_done_detect;
    
    // 출력 드라이버 (완전 분리)
    reg cnn_start_driver, cnn_reset_driver, pixel_valid_driver;
    reg frame_start_driver, frame_complete_driver;
    reg [7:0] pixel_data_driver;

    // ===== 안전한 입력 동기화 (Multiple Driver 방지) =====
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_sync_stage1 <= 32'h0;
            ctrl_sync_stage2 <= 32'h0;
            pixel_sync_stage1 <= 32'h0;
            pixel_sync_stage2 <= 32'h0;
            result_sync_stage1 <= 1'b0;
            result_sync_stage2 <= 1'b0;
            result_sync_stage3 <= 1'b0;
        end else begin
            // 입력 신호를 완전히 다른 이름으로 캡처
            ctrl_sync_stage1 <= control_reg;
            ctrl_sync_stage2 <= ctrl_sync_stage1;
            
            pixel_sync_stage1 <= pixel_reg;
            pixel_sync_stage2 <= pixel_sync_stage1;
            
            // CNN 결과 신호도 완전히 다른 이름으로
            result_sync_stage1 <= cnn_result_valid;
            result_sync_stage2 <= result_sync_stage1;
            result_sync_stage3 <= result_sync_stage2;
        end
    end

    // ===== Edge Detection (조합 논리 최소화) =====
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_edge_detect <= 1'b0;
            reset_edge_detect <= 1'b0;
            pixel_edge_detect <= 1'b0;
            frame_start_detect <= 1'b0;
            frame_end_detect <= 1'b0;
            result_done_detect <= 1'b0;
        end else begin
            start_edge_detect <= ctrl_sync_stage2[CTRL_CNN_START] & ~ctrl_sync_stage1[CTRL_CNN_START];
            reset_edge_detect <= ctrl_sync_stage2[CTRL_CNN_RESET] & ~ctrl_sync_stage1[CTRL_CNN_RESET];
            pixel_edge_detect <= ctrl_sync_stage2[CTRL_PIXEL_VALID] & ~ctrl_sync_stage1[CTRL_PIXEL_VALID];
            frame_start_detect <= ctrl_sync_stage2[CTRL_FRAME_START] & ~ctrl_sync_stage1[CTRL_FRAME_START];
            frame_end_detect <= ctrl_sync_stage2[CTRL_FRAME_COMPLETE] & ~ctrl_sync_stage1[CTRL_FRAME_COMPLETE];
            result_done_detect <= result_sync_stage3 & ~result_sync_stage2;
        end
    end

    // ===== Control Logic =====
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_count_internal <= 32'h0;
            error_code_internal <= ERROR_NONE;
        end else begin
            if (reset_edge_detect) begin
                error_code_internal <= ERROR_NONE;
            end
            
            if (result_done_detect) begin
                frame_count_internal <= frame_count_internal + 1;
            end
        end
    end

    // ===== 출력 드라이버 (Multiple Driver 방지) =====
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnn_start_driver <= 1'b0;
            cnn_reset_driver <= 1'b0;
            pixel_valid_driver <= 1'b0;
            pixel_data_driver <= 8'h0;
            frame_start_driver <= 1'b0;
            frame_complete_driver <= 1'b0;
        end else begin
            cnn_start_driver <= start_edge_detect;
            cnn_reset_driver <= reset_edge_detect;
            pixel_valid_driver <= pixel_edge_detect;
            pixel_data_driver <= pixel_sync_stage2[7:0];
            frame_start_driver <= frame_start_detect;
            frame_complete_driver <= frame_end_detect;
        end
    end

    // ===== 최종 출력 할당 (단일 Driver 보장) =====
    assign cnn_start = cnn_start_driver;
    assign cnn_reset = cnn_reset_driver;
    assign pixel_valid = pixel_valid_driver;
    assign pixel_data = pixel_data_driver;
    assign frame_start = frame_start_driver;
    assign frame_complete = frame_complete_driver;
    
    // Status register (읽기 전용, Driver 충돌 없음)
    assign status_reg = {
        27'b0,                    // Reserved [31:5]
        frame_complete_driver,    // FRAME_COMPLETE [4]
        frame_start_driver,       // FRAME_START [3]
        pixel_valid_driver,       // PIXEL_VALID [2]
        result_sync_stage3,       // RESULT_VALID [1]
        cnn_busy                  // CNN_BUSY [0]
    };
    
    // Counter outputs (읽기 전용)
    assign frame_counter = frame_count_internal;
    assign error_code = error_code_internal;
    assign frame_count_reg = frame_count_internal;
    assign error_code_reg = error_code_internal;

endmodule