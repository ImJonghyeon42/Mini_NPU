module Simple_SPI_CNN_Adapter (
    input logic clk_axi,
    input logic clk_cnn,
    input logic rst_axi_n,
    input logic rst_cnn_n,
    
    // SPI Interface
    input logic [7:0] spi_rx_data,
    input logic spi_rx_valid,
    input logic spi_tx_ready,
    
    // CNN Stream Interface
    output logic pixel_valid_out,
    output logic [7:0] pixel_data_out,
    output logic cnn_start,
    input logic [47:0] cnn_result,
    input logic cnn_result_valid
);
    // 상태 머신
    typedef enum logic [2:0] {
        WAIT_CMD = 3'b000,
        WAIT_LENGTH = 3'b001,
        RECEIVE_DATA = 3'b010,
        PROCESS_CNN = 3'b011,
        SEND_RESULT = 3'b100
    } adapter_state_t;
    
    adapter_state_t state;
    logic [15:0] data_length;
    logic [15:0] data_count;
    logic [7:0] image_buffer [0:1023];  // 32x32 이미지 버퍼
    logic [10:0] buffer_addr;
    logic [7:0] command;
    logic start_cnn_pulse;
    
    // CDC for CNN start signal
    logic start_cnn_sync1, start_cnn_sync2;
    always_ff @(posedge clk_cnn or negedge rst_cnn_n) begin
        if (!rst_cnn_n) begin
            start_cnn_sync1 <= 1'b0;
            start_cnn_sync2 <= 1'b0;
        end else begin
            start_cnn_sync1 <= start_cnn_pulse;
            start_cnn_sync2 <= start_cnn_sync1;
        end
    end
    assign cnn_start = start_cnn_sync2;
    
    // 픽셀 스트림 생성
    logic [10:0] pixel_count;
    logic stream_active;
    
    always_ff @(posedge clk_cnn or negedge rst_cnn_n) begin
        if (!rst_cnn_n) begin
            pixel_count <= 11'h0;
            stream_active <= 1'b0;
            pixel_valid_out <= 1'b0;
            pixel_data_out <= 8'h00;
        end else begin
            if (cnn_start && !stream_active) begin
                stream_active <= 1'b1;
                pixel_count <= 11'h0;
                pixel_valid_out <= 1'b1;
                pixel_data_out <= image_buffer[0];
            end else if (stream_active) begin
                if (pixel_count < 11'd1023) begin
                    pixel_count <= pixel_count + 1;
                    pixel_data_out <= image_buffer[pixel_count + 1];
                    pixel_valid_out <= 1'b1;
                end else begin
                    stream_active <= 1'b0;
                    pixel_valid_out <= 1'b0;
                    pixel_count <= 11'h0;
                end
            end else begin
                pixel_valid_out <= 1'b0;
            end
        end
    end
    
    // SPI 프로토콜 처리
    always_ff @(posedge clk_axi or negedge rst_axi_n) begin
        if (!rst_axi_n) begin
            state <= WAIT_CMD;
            data_length <= 16'h0;
            data_count <= 16'h0;
            buffer_addr <= 11'h0;
            command <= 8'h00;
            start_cnn_pulse <= 1'b0;
        end else begin
            start_cnn_pulse <= 1'b0;
            
            case (state)
                WAIT_CMD: begin
                    if (spi_rx_valid) begin
                        command <= spi_rx_data;
                        if (spi_rx_data == 8'hAA) begin  // IMAGE_DATA 명령
                            state <= WAIT_LENGTH;
                            data_count <= 16'h0;
                        end else if (spi_rx_data == 8'hBB) begin  // START_CNN 명령
                            start_cnn_pulse <= 1'b1;
                            state <= PROCESS_CNN;
                        end
                    end
                end
                
                WAIT_LENGTH: begin
                    if (spi_rx_valid) begin
                        if (data_count == 16'h0) begin
                            data_length[15:8] <= spi_rx_data;
                            data_count <= 16'h1;
                        end else begin
                            data_length[7:0] <= spi_rx_data;
                            state <= RECEIVE_DATA;
                            data_count <= 16'h0;
                            buffer_addr <= 11'h0;
                        end
                    end
                end
                
                RECEIVE_DATA: begin
                    if (spi_rx_valid) begin
                        if (buffer_addr < 11'd1024) begin
                            image_buffer[buffer_addr] <= spi_rx_data;
                            buffer_addr <= buffer_addr + 1;
                        end
                        data_count <= data_count + 1;
                        
                        if (data_count >= (data_length - 1)) begin
                            state <= WAIT_CMD;
                        end
                    end
                end
                
                PROCESS_CNN: begin
                    if (cnn_result_valid) begin
                        state <= WAIT_CMD;
                    end
                end
                
                default: state <= WAIT_CMD;
            endcase
        end
    end
endmodule