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
    
    // ===== Internal Registers =====
    logic [31:0] frame_count_internal;
    logic [31:0] error_code_internal;
    
    // 안전한 신호 동기화 (3단계)
    logic [31:0] control_reg_d1, control_reg_d2, control_reg_d3;
    logic [31:0] pixel_reg_d1, pixel_reg_d2, pixel_reg_d3;
    logic cnn_result_valid_d1, cnn_result_valid_d2, cnn_result_valid_d3;
    
    // Edge detection 신호들
    logic cnn_start_edge, cnn_reset_edge, pixel_valid_edge;
    logic frame_start_edge, frame_complete_edge, cnn_result_edge;
    
    // 출력 레지스터들
    logic cnn_start_reg, cnn_reset_reg, pixel_valid_reg;
    logic frame_start_reg, frame_complete_reg;
    logic [7:0] pixel_data_reg;

    // ===== 3단계 동기화 (안전한 격리) =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            control_reg_d1 <= '0;
            control_reg_d2 <= '0;
            control_reg_d3 <= '0;
            pixel_reg_d1 <= '0;
            pixel_reg_d2 <= '0;
            pixel_reg_d3 <= '0;
            cnn_result_valid_d1 <= '0;
            cnn_result_valid_d2 <= '0;
            cnn_result_valid_d3 <= '0;
        end else begin
            // 3단계 깊은 파이프라인
            control_reg_d1 <= control_reg;
            control_reg_d2 <= control_reg_d1;
            control_reg_d3 <= control_reg_d2;
            
            pixel_reg_d1 <= pixel_reg;
            pixel_reg_d2 <= pixel_reg_d1;
            pixel_reg_d3 <= pixel_reg_d2;
            
            cnn_result_valid_d1 <= cnn_result_valid;
            cnn_result_valid_d2 <= cnn_result_valid_d1;
            cnn_result_valid_d3 <= cnn_result_valid_d2;
        end
    end

    // ===== Edge Detection (완전 격리) =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnn_start_edge <= '0;
            cnn_reset_edge <= '0;
            pixel_valid_edge <= '0;
            frame_start_edge <= '0;
            frame_complete_edge <= '0;
            cnn_result_edge <= '0;
        end else begin
            cnn_start_edge <= control_reg_d3[CTRL_CNN_START] && !control_reg_d2[CTRL_CNN_START];
            cnn_reset_edge <= control_reg_d3[CTRL_CNN_RESET] && !control_reg_d2[CTRL_CNN_RESET];
            pixel_valid_edge <= control_reg_d3[CTRL_PIXEL_VALID] && !control_reg_d2[CTRL_PIXEL_VALID];
            frame_start_edge <= control_reg_d3[CTRL_FRAME_START] && !control_reg_d2[CTRL_FRAME_START];
            frame_complete_edge <= control_reg_d3[CTRL_FRAME_COMPLETE] && !control_reg_d2[CTRL_FRAME_COMPLETE];
            cnn_result_edge <= cnn_result_valid_d3 && !cnn_result_valid_d2;
        end
    end

    // ===== Control Logic =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_count_internal <= '0;
            error_code_internal <= ERROR_NONE;
        end else begin
            // Reset handling
            if (cnn_reset_edge) begin
                error_code_internal <= ERROR_NONE;
                $display("[CNN_CTRL] CNN Reset");
            end
            
            // Frame start handling
            if (frame_start_edge) begin
                $display("[CNN_CTRL] Frame start - MicroBlaze controlled");
            end
            
            // CNN start handling
            if (cnn_start_edge) begin
                $display("[CNN_CTRL] CNN start command");
            end
            
            // Pixel handling
            if (pixel_valid_edge) begin
                $display("[CNN_CTRL] Pixel received: 0x%02h", pixel_reg_d3[7:0]);
            end
            
            // CNN result handling
            if (cnn_result_edge) begin
                frame_count_internal <= frame_count_internal + 1;
                $display("[CNN_CTRL] CNN complete - Frame %0d", frame_count_internal + 1);
            end
            
            // Frame complete handling
            if (frame_complete_edge) begin
                $display("[CNN_CTRL] Frame complete - MicroBlaze controlled");
            end
        end
    end

    // ===== 출력 레지스터 (완전 격리) =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnn_start_reg <= '0;
            cnn_reset_reg <= '0;
            pixel_valid_reg <= '0;
            pixel_data_reg <= '0;
            frame_start_reg <= '0;
            frame_complete_reg <= '0;
        end else begin
            cnn_start_reg <= cnn_start_edge;
            cnn_reset_reg <= cnn_reset_edge;
            pixel_valid_reg <= pixel_valid_edge;
            pixel_data_reg <= pixel_reg_d3[7:0];
            frame_start_reg <= frame_start_edge;
            frame_complete_reg <= frame_complete_edge;
        end
    end

    // ===== 최종 출력 할당 (조합 논리 없음) =====
    assign cnn_start = cnn_start_reg;
    assign cnn_reset = cnn_reset_reg;
    assign pixel_valid = pixel_valid_reg;
    assign pixel_data = pixel_data_reg;
    assign frame_start = frame_start_reg;
    assign frame_complete = frame_complete_reg;
    
    // Status register (완전 독립적)
    assign status_reg = {
        27'b0,                    // Reserved [31:5]
        frame_complete_reg,       // FRAME_COMPLETE [4]
        frame_start_reg,          // FRAME_START [3]
        pixel_valid_reg,          // PIXEL_VALID [2]
        cnn_result_valid_d3,      // RESULT_VALID [1]
        cnn_busy                  // CNN_BUSY [0]
    };
    
    // Counter outputs (완전 독립적)
    assign frame_counter = frame_count_internal;
    assign error_code = error_code_internal;
    assign frame_count_reg = frame_count_internal;
    assign error_code_reg = error_code_internal;

    // ===== Debug Monitoring =====
    integer pixel_count = 0;
    
    always @(posedge clk) begin
        if (pixel_valid_edge) begin
            pixel_count++;
            if (pixel_count <= 5 || (pixel_count % 100 == 0)) begin
                $display("[CNN_CTRL] MicroBlaze Pixel[%0d] = 0x%02h", pixel_count, pixel_data_reg);
            end
        end
        
        if (frame_start_edge) begin
            pixel_count = 0;
            $display("[CNN_CTRL] MicroBlaze Frame started - pixel count reset");
        end
    end

endmodule