`timescale 1ns/1ps
module conv_engine_2d(
	input	logic	clk,
	input	logic	rst,
	
	input	logic				start_signal,
	input	logic	[7:0]	pixel_in,
	input	logic				pixel_valid,
	
	output	logic	signed	[17:0]	result_out,
	output	logic							result_valid
);

	localparam IMG_WIDTH	=	32;	//이미지 가로 크기
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
	logic	signed	[17:0]	result_sum;
	
	logic	signed	[18 : 0]	sum_stage1	[0 : 3];
	logic	signed	[19 : 0]	sum_stage2	[0 : 1];
	logic	signed	[21 : 0]	final_result;
	
	logic	[$clog2(IMG_WIDTH) - 1 : 0]	cnt;
	
	enum	logic	[2:0]	{IDLE,	LOAD,	PROCESSING,	DONE} state;
	
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
			result_sum	<=	'0;
			state	<=	IDLE;
			cnt	<=	'0;
		end else begin
			case(state)
			IDLE: if(start_signal)	state	<=	LOAD;

			LOAD	:	begin
				if(pixel_valid) begin
					if(cnt < 2) begin
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
						
						pixel_window [0][0 : KERNEL_SIZE - 1]	<=	win_col0 [0		:	KERNEL_SIZE - 1];
						pixel_window [1][0 : KERNEL_SIZE - 1]	<=	win_col1 [0		:	KERNEL_SIZE - 1];
						pixel_window [2][0 : KERNEL_SIZE - 1]	<=	win_col2 [0		:	KERNEL_SIZE - 1];
						
					end
				end
				if(cnt	==	IMG_WIDTH - 1) begin
					cnt	<=	'0;
					state	<=	PROCESSING;
				end
				else begin
					cnt	<=	cnt	+	'1;
				end
			end	
			
			PROCESSING : begin	
						sum_stage1[0]	<=	mac_out [0] [0],	mac_out [0] [1];
						sum_stage1[1]	<=	mac_out [0] [2],	mac_out [1] [0];
						sum_stage1[2]	<=	mac_out [1] [1],	mac_out [1] [2];
						sum_stage1[3]	<=	mac_out [2] [0],	mac_out [2] [1];
					
						sum_stage2[0]	<=	sum_stage1[0] + sum_stage1[1];
						sum_stage2[1]	<=	sum_stage1[2] + sum_stage1[3];
					
					final_result	<=	{sum_stage2[0], 1'b0} + {sum_stage2[1], 1'b0} + {mac_out[2] [2], 3'b0};
				end
			
			end
		end
	