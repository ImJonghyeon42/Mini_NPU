`timescale 1ns/1ps
module simple_quantizer #(
	parameter IN_WIDTH = 30,
	parameter OUT_WIDTH = 22,
	parameter Q_BITS = 11
)(
	input logic signed [IN_WIDTH-1:0] din,
	output logic signed [OUT_WIDTH-1:0] dout
);
	assign dout = din[IN_WIDTH-1 -: OUT_WIDTH]; 
	// 연산 후 32비트로 늘어난 데이터에서 상위 22비트만 선택 (단순 절삭)
    // MSB부터 필요한 만큼만 잘라내어 정밀도를 맞춤
endmodule