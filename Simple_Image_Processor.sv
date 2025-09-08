// 수정된 Simple_Image_Processor - 결과 래치 문제 해결
module Simple_Image_Processor (
    input logic clk,
    input logic rst_n,
    input logic pixel_valid_in,
    input logic [7:0] pixel_data_in,
    output logic command_valid,
    output logic [2:0] motor_command_out,
    output logic [3:0] status_led,
    output logic busy
);
    logic cnn_start;
    logic cnn_pixel_valid;
    logic [7:0] cnn_pixel_data;
    logic cnn_busy;
    logic cnn_result_valid;
    logic signed [47:0] cnn_result;
    logic [15:0] pixel_count;
    logic signed [47:0] latched_cnn_result;
    logic result_captured;  // 결과 캡처 플래그 추가
    
    enum logic [2:0] {
        IDLE       = 3'b000,
        RECEIVING  = 3'b001,
        PROCESSING = 3'b010,
        SENDING    = 3'b011,
        DONE       = 3'b100
    } current_state, next_state;
    
    Simple_Image_Analyzer image_analyzer (
        .clk(clk),
        .rst_n(rst_n),
        .start_signal(cnn_start),
        .pixel_valid(cnn_pixel_valid),
        .pixel_in(cnn_pixel_data),
        .final_result_valid(cnn_result_valid),
        .final_lane_result(cnn_result),
        .analyzer_busy(cnn_busy)
    );
    
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE:       if (pixel_valid_in)      next_state = RECEIVING;
            RECEIVING: if (pixel_count >= 1020) next_state = PROCESSING;  // 조건 완화
            PROCESSING: if (result_captured || !cnn_busy) next_state = SENDING;  // 수정
            SENDING:                             next_state = DONE;
            DONE:                                next_state = IDLE;
        endcase
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= IDLE;
        else        current_state <= next_state;
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_count <= 0;
            cnn_start <= 0;
            cnn_pixel_valid <= 0;
            cnn_pixel_data <= 0;
        end else begin
            cnn_start <= 0;
            cnn_pixel_valid <= 0;
            case (current_state)
                IDLE:      pixel_count <= 0;
                RECEIVING: begin
                    if (pixel_valid_in) begin
                        cnn_pixel_data <= pixel_data_in;
                        cnn_pixel_valid <= 1;
                        pixel_count <= pixel_count + 1;
                        $display("[%t ns] \t [PROC] 픽셀 수신! (count = %d)", $time, pixel_count);
                        if (pixel_count == 0) cnn_start <= 1;
                    end
                end
            endcase
        end
    end
    
    // 결과 래치 로직 수정
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            motor_command_out <= 3'b000;
            latched_cnn_result <= 0;
            command_valid <= 0;
            result_captured <= 0;
        end else begin
            command_valid <= 0;
            
            // 결과 캡처 (어느 상태에서든 가능)
            if (cnn_result_valid) begin
                latched_cnn_result <= cnn_result;
                result_captured <= 1;
                $display("결과 캡처됨: 0x%012X", cnn_result);
            end
            
            case (current_state)
                IDLE: begin
                    result_captured <= 0;
                    latched_cnn_result <= 0;
                end
                SENDING: begin
                    command_valid <= 1;
                    case (latched_cnn_result[1:0])
                        2'b01:   motor_command_out <= 3'b001;  // 좌회전
                        2'b10:   motor_command_out <= 3'b010;  // 우회전
                        default: motor_command_out <= 3'b100;  // 직진
                    endcase
                    $display("모터 명령: result=0x%X, command=%b", latched_cnn_result[1:0], 
                            (latched_cnn_result[1:0] == 2'b01) ? 3'b001 :
                            (latched_cnn_result[1:0] == 2'b10) ? 3'b010 : 3'b100);
                end
            endcase
        end
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) status_led <= 4'b0001;
        else begin
            case (current_state)
                IDLE:       status_led <= 4'b0001;
                RECEIVING:  status_led <= 4'b0010;
                PROCESSING: status_led <= 4'b0100;
                SENDING:    status_led <= 4'b1000;
                DONE:       status_led <= 4'b1111;
            endcase
        end
    end
    assign busy = (current_state != IDLE);
endmodule