`timescale 1ns/1ps
module CNN_TOP(
    input logic clk,
    input logic rst,  // Active Low
    input logic start_signal,
    input logic pixel_valid,
    input logic [7:0] pixel_in,
    output logic final_result_valid,
    output logic signed [47:0] final_lane_result,
    output logic cnn_busy
);

    // ===== 내부 신호들 (최소화) =====
    logic signed [21:0] feature_result;
    logic feature_valid;
    logic feature_done;
    
    logic flattened_buffer_full;
    logic signed [21:0] flatten_data [0:224];
    
    logic fc_start_pulse;
    logic fc_result_valid;
    logic signed [47:0] fc_result_data;
    
    // ===== 단순화된 상태 머신 (5→3 상태로 축소) =====
    enum logic [1:0] {
        ST_IDLE       = 2'b00,
        ST_PROCESSING = 2'b01,
        ST_DONE       = 2'b10
    } current_state, next_state;
    
    // ===== 카운터 대신 간단한 타이머만 사용 =====
    logic [15:0] simple_timer;  // 32비트→16비트로 축소
    
    // ===== 결과 래치 =====
    logic signed [47:0] final_result_reg;
    logic final_result_valid_reg;
    
    // Feature Extractor 제어
    logic feature_start;

    // ===== Feature Extractor =====
    Feature_Extractor u_feature_extractor(
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
    
    // ===== Fully Connected Layer =====
    Fully_Connected_Layer u_fully_connected_layer(
        .clk(clk), 
        .rst(rst),
        .i_start(fc_start_pulse),
        .i_flattened_data(flatten_data), 
        .o_result_valid(fc_result_valid), 
        .o_result_data(fc_result_data)
    );
    
    // ===== 단순화된 상태 전환 로직 =====
    always_comb begin
        next_state = current_state;
        case(current_state)
            ST_IDLE: begin
                if(start_signal) 
                    next_state = ST_PROCESSING;
            end
            
            ST_PROCESSING: begin
                // FC 결과가 나오거나 타임아웃 시 완료
                if(fc_result_valid || simple_timer > 50000)
                    next_state = ST_DONE;
            end
            
            ST_DONE: begin
                // 짧은 대기 후 IDLE로
                if(simple_timer > 1000)
                    next_state = ST_IDLE;
            end
        endcase
    end
    
    // ===== 상태 레지스터 및 간단한 타이머 =====
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            current_state <= ST_IDLE;
            simple_timer <= 16'h0;
            final_result_reg <= 48'h0;
            final_result_valid_reg <= 1'b0;
        end else begin
            current_state <= next_state;
            
            // 상태 타이머 (단순화)
            if (current_state != next_state) begin
                simple_timer <= 16'h0;
            end else begin
                simple_timer <= simple_timer + 1;
            end
            
            // 새 시작시 초기화
            if (current_state == ST_IDLE && next_state == ST_PROCESSING) begin
                final_result_valid_reg <= 1'b0;
            end
            
            // FC 결과 래치 (단순화)
            if (fc_result_valid && current_state == ST_PROCESSING) begin
                final_result_reg <= fc_result_data;
                final_result_valid_reg <= 1'b1;
            end
            
            // IDLE로 돌아가면 valid 해제
            if (current_state == ST_DONE && next_state == ST_IDLE) begin
                final_result_valid_reg <= 1'b0;
            end
        end
    end
    
    // ===== FC 시작 펄스 생성 (단순화) =====
    logic fc_start_d1;
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            fc_start_d1 <= 1'b0;
        end else begin
            fc_start_d1 <= flattened_buffer_full;
        end
    end
    
    assign fc_start_pulse = flattened_buffer_full && !fc_start_d1;
    
    // ===== 제어 신호 생성 (단순화) =====
    logic feature_start_d1;
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            feature_start_d1 <= 1'b0;
        end else begin
            feature_start_d1 <= (current_state == ST_PROCESSING);
        end
    end
    assign feature_start = (current_state == ST_PROCESSING) && !feature_start_d1;
    
    // ===== 출력 신호 (단순화) =====
    assign cnn_busy = (current_state != ST_IDLE);
    assign final_result_valid = final_result_valid_reg;
    assign final_lane_result = final_result_reg;
    
endmodule