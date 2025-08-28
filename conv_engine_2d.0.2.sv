`timescale 1ns/1ps
module conv_engine_2d #(
	parameter DATA_WIDTH  = 8,// 데이터 정밀도를 위한 비트 폭. 세부사항과 하드웨어 효율성의 균형을 맞춥니다.
	parameter IMG_SIZE    = 32,// 입력 특징 맵의 크기. 
	parameter KERNEL_SIZE  = 3 // 합성곱 필터의 크기. 
)(
	input	logic	clk,
	input	logic	rst,
	
	input	logic				start_signal,
	input	logic	[7:0]	pixel_in,
	input	logic				pixel_valid,
	
	output	logic	signed	[21:0]	result_out,
	output	logic							result_valid,
	output	logic							done_signal
);
	
	logic	[7:0]	line_buffer1	[0:IMG_SIZE-1];
	logic	[7:0]	line_buffer2	[0:IMG_SIZE-1];
	
	logic	[7:0]	pixel_window	[0 : KERNEL_SIZE-1][0 : KERNEL_SIZE-1];
	logic	signed	[7:0]	kernel	[0 : KERNEL_SIZE-1] [0 : KERNEL_SIZE-1]	=	'{{1, 0, -1},
																																{2, 0, -2},
																																{1, 0, -1}};
	logic	signed	[17:0]	mac_out	[0 :	KERNEL_SIZE-1] [0 : KERNEL_SIZE-1];
	
	logic	signed	[18 : 0]	sum_stage1	[0 : 4];
	logic	signed	[19 : 0]	sum_stage2	[0 : 2];
	logic	signed	[20 : 0]	sum_stage3	[0 : 1];
	
	logic	signed	[21 : 0]	final_result;
	
	logic	[$clog2(IMG_SIZE) - 1 : 0]	cnt_x;
	logic	[$clog2(IMG_SIZE)  - 1 : 0] cnt_y;
	
	logic	valid_in,valid_d1,valid_d2,valid_d3,valid_d4,valid_d5;
	
	enum	logic	[1:0]	{IDLE, PROCESSING, DONE} state, next_state;
	
	genvar	i,	j;
	generate
		for(i	=	0;	i	<	KERNEL_SIZE ;	i	=	i + 1) begin
			for(j = 0; j < KERNEL_SIZE ; j = j + 1) begin
				compute_unit	MAC_INST(
					.clk(clk),
					.rst(rst),
					.pixel_a(pixel_window	[i] [j]),
					.weight_b(kernel	[i] [j]),
					.sum_out(mac_out	[i] [j])
				);
			end
		end
	endgenerate
	
	always_ff@(posedge clk) begin
		if(rst) begin
			line_buffer1 <= '{default: '0};
			line_buffer2 <= '{default: '0};
			pixel_window <= '{default: '0};
		end
		else if(pixel_valid) begin
			line_buffer2[cnt_x]	<=	line_buffer1[cnt_x];	
			line_buffer1[cnt_x]	<=	pixel_in;
			
			for(int i = 0; i < KERNEL_SIZE ; i = i + 1) begin 
				pixel_window[i][0]	<=	pixel_window[i][1];					
				pixel_window[i][1]	<=	pixel_window[i][2];					
			end

			pixel_window[2][2] <= pixel_in;				
			pixel_window[1][2] <= line_buffer1[cnt_x];		
			pixel_window[0][2] <= line_buffer2[cnt_x];	
		end
	end
		
	always_ff@(posedge clk) begin
			if(rst) begin
				sum_stage1	<=	'{default: '0} ;
				sum_stage2	<=	'{default: '0} ;
				sum_stage3	<=	'{default: '0};
				
				final_result <= '0;
			end	else begin
				sum_stage1[0] <= mac_out[0][0] + mac_out[0][1];
				sum_stage1[1] <= mac_out[0][2] + mac_out[1][0];
				sum_stage1[2] <= mac_out[1][1] + mac_out[1][2]; 
				sum_stage1[3] <= mac_out[2][0] + mac_out[2][1];
				sum_stage1[4] <= mac_out[2][2];
					
				sum_stage2[0] <= sum_stage1[0] + sum_stage1[1];
				sum_stage2[1] <= sum_stage1[2] + sum_stage1[3];
				sum_stage2[2] <= sum_stage1[4];
				
				sum_stage3[0] <= sum_stage2[0] + sum_stage2[1];
				sum_stage3[1] <= sum_stage2[2];
					
				final_result <= sum_stage3[0] + sum_stage3[1];
			end
	end
	
	always_ff@(posedge clk) begin
		if(rst) state <= IDLE;
		else state <= next_state;
	end
	
	always_comb begin
		next_state = state; // 현재 상태 유지
		case(state) 
			IDLE : if(start_signal) next_state = PROCESSING;
			PROCESSING : if (pixel_valid && (cnt_x == IMG_SIZE -1 ) && (cnt_y == IMG_SIZE - 1)) next_state = DONE;
			DONE : next_state = IDLE;
		endcase
	end
	
	always_ff@(posedge clk) begin
		if(rst) begin
			cnt_x	<=	'0;
			cnt_y	<=	'0;	
		end else if(state == IDLE) begin
			cnt_x <= '0;
			cnt_y <= '0;
		end else if (pixel_valid && state == PROCESSING) begin
			if(cnt_x == IMG_SIZE - 1) begin
				cnt_x <= '0;
				cnt_y <= cnt_y + 1'd1;
			end else cnt_x <= cnt_x + 1'd1;
		end
	end
	
	assign valid_in = (state == PROCESSING) && (cnt_x >= 2) && (cnt_y >= 2);
	 always_ff @(posedge clk) begin
        if (rst) begin
            valid_d1 <= 1'b0;
            valid_d2 <= 1'b0;
            valid_d3 <= 1'b0;
            valid_d4 <= 1'b0;
			valid_d5 <= 1'b0;
            //result_valid <= 1'b0; 
        end else begin
            valid_d1 <= valid_in;
            valid_d2 <= valid_d1;
            valid_d3 <= valid_d2;
			valid_d4 <= valid_d3;
			valid_d5 <= valid_d4;
           // result_valid <= valid_d5; 
        end
    end
	
	assign  result_valid = valid_d5;
	assign result_out = final_result;
	assign done_signal = (state == DONE);
endmodule
	