`timescale 1ns/1ps
module AUTONOMOUS_DRIVING_TOP(
    input logic clk,
    input logic rst,
    input logic start_signal, // 전체 시스템 시작 신호
    
    // 카메라 이미지 입력
    input logic pixel_valid,
    input logic [7:0] pixel_in,
    
    // 최종 제어 출력
    output logic final_control_valid,
    output logic signed [47:0] final_control_output // 예: 조향각
);

    // CNN과 PID 간의 연결 신호
    logic cnn_result_valid;
    logic signed [47:0] cnn_lane_error;

    // 1. CNN 모듈 인스턴스화
    CNN_TOP u_cnn_top(
        .clk(clk),
        .rst(rst),
        .start_signal(start_signal),
        .pixel_valid(pixel_valid),
        .pixel_in(pixel_in),
        
        // CNN의 최종 출력을 PID로 연결
        .final_result_valid(cnn_result_valid),
        .final_lane_result(cnn_lane_error)
    );

    // 2. PID 제어기 인스턴스화
    PID_Controller u_pid_controller(
        .clk(clk),
        .rst(rst),
        
        // CNN의 출력을 PID의 입력으로 사용
        .i_cnn_valid(cnn_result_valid),
        .i_cnn_error(cnn_lane_error),
        
        // PID의 최종 출력을 시스템의 최종 출력으로 연결
        .o_pid_valid(final_control_valid),
        .o_pid_output(final_control_output)
    );

endmodule