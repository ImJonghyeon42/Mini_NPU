`timescale 1ns/1ps
module Fully_Connected_Layer_Fixed(
	input logic clk,
	input logic rst,
	input logic i_start,
	input logic signed [21:0] i_flattened_data [0:224],
	output logic o_result_valid,
	output logic signed [47:0] o_result_data
);
	// ===== 하드코딩된 가중치 ROM (파일 의존성 제거) =====
	logic signed [21:0] weight_ROM [0 : 224];
	
	// ===== 상태 정의 =====
	enum logic [1:0] {
		IDLE, 
		COMPUTE, 
		DONE
	} state;
	
	// ===== 내부 신호들 =====
	logic [7:0] mac_cnt;
	logic mac_valid;
	logic signed [47:0] accumulator_reg;
	logic signed [47:0] mac_sum_in;
	logic signed [47:0] mac_sum_out;
	logic mac_sum_out_valid;
	
	// ===== MAC Unit =====
	MAC_unit MAC(
		.clk(clk), 
		.rst(rst), 
		.i_valid(mac_valid),
		.data_in_a(i_flattened_data[mac_cnt]),
		.data_in_b(weight_ROM[mac_cnt]),
		.sum_in(mac_sum_in),
		.o_valid(mac_sum_out_valid),
		.sum_out(mac_sum_out)
	);
	
	// ===== 시작 펄스 감지 =====
	logic i_start_d1;
	always_ff @(posedge clk or negedge rst) begin 
		if(!rst) 
			i_start_d1 <= 1'b0; 
		else 
			i_start_d1 <= i_start;
	end
	
	logic start_pulse = i_start & ~i_start_d1;
	
	// ===== 메인 상태 머신 =====
	always_ff @(posedge clk or negedge rst) begin  
		if(!rst) begin  
			state <= IDLE;
			mac_cnt <= 8'h0;
			mac_valid <= 1'b0;
			accumulator_reg <= 48'h0;
			o_result_valid <= 1'b0;
		end else begin
			case(state) 
				IDLE: begin
					mac_valid <= 1'b0;
					o_result_valid <= 1'b0;
					
					if(start_pulse) begin
						accumulator_reg <= 48'h0;
						mac_cnt <= 8'h0;
						mac_valid <= 1'b1;
						state <= COMPUTE;
						$display("FC Layer 시작: 225개 가중치 계산");
					end
				end
				
				COMPUTE: begin
					// MAC 결과 누적
					if(mac_sum_out_valid) begin
						accumulator_reg <= mac_sum_out;
						
						// 진행 상황 출력 (디버깅용)
						if(mac_cnt % 50 == 0) begin
							$display("FC 진행: %d/225, 누적값: %h", mac_cnt, mac_sum_out);
						end
					end
					
					// 모든 가중치 처리 완료?
					if(mac_cnt == 224) begin
						state <= DONE;
						mac_valid <= 1'b0;
						o_result_valid <= 1'b1;
						$display("FC Layer 완료: 최종 결과 = %h", accumulator_reg);
					end else begin
						mac_cnt <= mac_cnt + 1'b1;
						mac_valid <= 1'b1;
					end
				end
				
				DONE: begin
					o_result_valid <= 1'b1;
					if(!i_start) begin
						state <= IDLE;
						o_result_valid <= 1'b0;
					end
				end
			endcase
		end
	end
	
	// ===== 출력 할당 =====
	assign mac_sum_in = accumulator_reg;
	assign o_result_data = accumulator_reg;
	
	// ===== 가중치 하드코딩 (파일 의존성 제거) =====
	initial begin
		// weight.mem 파일의 모든 225개 가중치를 하드코딩
		weight_ROM[0] = 22'h3FFE46;   weight_ROM[1] = 22'h3FFB24;   weight_ROM[2] = 22'h3FFDB8;   weight_ROM[3] = 22'h3FFB7F;
		weight_ROM[4] = 22'h000136;   weight_ROM[5] = 22'h000964;   weight_ROM[6] = 22'h3FFD6A;   weight_ROM[7] = 22'h0001CC;
		weight_ROM[8] = 22'h3FFCE0;   weight_ROM[9] = 22'h000496;   weight_ROM[10] = 22'h3FFE85;  weight_ROM[11] = 22'h3FFD36;
		weight_ROM[12] = 22'h0000D7;  weight_ROM[13] = 22'h000079;  weight_ROM[14] = 22'h3FFAEB;  weight_ROM[15] = 22'h00039F;
		weight_ROM[16] = 22'h3FFA5D;  weight_ROM[17] = 22'h3FFAD6;  weight_ROM[18] = 22'h0005D2;  weight_ROM[19] = 22'h00072A;
		weight_ROM[20] = 22'h3FFDA6;  weight_ROM[21] = 22'h3FFA89;  weight_ROM[22] = 22'h00039B;  weight_ROM[23] = 22'h3FFDCD;
		weight_ROM[24] = 22'h3FF9A6;  weight_ROM[25] = 22'h00043A;  weight_ROM[26] = 22'h000190;  weight_ROM[27] = 22'h3FFF68;
		weight_ROM[28] = 22'h000457;  weight_ROM[29] = 22'h000898;  weight_ROM[30] = 22'h3FFE43;  weight_ROM[31] = 22'h00016F;
		weight_ROM[32] = 22'h000095;  weight_ROM[33] = 22'h3FFFB9;  weight_ROM[34] = 22'h3FFC68;  weight_ROM[35] = 22'h00068C;
		weight_ROM[36] = 22'h000111;  weight_ROM[37] = 22'h0000C2;  weight_ROM[38] = 22'h00055E;  weight_ROM[39] = 22'h0007EF;
		weight_ROM[40] = 22'h0003DC;  weight_ROM[41] = 22'h3FFC44;  weight_ROM[42] = 22'h00001C;  weight_ROM[43] = 22'h00003E;
		weight_ROM[44] = 22'h3FFED7;  weight_ROM[45] = 22'h3FFC04;  weight_ROM[46] = 22'h0006B2;  weight_ROM[47] = 22'h0005DB;
		weight_ROM[48] = 22'h0002E1;  weight_ROM[49] = 22'h3FFF1B;  weight_ROM[50] = 22'h000489;  weight_ROM[51] = 22'h0002F0;
		weight_ROM[52] = 22'h3FFFC8;  weight_ROM[53] = 22'h00068C;  weight_ROM[54] = 22'h3FFBF1;  weight_ROM[55] = 22'h3FF94C;
		weight_ROM[56] = 22'h000DE9;  weight_ROM[57] = 22'h3FFF5A;  weight_ROM[58] = 22'h3FFCF9;  weight_ROM[59] = 22'h3FF84B;
		weight_ROM[60] = 22'h0003B8;  weight_ROM[61] = 22'h3FFB62;  weight_ROM[62] = 22'h3FFAF3;  weight_ROM[63] = 22'h3FFCA2;
		weight_ROM[64] = 22'h3FF87A;  weight_ROM[65] = 22'h3FFE78;  weight_ROM[66] = 22'h00006B;  weight_ROM[67] = 22'h3FFE9B;
		weight_ROM[68] = 22'h3FF915;  weight_ROM[69] = 22'h3FFBDF;  weight_ROM[70] = 22'h000230;  weight_ROM[71] = 22'h3FFD72;
		weight_ROM[72] = 22'h0001FF;  weight_ROM[73] = 22'h000934;  weight_ROM[74] = 22'h3FFAF9;  weight_ROM[75] = 22'h0001EC;
		weight_ROM[76] = 22'h000284;  weight_ROM[77] = 22'h3FFA2F;  weight_ROM[78] = 22'h00001B;  weight_ROM[79] = 22'h000281;
		weight_ROM[80] = 22'h3FFB80;  weight_ROM[81] = 22'h3FFFAE;  weight_ROM[82] = 22'h3FFD29;  weight_ROM[83] = 22'h000308;
		weight_ROM[84] = 22'h3FF861;  weight_ROM[85] = 22'h3FF8CF;  weight_ROM[86] = 22'h000982;  weight_ROM[87] = 22'h3FFA34;
		weight_ROM[88] = 22'h00042E;  weight_ROM[89] = 22'h3FFB60;  weight_ROM[90] = 22'h3FF9C6;  weight_ROM[91] = 22'h3FFA7B;
		weight_ROM[92] = 22'h3FFB31;  weight_ROM[93] = 22'h3FFCE4;  weight_ROM[94] = 22'h3FF8A5;  weight_ROM[95] = 22'h3FFC0D;
		weight_ROM[96] = 22'h3FF1D1;  weight_ROM[97] = 22'h00014D;  weight_ROM[98] = 22'h000588;  weight_ROM[99] = 22'h3FF8BD;
		weight_ROM[100] = 22'h000205; weight_ROM[101] = 22'h000040; weight_ROM[102] = 22'h3FFB96; weight_ROM[103] = 22'h00009B;
		weight_ROM[104] = 22'h000000; weight_ROM[105] = 22'h0004EA; weight_ROM[106] = 22'h00030F; weight_ROM[107] = 22'h000B1D;
		weight_ROM[108] = 22'h3FFBE6; weight_ROM[109] = 22'h00020D; weight_ROM[110] = 22'h0000D1; weight_ROM[111] = 22'h000388;
		weight_ROM[112] = 22'h0000CB; weight_ROM[113] = 22'h3FFEA6; weight_ROM[114] = 22'h3FFB97; weight_ROM[115] = 22'h3FFD6D;
		weight_ROM[116] = 22'h3FFBB8; weight_ROM[117] = 22'h00064E; weight_ROM[118] = 22'h3FFE82; weight_ROM[119] = 22'h0000BE;
		weight_ROM[120] = 22'h3FFFCF; weight_ROM[121] = 22'h000204; weight_ROM[122] = 22'h3FFBF3; weight_ROM[123] = 22'h3FFDCD;
		weight_ROM[124] = 22'h0009A6; weight_ROM[125] = 22'h3FFD80; weight_ROM[126] = 22'h000048; weight_ROM[127] = 22'h000434;
		weight_ROM[128] = 22'h000628; weight_ROM[129] = 22'h3FFCF5; weight_ROM[130] = 22'h0003D1; weight_ROM[131] = 22'h00012F;
		weight_ROM[132] = 22'h000130; weight_ROM[133] = 22'h3FFE75; weight_ROM[134] = 22'h3FFB1D; weight_ROM[135] = 22'h0000EF;
		weight_ROM[136] = 22'h3FF7E0; weight_ROM[137] = 22'h000045; weight_ROM[138] = 22'h000223; weight_ROM[139] = 22'h3FFA54;
		weight_ROM[140] = 22'h3FFA3D; weight_ROM[141] = 22'h000753; weight_ROM[142] = 22'h0000A6; weight_ROM[143] = 22'h000464;
		weight_ROM[144] = 22'h000514; weight_ROM[145] = 22'h3FF8F5; weight_ROM[146] = 22'h0002E0; weight_ROM[147] = 22'h3FFCCC;
		weight_ROM[148] = 22'h3FFF13; weight_ROM[149] = 22'h000433; weight_ROM[150] = 22'h00019A; weight_ROM[151] = 22'h3FFBF6;
		weight_ROM[152] = 22'h0001D5; weight_ROM[153] = 22'h3FFDF0; weight_ROM[154] = 22'h3FFB17; weight_ROM[155] = 22'h000A3D;
		weight_ROM[156] = 22'h3FFCE1; weight_ROM[157] = 22'h0008C8; weight_ROM[158] = 22'h000370; weight_ROM[159] = 22'h0005BD;
		weight_ROM[160] = 22'h00005B; weight_ROM[161] = 22'h0003DE; weight_ROM[162] = 22'h0003BC; weight_ROM[163] = 22'h3FF69F;
		weight_ROM[164] = 22'h00035A; weight_ROM[165] = 22'h0001D8; weight_ROM[166] = 22'h3FFE4C; weight_ROM[167] = 22'h3FFAEE;
		weight_ROM[168] = 22'h3FFF41; weight_ROM[169] = 22'h0004F0; weight_ROM[170] = 22'h3FFF51; weight_ROM[171] = 22'h3FFC69;
		weight_ROM[172] = 22'h3FF9FA; weight_ROM[173] = 22'h0005C4; weight_ROM[174] = 22'h000768; weight_ROM[175] = 22'h00002E;
		weight_ROM[176] = 22'h3FF81C; weight_ROM[177] = 22'h3FFFBD; weight_ROM[178] = 22'h000069; weight_ROM[179] = 22'h0002DA;
		weight_ROM[180] = 22'h0003D3; weight_ROM[181] = 22'h3FFE80; weight_ROM[182] = 22'h0006F8; weight_ROM[183] = 22'h000685;
		weight_ROM[184] = 22'h3FFBF6; weight_ROM[185] = 22'h000385; weight_ROM[186] = 22'h0001D1; weight_ROM[187] = 22'h3FFE08;
		weight_ROM[188] = 22'h0003E1; weight_ROM[189] = 22'h3FFF9E; weight_ROM[190] = 22'h3FFF00; weight_ROM[191] = 22'h000362;
		weight_ROM[192] = 22'h000194; weight_ROM[193] = 22'h000618; weight_ROM[194] = 22'h3FF759; weight_ROM[195] = 22'h0004D9;
		weight_ROM[196] = 22'h3FFA95; weight_ROM[197] = 22'h00022F; weight_ROM[198] = 22'h3FFB2A; weight_ROM[199] = 22'h3FFD58;
		weight_ROM[200] = 22'h0003BD; weight_ROM[201] = 22'h3FFE98; weight_ROM[202] = 22'h0000E9; weight_ROM[203] = 22'h3FFACA;
		weight_ROM[204] = 22'h3FFA14; weight_ROM[205] = 22'h3FF9A6; weight_ROM[206] = 22'h000147; weight_ROM[207] = 22'h00053F;
		weight_ROM[208] = 22'h3FF91C; weight_ROM[209] = 22'h0005AA; weight_ROM[210] = 22'h3FFD5C; weight_ROM[211] = 22'h0005A7;
		weight_ROM[212] = 22'h3FFBE2; weight_ROM[213] = 22'h3FFCAA; weight_ROM[214] = 22'h0002F0; weight_ROM[215] = 22'h000640;
		weight_ROM[216] = 22'h3FFDA5; weight_ROM[217] = 22'h000159; weight_ROM[218] = 22'h000469; weight_ROM[219] = 22'h000640;
		weight_ROM[220] = 22'h0004CA; weight_ROM[221] = 22'h000286; weight_ROM[222] = 22'h3FFDE7; weight_ROM[223] = 22'h3FFBC2;
		weight_ROM[224] = 22'h000760;
		
		$display("✓ 하드코딩된 가중치 초기화 완료: 225개");
		$display("  Weight[0] = 0x%06X", weight_ROM[0]);
		$display("  Weight[1] = 0x%06X", weight_ROM[1]);
		$display("  Weight[224] = 0x%06X", weight_ROM[224]);
	end
	
endmodule