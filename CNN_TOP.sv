`timescale 1ns/1ps
module CNN_TOP(
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
    
    // ===== 상태 머신으로 명확한 제어 =====
    enum logic [2:0] {
        ST_IDLE,
        ST_CONV_PROCESSING, 
        ST_CONV_DONE,
        ST_FC_PROCESSING,
        ST_RESULT_READY
    } current_state, next_state;
    
    // 결과 래치용 레지스터
    logic signed [47:0] final_result_reg;
    logic final_result_valid_reg;

    // ===== Feature Extractor (Convolution + Pooling) =====
    Feature_Extractor u_feature_extractor(
        .clk(clk), 
        .rst(rst), 
        .start_signal(start_signal),
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
    
    // ===== 상태 전환 로직 =====
    always_comb begin
        next_state = current_state;
        case(current_state)
            ST_IDLE: begin
                if(start_signal) 
                    next_state = ST_CONV_PROCESSING;
            end
            
            ST_CONV_PROCESSING: begin
                if(feature_done) 
                    next_state = ST_CONV_DONE;
            end
            
            ST_CONV_DONE: begin
                if(flattened_buffer_full) 
                    next_state = ST_FC_PROCESSING;
            end
            
            ST_FC_PROCESSING: begin
                if(fc_result_valid) 
                    next_state = ST_RESULT_READY;
            end
            
            ST_RESULT_READY: begin
                // 결과를 충분히 유지한 후 IDLE로
                next_state = ST_IDLE;
            end
        endcase
    end
    
    // ===== 상태 레지스터 및 제어 신호 생성 =====
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            current_state <= ST_IDLE;
            final_result_reg <= 48'h0;
            final_result_valid_reg <= 1'b0;
        end else begin
            current_state <= next_state;
            
            // FC 결과가 나오면 래치
            if (fc_result_valid && current_state == ST_FC_PROCESSING) begin
                final_result_reg <= fc_result_data;
                final_result_valid_reg <= 1'b1;
                $display("[CNN_TOP] FC 결과 래치: %0d (0x%h)", fc_result_data, fc_result_data);
            end
            
            // IDLE 상태로 돌아가면 valid 클리어
            if (current_state == ST_RESULT_READY && next_state == ST_IDLE) begin
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
            fc_start_d1 <= (current_state == ST_FC_PROCESSING);
        end
    end
    
    assign fc_start_pulse = (current_state == ST_FC_PROCESSING) && !fc_start_d1;
    
    // ===== 출력 신호 할당 =====
    assign cnn_busy = (current_state != ST_IDLE);
    assign final_result_valid = final_result_valid_reg;
    assign final_lane_result = final_result_reg;
    
    // ===== 디버깅 출력 =====
    always @(posedge clk) begin
        if (current_state != next_state) begin
            case(next_state)
                ST_IDLE: $display("[CNN_TOP] 상태: IDLE");
                ST_CONV_PROCESSING: $display("[CNN_TOP] 상태: CONV_PROCESSING");
                ST_CONV_DONE: $display("[CNN_TOP] 상태: CONV_DONE");
                ST_FC_PROCESSING: $display("[CNN_TOP] 상태: FC_PROCESSING");
                ST_RESULT_READY: $display("[CNN_TOP] 상태: RESULT_READY");
            endcase
        end
        
        if (fc_start_pulse) begin
            $display("[CNN_TOP] FC 시작 펄스 생성");
        end
        
        if (flattened_buffer_full && current_state == ST_CONV_DONE) begin
            $display("[CNN_TOP] Buffer Full, FC 시작 준비");
        end
    end
    
endmodule