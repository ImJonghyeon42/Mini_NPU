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
    
    // ===== Internal Registers (완전 분리) =====
    logic [31:0] frame_count_internal;
    logic [31:0] error_code_internal;
    
    // 완전히 격리된 입력 캡처 레지스터들 (3단계 깊이)
    logic [31:0] control_reg_sync [0:2];
    logic [31:0] pixel_reg_sync [0:2];
    logic cnn_result_valid_sync [0:2];
    
    // 완전히 격리된 출력 레지스터들
    logic cnn_start_reg, cnn_reset_reg, pixel_valid_reg;
    logic frame_start_reg, frame_complete_reg;
    logic [7:0] pixel_data_reg;
    
    // State machine for safe control
    typedef enum logic [2:0] {
        IDLE = 3'b000,
        CAPTURE = 3'b001,
        PROCESS = 3'b010,
        OUTPUT = 3'b011,
        WAIT_CYCLE = 3'b100
    } state_t;
    
    state_t current_state, next_state;

    // ===== 3단계 Deep Synchronization (Complete Isolation) =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            control_reg_sync[0] <= '0;
            control_reg_sync[1] <= '0;
            control_reg_sync[2] <= '0;
            pixel_reg_sync[0] <= '0;
            pixel_reg_sync[1] <= '0;
            pixel_reg_sync[2] <= '0;
            cnn_result_valid_sync[0] <= '0;
            cnn_result_valid_sync[1] <= '0;
            cnn_result_valid_sync[2] <= '0;
        end else begin
            // 3-stage deep pipeline for complete isolation
            control_reg_sync[0] <= control_reg;
            control_reg_sync[1] <= control_reg_sync[0];
            control_reg_sync[2] <= control_reg_sync[1];
            
            pixel_reg_sync[0] <= pixel_reg;
            pixel_reg_sync[1] <= pixel_reg_sync[0];
            pixel_reg_sync[2] <= pixel_reg_sync[1];
            
            cnn_result_valid_sync[0] <= cnn_result_valid;
            cnn_result_valid_sync[1] <= cnn_result_valid_sync[0];
            cnn_result_valid_sync[2] <= cnn_result_valid_sync[1];
        end
    end

    // ===== State Machine =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: 
                next_state = CAPTURE;
            CAPTURE: 
                next_state = PROCESS;
            PROCESS: 
                next_state = OUTPUT;
            OUTPUT: 
                next_state = WAIT_CYCLE;
            WAIT_CYCLE: 
                next_state = IDLE;
            default: 
                next_state = IDLE;
        endcase
    end

    // ===== Safe Edge Detection with State Machine =====
    logic cnn_start_detected, cnn_reset_detected, pixel_valid_detected;
    logic frame_start_detected, frame_complete_detected;
    logic cnn_result_valid_detected;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnn_start_detected <= '0;
            cnn_reset_detected <= '0;
            pixel_valid_detected <= '0;
            frame_start_detected <= '0;
            frame_complete_detected <= '0;
            cnn_result_valid_detected <= '0;
        end else if (current_state == PROCESS) begin
            // Only detect edges in PROCESS state to avoid loops
            cnn_start_detected <= control_reg_sync[2][CTRL_CNN_START] && !control_reg_sync[1][CTRL_CNN_START];
            cnn_reset_detected <= control_reg_sync[2][CTRL_CNN_RESET] && !control_reg_sync[1][CTRL_CNN_RESET];
            pixel_valid_detected <= control_reg_sync[2][CTRL_PIXEL_VALID] && !control_reg_sync[1][CTRL_PIXEL_VALID];
            frame_start_detected <= control_reg_sync[2][CTRL_FRAME_START] && !control_reg_sync[1][CTRL_FRAME_START];
            frame_complete_detected <= control_reg_sync[2][CTRL_FRAME_COMPLETE] && !control_reg_sync[1][CTRL_FRAME_COMPLETE];
            cnn_result_valid_detected <= cnn_result_valid_sync[2] && !cnn_result_valid_sync[1];
        end else begin
            cnn_start_detected <= '0;
            cnn_reset_detected <= '0;
            pixel_valid_detected <= '0;
            frame_start_detected <= '0;
            frame_complete_detected <= '0;
            cnn_result_valid_detected <= '0;
        end
    end

    // ===== Control Logic =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_count_internal <= '0;
            error_code_internal <= ERROR_NONE;
        end else begin
            // Reset handling
            if (cnn_reset_detected) begin
                error_code_internal <= ERROR_NONE;
                $display("[CNN_CTRL] CNN Reset");
            end
            
            // Frame start handling
            if (frame_start_detected) begin
                $display("[CNN_CTRL] Frame start - MicroBlaze controlled");
            end
            
            // CNN start handling
            if (cnn_start_detected) begin
                $display("[CNN_CTRL] CNN start command");
            end
            
            // Pixel handling
            if (pixel_valid_detected) begin
                $display("[CNN_CTRL] Pixel received: 0x%02h", pixel_reg_sync[2][7:0]);
            end
            
            // CNN result handling
            if (cnn_result_valid_detected) begin
                frame_count_internal <= frame_count_internal + 1;
                $display("[CNN_CTRL] CNN complete - Frame %0d", frame_count_internal + 1);
            end
            
            // Frame complete handling
            if (frame_complete_detected) begin
                $display("[CNN_CTRL] Frame complete - MicroBlaze controlled");
            end
        end
    end

    // ===== Completely Isolated Output Stage =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnn_start_reg <= '0;
            cnn_reset_reg <= '0;
            pixel_valid_reg <= '0;
            pixel_data_reg <= '0;
            frame_start_reg <= '0;
            frame_complete_reg <= '0;
        end else if (current_state == OUTPUT) begin
            // Only update outputs in OUTPUT state
            cnn_start_reg <= cnn_start_detected;
            cnn_reset_reg <= cnn_reset_detected;
            pixel_valid_reg <= pixel_valid_detected;
            pixel_data_reg <= pixel_reg_sync[2][7:0];
            frame_start_reg <= frame_start_detected;
            frame_complete_reg <= frame_complete_detected;
        end else begin
            // Clear pulse signals in other states
            cnn_start_reg <= '0;
            cnn_reset_reg <= '0;
            pixel_valid_reg <= '0;
            frame_start_reg <= '0;
            frame_complete_reg <= '0;
            // Keep pixel_data_reg stable
        end
    end

    // ===== Final Output Assignments (No Combinatorial Path Possible) =====
    assign cnn_start = cnn_start_reg;
    assign cnn_reset = cnn_reset_reg;
    assign pixel_valid = pixel_valid_reg;
    assign pixel_data = pixel_data_reg;
    assign frame_start = frame_start_reg;
    assign frame_complete = frame_complete_reg;
    
    // Status register (完全히 독립적)
    assign status_reg = {
        27'b0,                    // Reserved [31:5]
        frame_complete_reg,       // FRAME_COMPLETE [4]
        frame_start_reg,          // FRAME_START [3]
        pixel_valid_reg,          // PIXEL_VALID [2]
        cnn_result_valid_pipe[2], // RESULT_VALID [1]
        cnn_busy                  // CNN_BUSY [0]
    };
    
    // Counter outputs (完全히 독립적)
    assign frame_counter = frame_count_internal;
    assign error_code = error_code_internal;
    assign frame_count_reg = frame_count_internal;
    assign error_code_reg = error_code_internal;

    // ===== Debug Monitoring =====
    integer pixel_count = 0;
    
    always @(posedge clk) begin
        if (pixel_valid_detected) begin
            pixel_count++;
            if (pixel_count <= 5 || (pixel_count % 100 == 0)) begin
                $display("[CNN_CTRL] MicroBlaze Pixel[%0d] = 0x%02h", pixel_count, pixel_data_reg);
            end
        end
        
        if (frame_start_detected) begin
            pixel_count = 0;
            $display("[CNN_CTRL] MicroBlaze Frame started - pixel count reset");
        end
    end

endmodule