`timescale 1ns/1ps
module CNN_TOP_Improved(
    input logic clk,
    input logic rst,  
    input logic start_signal,
    input logic pixel_valid,
    input logic [7:0] pixel_in,
    output logic final_result_valid,
    output logic signed [47:0] final_lane_result,
    output logic cnn_busy
);

    // ===== 내부 신호들 =====
    logic signed [21:0] feature_result;
    logic feature_valid;
    logic feature_done;
    
    logic flattened_buffer_full;
    logic signed [21:0] flatten_data [0:224];
    
    logic fc_start_pulse;
    logic fc_result_valid;
    logic signed [47:0] fc_result_data;
    
    // ===== 개선된 상태 머신 (실제 완료 신호 기반) =====
    enum logic [2:0] {
        ST_IDLE          = 3'b000,
        ST_FEATURE_CONV  = 3'b001,
        ST_FLATTEN_WAIT  = 3'b010,
        ST_FC_COMPUTE    = 3'b011,
        ST_RESULT_READY  = 3'b100,
        ST_DONE          = 3'b101
    } current_state, next_state;
    
    // 타이머는 비상용으로만 사용 (워치독)
    logic [19:0] watchdog_timer;  // 더 긴 타이머
    logic timeout_error;
    
    logic signed [47:0] final_result_reg;
    logic final_result_valid_reg;
    logic feature_start;

    // ===== Feature Extractor (수정된 버전 사용) =====
    Feature_Extractor_Fixed u_feature_extractor(
        .clk(clk), 
        .rst(rst),
        .start_signal(feature_start),
        .pixel_valid_in(pixel_valid),
        .pixel_in(pixel_in), 
        .final_result_out(feature_result),
        .final_result_valid(feature_valid), 
        .final_done_signal(feature_done)
    );
    
    // ===== Flatten Buffer =====
    flatten_buffer u_flatten_buffer(
        .clk(clk), 
        .rst(rst),
        .i_data_valid(feature_valid),
        .i_data_in(feature_result), 
        .o_buffer_full(flattened_buffer_full),
        .o_flattened_data(flatten_data)
    );
    
    // ===== Fully Connected Layer (수정된 버전 사용) =====
    Fully_Connected_Layer_Fixed u_fully_connected_layer(
        .clk(clk), 
        .rst(rst),
        .i_start(fc_start_pulse),
        .i_flattened_data(flatten_data), 
        .o_result_valid(fc_result_valid), 
        .o_result_data(fc_result_data)
    );
    
    // ===== 개선된 상태 전환 로직 (실제 신호 기반) =====
    always_comb begin
        next_state = current_state;
        case(current_state)
            ST_IDLE: begin
                if(start_signal) begin
                    next_state = ST_FEATURE_CONV;
                end
            end
            
            ST_FEATURE_CONV: begin
                // 실제 feature extraction 완료 신호 기반
                if(feature_done) begin
                    next_state = ST_FLATTEN_WAIT;
                end else if(timeout_error) begin
                    // 비상시에만 타임아웃 사용
                    next_state = ST_DONE;  // 에러로 종료
                end
            end
            
            ST_FLATTEN_WAIT: begin
                // 실제 flatten buffer 완료 신호 기반
                if(flattened_buffer_full) begin
                    next_state = ST_FC_COMPUTE;
                end else if(timeout_error) begin
                    next_state = ST_DONE;
                end
            end
            
            ST_FC_COMPUTE: begin
                // 실제 FC layer 완료 신호 기반
                if(fc_result_valid) begin
                    next_state = ST_RESULT_READY;
                end else if(timeout_error) begin
                    next_state = ST_DONE;
                end
            end
            
            ST_RESULT_READY: begin
                next_state = ST_DONE;
            end
            
            ST_DONE: begin
                next_state = ST_IDLE;
            end
        endcase
    end
    
    // ===== 상태 레지스터 및 제어 로직 =====
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            current_state <= ST_IDLE;
            watchdog_timer <= 20'h0;
            timeout_error <= 1'b0;
            final_result_reg <= 48'h0;
            final_result_valid_reg <= 1'b0;
        end else begin
            current_state <= next_state;
            
            // 워치독 타이머 (비상용)
            if (current_state != next_state) begin
                watchdog_timer <= 20'h0;
                timeout_error <= 1'b0;
                
                // 상태 전환 로그
                case(next_state)
                    ST_FEATURE_CONV: $display("CNN: Feature Extraction 시작");
                    ST_FLATTEN_WAIT: $display("CNN: Flatten 대기");
                    ST_FC_COMPUTE: $display("CNN: FC Layer 시작");
                    ST_RESULT_READY: $display("CNN: 결과 준비됨");
                    ST_DONE: $display("CNN: 완료");
                endcase
            end else begin
                watchdog_timer <= watchdog_timer + 1;
                // 더 긴 타임아웃 (200,000 사이클 ≈ 2ms @100MHz)
                if (watchdog_timer > 200000) begin
                    timeout_error <= 1'b1;
                    $display("CNN: 워치독 타임아웃! 상태: %s", current_state.name);
                end
            end
            
            // 결과 래치 (실제 완료 신호 기반)
            if (current_state == ST_IDLE && next_state == ST_FEATURE_CONV) begin
                final_result_valid_reg <= 1'b0;
            end
            
            if (fc_result_valid && current_state == ST_FC_COMPUTE) begin
                final_result_reg <= fc_result_data;
                final_result_valid_reg <= 1'b1;
                $display("CNN: 최종 결과 = 0x%012X", fc_result_data);
            end
            
            if (current_state == ST_DONE && next_state == ST_IDLE) begin
                final_result_valid_reg <= 1'b0;
            end
        end
    end
    
    // ===== FC 시작 펄스 생성 (개선) =====
    logic fc_start_d1;
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            fc_start_d1 <= 1'b0;
        end else begin
            fc_start_d1 <= (current_state == ST_FLATTEN_WAIT) && flattened_buffer_full;
        end
    end
    
    assign fc_start_pulse = (current_state == ST_FLATTEN_WAIT) && flattened_buffer_full && !fc_start_d1;
    
    // ===== Feature Extractor 시작 신호 생성 (개선) =====
    logic feature_start_d1;
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            feature_start_d1 <= 1'b0;
        end else begin
            feature_start_d1 <= (current_state == ST_FEATURE_CONV);
        end
    end
    assign feature_start = (current_state == ST_FEATURE_CONV) && !feature_start_d1;
    
    // ===== 출력 신호 =====
    assign cnn_busy = (current_state != ST_IDLE);
    assign final_result_valid = final_result_valid_reg;
    assign final_lane_result = final_result_reg;
    
    // ===== 디버그 출력 =====
    always_ff @(posedge clk) begin
        if (pixel_valid) begin
            static int pixel_count = 0;
            pixel_count++;
            if (pixel_count % 256 == 0) begin
                $display("CNN: 픽셀 %d개 수신됨", pixel_count);
            end
        end
    end
    
endmodule