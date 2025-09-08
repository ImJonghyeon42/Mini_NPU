module IP_CNN_System_WithTest(
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
    output logic [3:0] status_led,
    
    // 테스트 전용 인터페이스
    input logic test_mode,        
    input logic test_pixel_valid, 
    input logic [7:0] test_pixel_data
);

    // ===== CNN 관련 신호들 =====
    logic cnn_start;
    logic cnn_pixel_valid;
    logic [7:0] cnn_pixel_data;
    logic cnn_busy;
    logic cnn_result_valid;
    logic signed [47:0] cnn_result;
    
    // ===== SPI Slave 신호들 =====
    logic [7:0] spi_rx_data;
    logic spi_rx_valid;
    
    // ===== 테스트 모드 신호 선택 =====
    logic [7:0] rx_data;
    logic rx_valid;
    
    always_comb begin
        if (test_mode) begin
            rx_data = test_pixel_data;
            rx_valid = test_pixel_valid;
        end else begin
            rx_data = spi_rx_data;
            rx_valid = spi_rx_valid;
        end
    end
    
    // ===== SPI Master 신호들 =====
    logic [7:0] spi_tx_data;
    logic spi_tx_start;
    logic spi_tx_busy;
    
    // ===== 제어 신호들 =====
    logic [15:0] pixel_count;
    logic [2:0] motor_command;
    
    // ===== 상태 머신 =====
    enum logic [2:0] {
        IDLE       = 3'b000,
        RECEIVING  = 3'b001,
        PROCESSING = 3'b010,
        SENDING    = 3'b011,
        DONE       = 3'b100
    } current_state, next_state;

    // ===== 간단한 SPI SLAVE 구현 =====
    logic [2:0] spi_bit_count;
    logic [7:0] spi_shift_reg;
    logic spi_sclk_d1, spi_sclk_d2;
    logic spi_ss_d1, spi_ss_d2;
    logic spi_sclk_posedge, spi_sclk_negedge;
    logic spi_ss_negedge, spi_ss_posedge;

    
    // 클럭 도메인 동기화
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_sclk_d1 <= 0; spi_sclk_d2 <= 0;
            spi_ss_d1 <= 1; spi_ss_d2 <= 1;
        end else begin
            spi_sclk_d1 <= spi_slave_sclk; spi_sclk_d2 <= spi_sclk_d1;
            spi_ss_d1 <= spi_slave_ss; spi_ss_d2 <= spi_ss_d1;
        end
    end
    
    assign spi_sclk_posedge = spi_sclk_d1 & ~spi_sclk_d2;
    assign spi_sclk_negedge = ~spi_sclk_d1 & spi_sclk_d2;
    assign spi_ss_negedge = ~spi_ss_d1 & spi_ss_d2;
    assign spi_ss_posedge = spi_ss_d1 & ~spi_ss_d2;
    
    // SPI Slave 로직
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_bit_count <= 0;
            spi_shift_reg <= 0;
            spi_rx_data <= 0;
            spi_rx_valid <= 0;
        end else begin
            spi_rx_valid <= 0; // 기본값
            
            if (spi_ss_negedge) begin
                // SPI 전송 시작
                spi_bit_count <= 0;
                spi_shift_reg <= 0;
            end else if (!spi_slave_ss && spi_sclk_posedge) begin
                // 데이터 수신 (SCLK 상승 엣지에서)
                spi_shift_reg <= {spi_shift_reg[6:0], spi_slave_mosi};
                spi_bit_count <= spi_bit_count + 1;
                
                if (spi_bit_count == 7) begin
                    // 8비트 완성
                    spi_rx_data <= {spi_shift_reg[6:0], spi_slave_mosi};
                    spi_rx_valid <= 1;
                    spi_bit_count <= 0;
                end
            end
        end
    end
    
    assign spi_slave_miso = 1'b0; // 간단히 0으로 고정

    // ===== 간단한 SPI MASTER 구현 =====
    logic [3:0] master_bit_count;
    logic [7:0] master_shift_reg;
    logic [7:0] master_clk_div;
    logic master_sclk;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            master_clk_div <= 0;
            master_sclk <= 0;
        end else begin
            master_clk_div <= master_clk_div + 1;
            if (master_clk_div == 99) begin // 1MHz SPI 클럭
                master_sclk <= ~master_sclk;
                master_clk_div <= 0;
            end
        end
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            master_bit_count <= 0;
            master_shift_reg <= 0;
            spi_tx_busy <= 0;
            spi_master_ss <= 1;
            spi_master_sclk <= 0;
            spi_master_mosi <= 0;
        end else begin
            if (spi_tx_start && !spi_tx_busy) begin
                // 전송 시작
                spi_tx_busy <= 1;
                master_shift_reg <= spi_tx_data;
                master_bit_count <= 0;
                spi_master_ss <= 0;
            end else if (spi_tx_busy && (master_clk_div == 99) && master_sclk) begin
                // 데이터 전송 (SCLK 하강 엣지에서)
                spi_master_mosi <= master_shift_reg[7];
                master_shift_reg <= {master_shift_reg[6:0], 1'b0};
                master_bit_count <= master_bit_count + 1;
                
                if (master_bit_count == 7) begin
                    // 전송 완료
                    spi_tx_busy <= 0;
                    spi_master_ss <= 1;
                    master_bit_count <= 0;
                end
            end
            
            // SPI 클럭 출력
            if (spi_tx_busy) begin
                spi_master_sclk <= master_sclk;
            end else begin
                spi_master_sclk <= 0;
            end
        end
    end

    // ===== CNN 엔진 (간단한 버전 사용) =====
   CNN_TOP_Simple cnn_engine (
        .clk(clk),
        .rst(rst_n),
        .start_signal(cnn_start),
        .pixel_valid(cnn_pixel_valid),
        .pixel_in(cnn_pixel_data),
        .final_result_valid(cnn_result_valid),
        .final_lane_result(cnn_result),
        .cnn_busy(cnn_busy)
    ); 

    // ===== 제어 로직 =====
    
    // 상태 전환 (통합 신호 사용)
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (rx_valid) next_state = RECEIVING;
            end
            RECEIVING: begin
                if (pixel_count >= 1023) next_state = PROCESSING;
            end
           PROCESSING: begin
    if (cnn_result_valid) begin
        next_state = SENDING;
    end
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
    
    // ===== 픽셀 데이터 처리 (디버그 추가) =====
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_count <= 0;
            cnn_start <= 0;
            cnn_pixel_valid <= 0;
            cnn_pixel_data <= 0;
        end else begin
            case (current_state)
               IDLE: begin
    pixel_count <= 0;
    cnn_start <= 0;
    // 상태 진입시에만 출력
    if (current_state != IDLE) begin
        $display("DEBUG: IDLE 상태 진입");
    end
end
                
                RECEIVING: begin
                    if (rx_valid) begin
                        // 수신된 픽셀 데이터 처리
                        cnn_pixel_data <= rx_data;
                        cnn_pixel_valid <= 1;
                        
                        pixel_count <= pixel_count + 1;
                        
                        // 디버그 출력 - 매번 출력
                        $display("DEBUG: 픽셀 수신 - count=%d, data=0x%02X", pixel_count, rx_data);
                        
                        // CNN 시작 신호 (첫 번째 픽셀에서만)
                        if (pixel_count == 0) begin
                            cnn_start <= 1;
                            $display("DEBUG: CNN 시작 신호 활성화");
                        end else begin
                            cnn_start <= 0;
                        end
                        
                        // 100개마다 출력
                        if (pixel_count % 100 == 0) begin
                            $display("DEBUG: %d/1024 픽셀 수신됨", pixel_count);
                        end
                        
                        if (pixel_count >= 1023) begin
                            $display("DEBUG: !!! 1024 픽셀 수신 완료 - 다음 상태로 전환해야 함 !!!");
                        end
                    end else begin
                        cnn_pixel_valid <= 0;
                        cnn_start <= 0;
                    end
                end
                
                PROCESSING: begin
    cnn_pixel_valid <= 0;
    cnn_start <= 0;
    if (cnn_result_valid) begin
        $display("DEBUG: ✅ CNN 처리 완료! 결과: 0x%012X", cnn_result);
    end
end
                
                default: begin
                    cnn_pixel_valid <= 0;
                    cnn_start <= 0;
                end
            endcase
        end
    end
    
    // ===== 모터 명령 생성 및 전송 (간소화) =====
   always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        motor_command <= 3'b000;
        spi_tx_data <= 8'h00;
        spi_tx_start <= 0;
    end else begin
        spi_tx_start <= 0;
        
        case (current_state)
            PROCESSING: begin
                if (cnn_result_valid) begin
                    // CNN 결과에 따른 모터 명령
                    if (cnn_result[47] == 1'b1) begin
                        motor_command <= 3'b001;  // 좌회전
                    end else if (cnn_result[46:0] > 47'h1000000000000) begin
                        motor_command <= 3'b010;  // 우회전  
                    end else begin
                        motor_command <= 3'b100;  // 직진
                    end
                    $display("DEBUG: CNN 결과: 0x%012X, 모터: %b", cnn_result, motor_command);
                end
            end
            
            SENDING: begin
                if (current_state != next_state) begin
                    spi_tx_data <= {5'b10101, motor_command};
                    spi_tx_start <= 1;
                    $display("DEBUG: SPI 전송: 0x%02X", {5'b10101, motor_command});
                end
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