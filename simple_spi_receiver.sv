module CNN_System_Simple_SPI(
    input logic clk,
    input logic rst_n,
    
    // SPI SLAVE - 라즈베리파이로부터 이미지 수신
    input logic spi_slave_sclk,   
    input logic spi_slave_mosi,   
    output logic spi_slave_miso,  
    input logic spi_slave_ss,     
    
    // SPI MASTER - 모터보드로 명령 전송  
    output logic spi_master_sclk, 
    output logic spi_master_mosi, 
    input logic spi_master_miso,  
    output logic spi_master_ss,   
    
    // 상태 LED
    output logic [3:0] status_led
);

    // ===== CNN 관련 신호들 =====
    logic cnn_start;
    logic cnn_pixel_valid;
    logic [7:0] cnn_pixel_data;
    logic cnn_busy;
    logic cnn_result_valid;
    logic signed [47:0] cnn_result;
    
    // ===== SPI 관련 신호들 =====
    logic [7:0] spi_rx_data;
    logic spi_rx_valid;
    logic [7:0] spi_tx_data;
    logic spi_tx_start, spi_tx_busy;
    
    // ===== 제어 신호들 =====
    logic [31:0] pixel_count;
    logic [2:0] motor_command;
    logic image_complete;
    
    // ===== 상태 머신 =====
    enum logic [2:0] {
        IDLE       = 3'b000,
        RECEIVING  = 3'b001,
        PROCESSING = 3'b010,
        SENDING    = 3'b011,
        DONE       = 3'b100
    } current_state, next_state;

    // ===== 간단한 SPI SLAVE 모듈 =====
    simple_spi_slave spi_slave_inst (
        .clk(clk),
        .rst_n(rst_n),
        .spi_clk(spi_slave_sclk),
        .spi_mosi(spi_slave_mosi),
        .spi_miso(spi_slave_miso),
        .spi_ss(spi_slave_ss),
        .rx_data(spi_rx_data),
        .rx_valid(spi_rx_valid)
    );
    
    // ===== 간단한 SPI MASTER 모듈 =====
    simple_spi_master spi_master_inst (
        .clk(clk),
        .rst_n(rst_n),
        .spi_clk(spi_master_sclk),
        .spi_mosi(spi_master_mosi),
        .spi_miso(spi_master_miso),
        .spi_ss(spi_master_ss),
        .tx_data(spi_tx_data),
        .tx_start(spi_tx_start),
        .tx_busy(spi_tx_busy)
    );

    // ===== CNN 엔진 =====
    CNN_TOP_Improved cnn_engine (
        .clk(clk),
        .rst(rst_n),
        .start_signal(cnn_start),
        .pixel_valid(cnn_pixel_valid),
        .pixel_in(cnn_pixel_data),
        .final_result_valid(cnn_result_valid),
        .final_lane_result(cnn_result),
        .cnn_busy(cnn_busy)
    );

    // ===== 상태 전환 =====
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (spi_rx_valid) next_state = RECEIVING;
            end
            RECEIVING: begin
                if (image_complete) next_state = PROCESSING;
            end
            PROCESSING: begin
                if (cnn_result_valid) next_state = SENDING;
            end
            SENDING: begin
                if (!spi_tx_busy) next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // ===== 픽셀 데이터 처리 =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_count <= 0;
            cnn_start <= 0;
            cnn_pixel_valid <= 0;
            cnn_pixel_data <= 0;
            image_complete <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    pixel_count <= 0;
                    image_complete <= 0;
                    cnn_start <= 0;
                end
                
                RECEIVING: begin
                    if (spi_rx_valid) begin
                        cnn_pixel_data <= spi_rx_data;
                        cnn_pixel_valid <= 1;
                        
                        if (pixel_count == 0) begin
                            cnn_start <= 1;
                        end else begin
                            cnn_start <= 0;
                        end
                        
                        pixel_count <= pixel_count + 1;
                        
                        if (pixel_count >= 1023) begin // 32x32 = 1024
                            image_complete <= 1;
                        end
                    end else begin
                        cnn_pixel_valid <= 0;
                        cnn_start <= 0;
                    end
                end
                
                default: begin
                    cnn_pixel_valid <= 0;
                    cnn_start <= 0;
                end
            endcase
        end
    end
    
    // ===== 모터 명령 생성 및 전송 =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            motor_command <= 3'b000;
            spi_tx_data <= 8'h00;
            spi_tx_start <= 0;
        end else begin
            case (current_state)
                PROCESSING: begin
                    if (cnn_result_valid) begin
                        // 간단한 결과 분석
                        if (cnn_result > 0) begin
                            motor_command <= 3'b001;  // 우회전
                        end else if (cnn_result < 0) begin
                            motor_command <= 3'b010;  // 좌회전
                        end else begin
                            motor_command <= 3'b000;  // 정지
                        end
                    end
                end
                
                SENDING: begin
                    if (!spi_tx_busy && !spi_tx_start) begin
                        spi_tx_data <= {5'b10101, motor_command}; // 프리앰블 + 명령
                        spi_tx_start <= 1;
                    end else begin
                        spi_tx_start <= 0;
                    end
                end
                
                default: begin
                    spi_tx_start <= 0;
                end
            endcase
        end
    end
    
    // ===== 상태 표시 =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            status_led <= 4'b0001;
        end else begin
            case (current_state)
                IDLE:       status_led <= 4'b0001;
                RECEIVING:  status_led <= 4'b0010;
                PROCESSING: status_led <= 4'b0100;
                SENDING:    status_led <= 4'b1000;
                DONE:       status_led <= 4'b1111;
            endcase
        end
    end

endmodule

// ===== 간단한 SPI SLAVE 모듈 =====
module simple_spi_slave(
    input logic clk, rst_n,
    input logic spi_clk, spi_mosi, spi_ss,
    output logic spi_miso,
    output logic [7:0] rx_data,
    output logic rx_valid
);

    logic [7:0] shift_reg;
    logic [2:0] bit_count;
    logic spi_clk_d1, spi_clk_d2;
    logic spi_ss_d1, spi_ss_d2;
    logic spi_clk_rising, spi_ss_falling;

    // SPI 클럭 엣지 검출
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk_d1 <= 0;
            spi_clk_d2 <= 0;
            spi_ss_d1 <= 1;
            spi_ss_d2 <= 1;
        end else begin
            spi_clk_d1 <= spi_clk;
            spi_clk_d2 <= spi_clk_d1;
            spi_ss_d1 <= spi_ss;
            spi_ss_d2 <= spi_ss_d1;
        end
    end

    assign spi_clk_rising = spi_clk_d1 && !spi_clk_d2;
    assign spi_ss_falling = !spi_ss_d1 && spi_ss_d2;

    // SPI 수신 로직
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 8'h00;
            bit_count <= 0;
            rx_data <= 8'h00;
            rx_valid <= 0;
        end else begin
            rx_valid <= 0;
            
            if (spi_ss_falling) begin
                bit_count <= 0;
                shift_reg <= 8'h00;
            end else if (!spi_ss && spi_clk_rising) begin
                shift_reg <= {shift_reg[6:0], spi_mosi};
                bit_count <= bit_count + 1;
                
                if (bit_count == 7) begin
                    rx_data <= {shift_reg[6:0], spi_mosi};
                    rx_valid <= 1;
                    bit_count <= 0;
                end
            end
        end
    end

    assign spi_miso = 1'b0; // 간단히 0으로 고정

endmodule

// ===== 간단한 SPI MASTER 모듈 =====
module simple_spi_master(
    input logic clk, rst_n,
    output logic spi_clk, spi_mosi, spi_ss,
    input logic spi_miso,
    input logic [7:0] tx_data,
    input logic tx_start,
    output logic tx_busy
);

    logic [7:0] shift_reg;
    logic [2:0] bit_count;
    logic [7:0] clk_div;
    logic spi_clk_en;

    // SPI 클럭 생성 (시스템 클럭/256)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div <= 0;
            spi_clk_en <= 0;
        end else begin
            clk_div <= clk_div + 1;
            spi_clk_en <= (clk_div == 8'hFF);
        end
    end

    // SPI 전송 로직
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 8'h00;
            bit_count <= 0;
            tx_busy <= 0;
            spi_clk <= 0;
            spi_mosi <= 0;
            spi_ss <= 1;
        end else begin
            if (tx_start && !tx_busy) begin
                shift_reg <= tx_data;
                bit_count <= 0;
                tx_busy <= 1;
                spi_ss <= 0;
            end else if (tx_busy && spi_clk_en) begin
                spi_clk <= ~spi_clk;
                
                if (spi_clk) begin // falling edge에서 데이터 변경
                    spi_mosi <= shift_reg[7];
                    shift_reg <= {shift_reg[6:0], 1'b0};
                    bit_count <= bit_count + 1;
                    
                    if (bit_count == 7) begin
                        tx_busy <= 0;
                        spi_ss <= 1;
                        spi_clk <= 0;
                    end
                end
            end
        end
    end

endmodule