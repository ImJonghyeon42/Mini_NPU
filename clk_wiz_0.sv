`timescale 1ns/1ps
module clk_wiz_0 (
    input logic clk_in1,
    output logic clk_out1,    // 150MHz
    output logic clk_out2,    // 100MHz  
    output logic locked,
    input logic reset         // reset 포트 (resetn 대신)
);
    // 간단한 클록 분주기
    logic [3:0] div_counter;
    
    always_ff @(posedge clk_in1 or posedge reset) begin
        if (reset) begin
            div_counter <= 4'h0;
            locked <= 1'b0;
        end else begin
            div_counter <= div_counter + 1;
            if (div_counter > 4'd10) locked <= 1'b1;
        end
    end
    
    // 클록 출력 (간단히 입력 클록 사용)
    assign clk_out1 = clk_in1;  // 실제로는 150MHz여야 함
    assign clk_out2 = clk_in1;  // 실제로는 100MHz여야 함
endmodule