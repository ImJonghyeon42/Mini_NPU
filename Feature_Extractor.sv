`timescale 1ns/1ps
module CNN_TOP(
    input logic clk,
    input logic rst,  // Active Low (negedge)
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
    
    // ===== 간단한 상태 머신 =====
    enum logic [2:0] {
        ST_IDLE            = 3'b000,
        ST_FEATURE_EXTRACT = 3'b001, 
        ST_WAIT_BUFFER     = 3'b010,
        ST_FC_PROCESS      = 3'b011,
        ST_RESULT_HOLD     = 3'b100
    } current_state, next_state;
    
    // 카운터들
    logic [31:0] pixel_counter;
    logic [31:0] feature_counter;
    logic [15:0] state_timer;
    
    // 결과 래치
    logic signed [47:0] final_result_reg;
    logic final_result_valid_reg;
    
    // Feature Extractor 제어
    logic feature_start;

    // ===== Feature Extractor =====
    Feature_Extractor u_feature_extractor(
        .clk(clk), 
        .rst(rst),  // Active Low 그대로
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
        .rst(rst),  // Active Low 그대로
        .i_data_valid(feature_valid),
        .i_data_in(feature_result), 
        .o_buffer_full(flattened_buffer_full),
        .o_flattened_data(flatten_data)
    );
    
    // ===== Fully Connected Layer =====
    Fully_Connected_Layer u_fully_connected_layer(
        .clk(clk), 
        .rst(rst),  // Active Low 그대로
        .i_start(fc_start_pulse),
        .i_flattened_data(flatten_data), 
        .o_result_valid(fc_result_valid), 
        .o_result_data(fc_result_data)
    );
    
    // ===== 상태 전환 로직 =====
    always_comb begin
        next_state = current_state;
        case(current_state)
            ST_IDLE: begin
                if(start_signal) 
                    next_state = ST_FEATURE_EXTRACT;
            end
            
            ST_FEATURE_EXTRACT: begin
                // 충분한 픽셀을 받고 feature 추출이 완료되면
                if(pixel_counter >= 1024 && feature_done)
                    next_state = ST_WAIT_BUFFER;
                // 타임아웃 (5초)
                else if(state_timer > 50000)  
                    next_state = ST_WAIT_BUFFER;
            end
            
            ST_WAIT_BUFFER: begin
                // Buffer가 가득 차면 FC 시작
                if(flattened_buffer_full)
                    next_state = ST_FC_PROCESS;
                // 타임아웃 (1초)
                else if(state_timer > 10000)
                    next_state = ST_FC_PROCESS;
            end
            
            ST_FC_PROCESS: begin
                // FC 결과가 나오면 완료
                if(fc_result_valid)
                    next_state = ST_RESULT_HOLD;
                // 타임아웃 (10초)
                else if(state_timer > 100000)
                    next_state = ST_RESULT_HOLD;
            end
            
            ST_RESULT_HOLD: begin
                // 결과를 1000 클럭 동안 유지
                if(state_timer > 1000)
                    next_state = ST_IDLE;
            end
        endcase
    end
    
    // ===== 상태 레지스터 및 카운터 (Active Low Reset) =====
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin  // Active Low Reset
            current_state <= ST_IDLE;
            pixel_counter <= 32'h0;
            feature_counter <= 32'h0;
            state_timer <= 16'h0;
            final_result_reg <= 48'h0;
            final_result_valid_reg <= 1'b0;
        end else begin
            current_state <= next_state;
            
            // 상태 타이머
            if (current_state != next_state) begin
                state_timer <= 16'h0;
            end else begin
                state_timer <= state_timer + 1;
            end
            
            // 픽셀 카운터
            if (pixel_valid && current_state == ST_FEATURE_EXTRACT) begin
                pixel_counter <= pixel_counter + 1;
            end
            
            // Feature 카운터  
            if (feature_valid) begin
                feature_counter <= feature_counter + 1;
            end
            
            // 새 시작시 카운터 리셋
            if (current_state == ST_IDLE && next_state == ST_FEATURE_EXTRACT) begin
                pixel_counter <= 32'h0;
                feature_counter <= 32'h0;
                final_result_valid_reg <= 1'b0;
            end
            
            // FC 결과 래치
            if (fc_result_valid && current_state == ST_FC_PROCESS) begin
                final_result_reg <= fc_result_data;
                final_result_valid_reg <= 1'b1;
            end
            
            // 타임아웃으로 강제 완료 (디버그용)
            else if (current_state == ST_FC_PROCESS && next_state == ST_RESULT_HOLD && !fc_result_valid) begin
                final_result_reg <= {16'hDEAD, 16'hBEEF, pixel_counter[15:0]};
                final_result_valid_reg <= 1'b1;
            end
            
            // IDLE로 돌아가면 valid 해제
            if (current_state == ST_RESULT_HOLD && next_state == ST_IDLE) begin
                final_result_valid_reg <= 1'b0;
            end
        end
    end
    
    // ===== FC 시작 펄스 생성 =====
    logic fc_start_d1;
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            fc_start_d1 <= 1'b0;
        end else begin
            fc_start_d1 <= (current_state == ST_FC_PROCESS);
        end
    end
    
    assign fc_start_pulse = (current_state == ST_FC_PROCESS) && !fc_start_d1;
    
    // ===== 제어 신호 생성 =====
    // Feature start를 펄스로 변경 (계속 active 방지)
    logic feature_start_d1;
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            feature_start_d1 <= 1'b0;
        end else begin
            feature_start_d1 <= (current_state == ST_FEATURE_EXTRACT);
        end
    end
    assign feature_start = (current_state == ST_FEATURE_EXTRACT) && !feature_start_d1;
    
    // ===== 출력 신호 =====
    assign cnn_busy = (current_state != ST_IDLE);
    assign final_result_valid = final_result_valid_reg;
    assign final_lane_result = final_result_reg;
    
endmodule