`timescale 1ns/1ps
module CNN_TOP(
    input logic clk,
    input logic rst,
    input logic start_signal,
    input logic pixel_valid,
    input logic [7:0] pixel_in,
    output logic final_result_valid,
    output logic signed [47:0] final_lane_result,
    output logic cnn_busy  // <- 추가된 포트
);
    logic signed [21:0] feature_result;
    logic feature_valid;
    logic feature_done;
    
    logic flattened_buffer_full;
    logic signed [21:0] flatten_data [0:224];
    
    logic fc_executed;     
    logic fc_start_pulse;
    
    // CNN이 바쁜 상태를 나타내는 신호
    logic processing_active;

    Feature_Extractor u_feature_extractor(
        .clk, .rst, .pixel_valid_in(pixel_valid),
        .start_signal, .pixel_in, .final_result_out(feature_result),
        .final_result_valid(feature_valid), .final_done_signal(feature_done)
    );
    
    flatten_buffer u_flatten_buffer(
        .clk, .rst, 
        .i_data_valid(feature_valid),
        .i_data_in(feature_result), 
        .o_buffer_full(flattened_buffer_full),
        .o_flattened_data(flatten_data)
    );
    
    always_ff @(posedge clk or negedge rst) begin  
        if (!rst) begin  
            fc_executed <= 0;
            fc_start_pulse <= 0;
            processing_active <= 0;
        end else begin
            // 시작 신호가 오면 처리 시작
            if (start_signal) begin
                processing_active <= 1;
                fc_executed <= 0;
            end
            
            if (flattened_buffer_full && !fc_executed) begin
                fc_start_pulse <= 1;
                fc_executed <= 1;
                $display("[CNN_TOP] FC Layer 원샷 시작");
            end else begin
                fc_start_pulse <= 0;
            end
            
            // FC 결과가 나오면 처리 완료
            if (final_result_valid) begin
                processing_active <= 0;
            end
        end
    end
    
    Fully_Connected_Layer u_fully_connected_layer(
        .clk, .rst, 
        .i_start(fc_start_pulse),  
        .i_flattened_data(flatten_data), 
        .o_result_valid(final_result_valid), 
        .o_result_data(final_lane_result)
    );
    
    // CNN이 바쁜 상태: 처리 중이거나 FC가 실행 중
    assign cnn_busy = processing_active || fc_start_pulse || (!final_result_valid && fc_executed);
    
endmodule