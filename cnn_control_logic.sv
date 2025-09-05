`timescale 1ns/1ps

module cnn_control_logic (
    input logic clk,
    input logic rst_n,
    
    // AXI Control Interface
    input logic [31:0] control_reg,      // Control register from AXI
    output logic [31:0] status_reg,      // Status register to AXI
    output logic [31:0] frame_count_reg, // Frame count register
    output logic [31:0] error_code_reg,  // Error code register
    
    // SPI Interface Status
    input logic spi_frame_start,         // SPI frame start
    input logic spi_frame_complete,      // SPI frame complete
    
    // CNN Interface
    output logic cnn_start,              // Start CNN processing
    output logic cnn_reset,              // Reset CNN
    input logic cnn_busy,                // CNN is busy
    input logic cnn_result_valid,        // CNN result valid
    
    // Output counters
    output logic [31:0] frame_counter,   // Processed frame counter
    output logic [31:0] error_code       // Error code
);

    // ===== Parameters =====
    localparam ERROR_NONE           = 32'h00000000;
    localparam ERROR_SPI_TIMEOUT    = 32'h00000001;  // SPI 데이터 수신 타임아웃
    localparam ERROR_CNN_TIMEOUT    = 32'h00000002;  // CNN 처리 타임아웃
    localparam ERROR_FRAME_OVERRUN  = 32'h00000003;  // 프레임 중복 처리
    localparam ERROR_INVALID_START  = 32'h00000004;  // 잘못된 시작 조건
    localparam ERROR_FIFO_UNDERRUN  = 32'h00000005;  // SPI FIFO 언더런
    
    // 타임아웃 설정 (100MHz 클럭 기준)
    localparam CNN_TIMEOUT_CYCLES   = 500000;   // CNN 타임아웃: 5ms
    localparam SPI_TIMEOUT_CYCLES   = 2000000;  // SPI 타임아웃: 20ms  
    localparam FRAME_INTERVAL_MIN   = 100000;   // 최소 프레임 간격: 1ms
    
    // ===== Internal Signals =====
    logic [31:0] cnn_timeout_counter;
    logic [31:0] spi_timeout_counter;
    logic [31:0] frame_count_internal;
    logic [31:0] error_code_internal;
    
    logic cnn_start_request;
    logic cnn_reset_request;
    logic cnn_start_pulse;
    logic cnn_reset_pulse;
    
    logic spi_frame_start_d1;
    logic spi_frame_complete_d1;
    logic cnn_result_valid_d1;
    
    logic spi_frame_start_pulse;
    logic spi_frame_complete_pulse;
    logic cnn_result_valid_pulse;
    
    enum logic [3:0] {
        IDLE,
        WAIT_SPI_FRAME,
        SPI_RECEIVING,
        START_CNN,
        CNN_PROCESSING,
        CNN_COMPLETE,
        ERROR_STATE
    } state, next_state;

    // ===== Control Register Parsing =====
    assign cnn_start_request = control_reg[0];  // Bit 0: Start CNN
    assign cnn_reset_request = control_reg[1];  // Bit 1: Reset CNN

    // ===== Edge Detection =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_frame_start_d1 <= '0;
            spi_frame_complete_d1 <= '0;
            cnn_result_valid_d1 <= '0;
        end else begin
            spi_frame_start_d1 <= spi_frame_start;
            spi_frame_complete_d1 <= spi_frame_complete;
            cnn_result_valid_d1 <= cnn_result_valid;
        end
    end
    
    assign spi_frame_start_pulse = spi_frame_start && !spi_frame_start_d1;
    assign spi_frame_complete_pulse = spi_frame_complete && !spi_frame_complete_d1;
    assign cnn_result_valid_pulse = cnn_result_valid && !cnn_result_valid_d1;

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
                if (cnn_start_request) begin
                    next_state = WAIT_SPI_FRAME;
                end else if (cnn_reset_request) begin
                    next_state = IDLE;  // Stay in IDLE for reset
                end
            end
            
            WAIT_SPI_FRAME: begin
                if (spi_frame_start_pulse) begin
                    next_state = SPI_RECEIVING;
                end else if (spi_timeout_counter >= SPI_TIMEOUT_CYCLES) begin
                    next_state = ERROR_STATE;
                end else if (!cnn_start_request) begin
                    next_state = IDLE;
                end
            end
            
            SPI_RECEIVING: begin
                if (spi_frame_complete_pulse) begin
                    next_state = START_CNN;
                end else if (spi_timeout_counter >= SPI_TIMEOUT_CYCLES) begin
                    next_state = ERROR_STATE;
                end
            end
            
            START_CNN: begin
                next_state = CNN_PROCESSING;
            end
            
            CNN_PROCESSING: begin
                if (cnn_result_valid_pulse) begin
                    next_state = CNN_COMPLETE;
                end else if (cnn_timeout_counter >= CNN_TIMEOUT_CYCLES) begin
                    next_state = ERROR_STATE;
                end
            end
            
            CNN_COMPLETE: begin
                next_state = IDLE;
            end
            
            ERROR_STATE: begin
                if (cnn_reset_request) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

    // ===== Control Logic =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnn_start_pulse <= '0;
            cnn_reset_pulse <= '0;
            cnn_timeout_counter <= '0;
            spi_timeout_counter <= '0;
            frame_count_internal <= '0;
            error_code_internal <= ERROR_NONE;
        end else begin
            cnn_start_pulse <= '0;
            cnn_reset_pulse <= '0;
            
            // Reset request handling
            if (cnn_reset_request) begin
                cnn_reset_pulse <= '1;
                error_code_internal <= ERROR_NONE;
                cnn_timeout_counter <= '0;
                spi_timeout_counter <= '0;
            end
            
            case (state)
                IDLE: begin
                    cnn_timeout_counter <= '0;
                    spi_timeout_counter <= '0;
                    if (next_state == WAIT_SPI_FRAME) begin
                        $display("[CNN_CTRL] Waiting for SPI frame...");
                    end
                end
                
                WAIT_SPI_FRAME: begin
                    spi_timeout_counter <= spi_timeout_counter + 1;
                    if (next_state == SPI_RECEIVING) begin
                        spi_timeout_counter <= '0;
                        $display("[CNN_CTRL] SPI frame started");
                    end else if (next_state == ERROR_STATE) begin
                        error_code_internal <= ERROR_SPI_TIMEOUT;
                        $display("[CNN_CTRL] ERROR: SPI timeout");
                    end
                end
                
                SPI_RECEIVING: begin
                    spi_timeout_counter <= spi_timeout_counter + 1;
                    if (next_state == START_CNN) begin
                        $display("[CNN_CTRL] SPI frame complete, starting CNN");
                    end else if (next_state == ERROR_STATE) begin
                        error_code_internal <= ERROR_SPI_TIMEOUT;
                    end
                end
                
                START_CNN: begin
                    cnn_start_pulse <= '1;
                    cnn_timeout_counter <= '0;
                    $display("[CNN_CTRL] CNN processing started");
                end
                
                CNN_PROCESSING: begin
                    cnn_timeout_counter <= cnn_timeout_counter + 1;
                    if (next_state == CNN_COMPLETE) begin
                        frame_count_internal <= frame_count_internal + 1;
                        $display("[CNN_CTRL] CNN processing complete - Frame %0d", frame_count_internal + 1);
                    end else if (next_state == ERROR_STATE) begin
                        error_code_internal <= ERROR_CNN_TIMEOUT;
                        $display("[CNN_CTRL] ERROR: CNN timeout");
                    end
                end
                
                CNN_COMPLETE: begin
                    cnn_timeout_counter <= '0;
                end
                
                ERROR_STATE: begin
                    $display("[CNN_CTRL] In error state - Code: 0x%08h", error_code_internal);
                end
            endcase
        end
    end

    // ===== Output Assignments =====
    
    // CNN control signals
    assign cnn_start = cnn_start_pulse;
    assign cnn_reset = cnn_reset_pulse;
    
    // Status register (matches C code definitions)
    assign status_reg = {
        29'b0,                    // Reserved [31:3]
        spi_frame_complete,       // SPI_COMPLETE [2]
        cnn_result_valid,         // RESULT_VALID [1]
        (state == CNN_PROCESSING) // CNN_BUSY [0]
    };
    
    // Counter outputs
    assign frame_counter = frame_count_internal;
    assign error_code = error_code_internal;
    assign frame_count_reg = frame_count_internal;
    assign error_code_reg = error_code_internal;

    // ===== Debug Monitoring =====
    
    always @(posedge clk) begin
        if (state != next_state) begin
            case (next_state)
                IDLE: $display("[CNN_CTRL] State: IDLE");
                WAIT_SPI_FRAME: $display("[CNN_CTRL] State: WAIT_SPI_FRAME");
                SPI_RECEIVING: $display("[CNN_CTRL] State: SPI_RECEIVING");
                START_CNN: $display("[CNN_CTRL] State: START_CNN");
                CNN_PROCESSING: $display("[CNN_CTRL] State: CNN_PROCESSING");
                CNN_COMPLETE: $display("[CNN_CTRL] State: CNN_COMPLETE");
                ERROR_STATE: $display("[CNN_CTRL] State: ERROR_STATE");
            endcase
        end
    end

endmodule