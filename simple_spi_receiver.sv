module Simple_SPI_Slave (
    input logic clk,
    input logic rst_n,
    input logic spi_sclk,
    input logic spi_mosi,
    output logic spi_miso,
    input logic spi_cs_n,
    output logic [7:0] rx_data,
    output logic rx_valid,
    output logic tx_ready
);
    // SPI 상태 머신
    typedef enum logic [1:0] {
        IDLE = 2'b00,
        RECEIVING = 2'b01,
        TRANSMITTING = 2'b10
    } spi_state_t;
    
    spi_state_t state;
    logic [7:0] shift_reg;
    logic [2:0] bit_count;
    logic spi_sclk_d1, spi_sclk_d2;
    logic spi_cs_n_d1, spi_cs_n_d2;
    logic sclk_posedge, sclk_negedge;
    logic cs_falling;
    
    // 엣지 감지
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_sclk_d1 <= 1'b0;
            spi_sclk_d2 <= 1'b0;
            spi_cs_n_d1 <= 1'b1;
            spi_cs_n_d2 <= 1'b1;
        end else begin
            spi_sclk_d1 <= spi_sclk;
            spi_sclk_d2 <= spi_sclk_d1;
            spi_cs_n_d1 <= spi_cs_n;
            spi_cs_n_d2 <= spi_cs_n_d1;
        end
    end
    
    assign sclk_posedge = spi_sclk_d1 && !spi_sclk_d2;
    assign sclk_negedge = !spi_sclk_d1 && spi_sclk_d2;
    assign cs_falling = !spi_cs_n_d1 && spi_cs_n_d2;
    
    // SPI 상태 머신
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            shift_reg <= 8'h00;
            bit_count <= 3'b000;
            rx_data <= 8'h00;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            
            case (state)
                IDLE: begin
                    if (cs_falling) begin
                        state <= RECEIVING;
                        bit_count <= 3'b000;
                        shift_reg <= 8'h00;
                    end
                end
                
                RECEIVING: begin
                    if (spi_cs_n) begin
                        state <= IDLE;
                    end else if (sclk_posedge) begin
                        shift_reg <= {shift_reg[6:0], spi_mosi};
                        bit_count <= bit_count + 1;
                        
                        if (bit_count == 3'b111) begin
                            rx_data <= {shift_reg[6:0], spi_mosi};
                            rx_valid <= 1'b1;
                            bit_count <= 3'b000;
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    assign spi_miso = 1'b0;  // 간단한 구현에서는 항상 0
    assign tx_ready = 1'b1;
endmodule