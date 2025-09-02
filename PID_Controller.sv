`timescale 1ns/1ps
module PID_Controller(
    input logic clk,
    input logic rst,
    
    // CNN으로부터의 입력
    input logic i_cnn_valid,
    input logic signed [47:0] i_cnn_error, // CNN의 출력을 오차 값으로 사용
    
    // 액추에이터로 전달될 출력
    output logic o_pid_valid,
    output logic signed [47:0] o_pid_output // 최종 제어 출력 (예: 조향각)
);

    // Q12.10 고정 소수점 형식의 PID 계수
    localparam Q_FACTOR = 10;
    localparam signed [21:0] KP_FIXED = 22'd2048; // Kp = 2.0
    localparam signed [21:0] KI_FIXED = 22'd512;  // Ki = 0.5
    localparam signed [21:0] KD_FIXED = 22'd102;  // Kd = 0.1

    // 내부 레지스터 및 와이어
    logic signed [47:0] error_reg;
    logic signed [47:0] error_prev;
    logic signed [63:0] integral_acc; // 오버플로우 방지를 위해 폭을 넓게 설정
    
    logic signed [63:0] p_term;
    logic signed [63:0] i_term;
    logic signed [63:0] d_term;
    
    logic start_pulse;
    logic i_cnn_valid_d1;

    // 입력 유효 신호를 펄스 형태로 변환
    always_ff @(posedge clk) begin
        if(rst) i_cnn_valid_d1 <= 1'b0;
        else    i_cnn_valid_d1 <= i_cnn_valid;
    end
    assign start_pulse = i_cnn_valid & ~i_cnn_valid_d1;

    always_ff @(posedge clk) begin
        if (rst) begin
            error_reg       <= '0;
            error_prev      <= '0;
            integral_acc    <= '0;
            p_term          <= '0;
            i_term          <= '0;
            d_term          <= '0;
            o_pid_output    <= '0;
            o_pid_valid     <= 1'b0;
        end else begin
            o_pid_valid <= 1'b0; // 기본적으로는 low 유지
            
            if (start_pulse) begin
                // 1. 새로운 오차 값 등록
                // CNN 출력이 매우 크므로, 실제 시스템에 맞게 스케일링이 필요할 수 있음
                // 여기서는 예시로 하위 22비트만 사용
                error_reg <= i_cnn_error[21:0]; 
                
                // 2. 미분(D) 항 계산: (현재 오차 - 이전 오차)
                logic signed [47:0] derivative = error_reg - error_prev;
                
                // 3. 적분(I) 항 누적
                // Anti-windup: 적분값이 과도하게 커지는 것을 방지 (Saturation)
                if (integral_acc > 64'h7FFFFFFFFFFFFFFF - error_reg) begin
                    integral_acc <= 64'h7FFFFFFFFFFFFFFF;
                end else if (integral_acc < 64'h8000000000000000 + error_reg) begin
                    integral_acc <= 64'h8000000000000000;
                end else begin
                    integral_acc <= integral_acc + error_reg;
                end

                // 4. 각 텀 계산 (고정 소수점 연산)
                p_term <= KP_FIXED * error_reg;
                i_term <= KI_FIXED * integral_acc;
                d_term <= KD_FIXED * derivative;

                // 5. 최종 PID 출력 계산 및 스케일링 (Q_FACTOR 만큼 시프트)
                o_pid_output <= (p_term + i_term + d_term) >>> Q_FACTOR;
                o_pid_valid  <= 1'b1; // 계산 완료, 출력 유효
                
                // 6. 현재 오차를 이전 오차로 저장
                error_prev <= error_reg;

                $display("[PID_DEBUG] Time:%0t Error:%d P_term:%d, I_term:%d, D_term:%d -> Output:%d",
                         $time, error_reg, (p_term >>> Q_FACTOR), (i_term >>> Q_FACTOR), (d_term >>> Q_FACTOR), o_pid_output);
            end
        end
    end

endmodule