`timescale 1ns/1ps
module conv_engine_2d(
	input	logic	clk,
	input	logic	rst,
	
	input	logic				start_signal,
	input	logic	[7:0]	pixel_in,
	input	logic				pixel_valid,
	
	output	logic	signed	[21:0]	result_out,
	output	logic							result_valid,
	output	logic							done_signal
);

	localparam IMG_WIDTH	=	32;	//이미지 가로 크기
	localparam IMG_HEIGHT	=	32;	//이미지 세로 크기
	localparam KERNEL_SIZE	=	3;
	
	logic	[7:0]	line_buffer1	[0:IMG_WIDTH - 1];
	logic	[7:0]	line_buffer2	[0:IMG_WIDTH - 1];
	
	logic	[7:0]	pixel_window	[0 : KERNEL_SIZE - 1][0 : KERNEL_SIZE - 1];
	logic	[7:0]	win_col0	[0		:	KERNEL_SIZE - 1];
	logic	[7:0]	win_col1	[0		:	KERNEL_SIZE - 1];
	logic	[7:0]	win_col2	[0		:	KERNEL_SIZE - 1];
	
	logic	signed	[7:0]	kernel	[0 : KERNEL_SIZE - 1] [0 : KERNEL_SIZE - 1]	=	{{-1, 0, -1},
																																{-2, 0, -2},
																																{-1, 0, -1}};
	logic	signed	[17:0]	mac_out	[0 :	KERNEL_SIZE - 1] [0 : KERNEL_SIZE - 1];
	
	logic	signed	[18 : 0]	sum_stage1	[0 : 3];
	logic	signed	[19 : 0]	sum_stage2	[0 : 1];
	logic	signed	[21 : 0]	final_result;
	
	logic	[$clog2(IMG_WIDTH) - 1 : 0]	cnt_x;
	logic	[$clog2(IMG_HEIGHT)  - 1 : 0] cnt_y;
	
	enum	logic	[1:0]	{IDLE, PROCESSING, DONE} state, next_state;
	
	genvar	i,	j;
	generate
		for(i	=	0;	i	<	KERNEL_SIZE;	i	=	i + 1) begin
			for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
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
			win_col0 <= '{default: '0};
			win_col1 <= '{default: '0};
			win_col2 <= '{default: '0};
			line_buffer1 <= '{default: '0};
			line_buffer2 <= '{default: '0};
		end
		else if(pixel_valid) begin
			line_buffer2	<=	line_buffer1;
				
			line_buffer1[0]	<=	pixel_in;
			for(int i = 1; i < IMG_WIDTH; i = i + 1) begin 
				line_buffer1[i]	<=	line_buffer1[i - 1];					
			end
				
			win_col2[0] <=	pixel_in;
			win_col2[1]	<=	win_col2[0];
			win_col2[2]	<=	win_col2[1];
					
			win_col1[0] <=	line_buffer1[0];
			win_col1[1]	<=	win_col1[0];
			win_col1[2]	<=	win_col1[1];
					
			win_col0[0] <=	line_buffer2[0];
			win_col0[1]	<=	win_col0[0];
			win_col0[2]	<=	win_col0[1];
		end
	end
	
	always_ff@(posedge clk) begin
			if(rst) begin
				sum_stage1	<=	'{default: '0} ;
				sum_stage2	<=	'{default: '0} ;
				final_result <= '0;
			end	else begin
				sum_stage1[0]	<=	mac_out [0] [0] + mac_out [0] [1];
				sum_stage1[1]	<=	mac_out [0] [2] + mac_out [1] [0];
				sum_stage1[2]	<=	mac_out [1] [1] + mac_out [1] [2];
				sum_stage1[3]	<=	mac_out [2] [0] + mac_out [2] [1];
					
				sum_stage2[0]	<=	sum_stage1[0] + sum_stage1[1];
				sum_stage2[1]	<=	sum_stage1[2] + sum_stage1[3];
					
				final_result	<=	sum_stage2[0] + sum_stage2[1] + mac_out[2] [2];
			end
	end
	
	always_comb begin
		pixel_window[0] = win_col0;
		pixel_window[1] = win_col1;
		pixel_window[2] = win_col2;
	end
	
	always_ff@(posedge clk) begin
		if(rst) state <= IDLE;
		else state <= next_state;
	end
	
	always_comb begin
		next_state = state; // 현재 상태 유지
		case(state) 
			IDLE : if(start_signal) next_state = PROCESSING;
			PROCESSING : if (pixel_valid && (cnt_x == IMG_WIDTH - 1) && (cnt_y == IMG_HEIGHT - 1)) next_state = DONE;
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
			if(cnt_x == IMG_WIDTH - 1) begin
				cnt_x <= '0;
				cnt_y <= cnt_y + 1'd1;
			end else cnt_x <= cnt_x + 1'd1;
		end
	end
	
	assign result_valid = (state == PROCESSING) && (cnt_x >= 2) && (cnt_y >= 2);
	assign result_out = final_result;
	assign done_signal = (state == DONE);
endmodule
	