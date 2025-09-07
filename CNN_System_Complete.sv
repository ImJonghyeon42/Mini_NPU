// ===== 간소화된 IP 래퍼 (빠른 구현, 테스트벤치 불필요) =====

module IP_CNN_System_Fast(
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
    
    // ===== 제어 신호들 =====
    logic [31:0] pixel_count;
    logic [2:0] motor_command;
    logic image_complete;
    
    // ===== 단순한 상태 머신 =====
    enum logic [2:0] {
        IDLE       = 3'b000,
        RECEIVING  = 3'b001,
        PROCESSING = 3'b010,
        SENDING    = 3'b011,
        DONE       = 3'b100
    } current_state, next_state;

    // ===== IP 인스턴스들 (기존 설정 그대로 사용) =====
    
    // SPI SLAVE IP
    logic [31:0] slave_rx_data_reg;
    logic slave_rx_valid;
    logic [31:0] slave_tx_data_reg;
    logic slave_tx_valid;
    
    axi_quad_spi_0 spi_slave_ip (
        .ext_spi_clk(spi_slave_sclk),
        .s_axi4_aclk(clk),
        .s_axi4_aresetn(rst_n),
        
        // SPI 핀들 (기존 설정)
        .sck_i(spi_slave_sclk),
        .sck_o(),
        .sck_t(),
        .mosi_i(spi_slave_mosi),
        .mosi_o(),
        .mosi_t(),
        .miso_i(1'b0),
        .miso_o(spi_slave_miso),
        .miso_t(),
        .ss_i(spi_slave_ss),
        .ss_o(),
        .ss_t(),
        
        // 최소한의 AXI 연결 (나머지는 기본값)
        .s_axi4_araddr(32'h0),
        .s_axi4_arvalid(1'b0),
        .s_axi4_arready(),
        .s_axi4_rdata(slave_rx_data_reg),
        .s_axi4_rvalid(slave_rx_valid),
        .s_axi4_rready(1'b1),
        .s_axi4_rresp(),
        
        .s_axi4_awaddr(32'h0),
        .s_axi4_awvalid(1'b0),
        .s_axi4_awready(),
        .s_axi4_wdata(slave_tx_data_reg),
        .s_axi4_wvalid(slave_tx_valid),
        .s_axi4_wready(),
        .s_axi4_wstrb(4'hF),
        .s_axi4_bresp(),
        .s_axi4_bvalid(),
        .s_axi4_bready(1'b1),
        
        .ip2intc_irpt()
    );
    
    // SPI MASTER IP  
    logic [31:0] master_tx_data_reg;
    logic master_tx_valid;
    logic master_tx_ready;
    
    axi_quad_spi_1 spi_master_ip (
        .ext_spi_clk(clk),
        .s_axi4_aclk(clk),
        .s_axi4_aresetn(rst_n),
        
        // SPI 핀들 (기존 설정)
        .sck_i(1'b0),
        .sck_o(spi_master_sclk),
        .sck_t(),
        .mosi_i(1'b0),
        .mosi_o(spi_master_mosi),
        .mosi_t(),
        .miso_i(spi_master_miso),
        .miso_o(),
        .miso_t(),
        .ss_i(1'b1),
        .ss_o(spi_master_ss),
        .ss_t(),
        
        // 최소한의 AXI 연결
        .s_axi4_araddr(32'h0),
        .s_axi4_arvalid(1'b0),
        .s_axi4_arready(),
        .s_axi4_rdata(),
        .s_axi4_rvalid(),
        .s_axi4_rready(1'b1),
        .s_axi4_rresp(),
        
        .s_axi4_awaddr(32'h0),
        .s_axi4_awvalid(1'b0),
        .s_axi4_awready(),
        .s_axi4_wdata(master_tx_data_reg),
        .s_axi4_wvalid(master_tx_valid),
        .s_axi4_wready(master_tx_ready),
        .s_axi4_wstrb(4'hF),
        .s_axi4_bresp(),
        .s_axi4_bvalid(),
        .s_axi4_bready(1'b1),
        
        .ip2intc_irpt()
    );

    // ===== CNN 엔진 (수정된 버전) =====
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

    // ===== 간소화된 제어 로직 (복잡한 테스트 불필요) =====
    
    // 상태 전환
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (slave_rx_valid) next_state = RECEIVING;
            end
            RECEIVING: begin
                if (image_complete) next_state = PROCESSING;
            end
            PROCESSING: begin
                if (cnn_result_valid) next_state = SENDING;
            end
            SENDING: begin
                if (master_tx_ready) next_state = DONE;
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
    
    // ===== 픽셀 데이터 처리 (단순화) =====
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
                    if (slave_rx_valid) begin
                        // 간단한 데이터 추출 (8비트만)
                        cnn_pixel_data <= slave_rx_data_reg[7:0];
                        cnn_pixel_valid <= 1;
                        
                        if (pixel_count == 0) begin
                            cnn_start <= 1;
                        end else begin
                            cnn_start <= 0;
                        end
                        
                        pixel_count <= pixel_count + 1;
                        
                        if (pixel_count >= 1023) begin
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
    
    // ===== 모터 명령 생성 및 전송 (매우 단순화) =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            motor_command <= 3'b000;
            master_tx_data_reg <= 32'h0;
            master_tx_valid <= 0;
        end else begin
            case (current_state)
                PROCESSING: begin
                    if (cnn_result_valid) begin
                        // 간단한 결과 분류
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
                    // 모터 명령 전송
                    master_tx_data_reg <= {24'hAA55, 5'b0, motor_command};
                    master_tx_valid <= 1;
                end
                
                default: begin
                    master_tx_valid <= 0;
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