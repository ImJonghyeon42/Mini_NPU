
`timescale 1ns/1ps

module RELU_POOL_TOP (
    input  logic clk,
    input  logic rst,
    input  logic start_signal,
    input  logic pixel_valid,
    input  logic signed [21:0] pixel_in,

    output logic signed [21:0] result_out,
    output logic             result_valid,
    output logic             done_signal
);

    // Activation Function과 Max Pooling 모듈 간 연결 신호
    logic signed [21:0] relu_result_out;
    logic             relu_result_valid;

    // 1. Activation Function (ReLU) 인스턴스
    Activation_Function U0_RELU (
        .clk,
        .rst,
        .pixel_valid ( pixel_valid     ), // Top 모듈의 입력을 받음
        .pixel_in    ( pixel_in        ), // Top 모듈의 입력을 받음
        .result_out  ( relu_result_out ), // Max Pooling 모듈로 전달
        .result_valid( relu_result_valid )  // Max Pooling 모듈로 전달
    );

    // 2. Max Pooling 인스턴스
    Max_Pooling U1_POOL (
        .clk,
        .rst,
        .start_signal( start_signal    ), // Top 모듈의 입력을 받음
        .pixel_valid ( relu_result_valid ), // ReLU의 출력을 받음
        .pixel_in    ( relu_result_out ), // ReLU의 출력을 받음
        .result_out  ( result_out      ), // Top 모듈의 최종 출력
        .result_valid( result_valid    ), // Top 모듈의 최종 출력
        .done_signal ( done_signal     )  // Top 모듈의 최종 출력
    );

endmodule