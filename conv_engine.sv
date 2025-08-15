`timescale 1ns/1ps
module conv_engine(
	input logic clk,
	input logic rst,
	input logic start,
	input logic signed [255:0] pixel_row_data,
	output logic done_signal,
	output logic signed [17:0] result_data [0:29]
);
	enum logic [1:0] {IDLE, LOAD, PROCESSING, DONE} state;
	logic [5:0] count;

	logic signed [7:0] pixel_window [0:31];
	logic wea;
	logic [7:0] dina;
	logic signed [7:0] doutb;
	
	logic signed [17:0] pipe1_out,pipe2_out,pipe3_out;
	logic signed [7:0] kernel [0:2] = '{-1,2,-1};
	
	data_memory U3(
		.clka(clk),
		.wea,
		.addra(count[4:0]),
		.dina,
		.clkb(clk),
		.addrb(count[4:0]),
		.doutb
	);
	
	compute_unit U0(
		.clk,.rst,
		.pixel_a(pixel_window[0]),
		.weight_b(kernel[0]),
		.sum_in('0),
		.sum_out(pipe1_out)
	);
	compute_unit U1(
		.clk,.rst,
		.pixel_a(pixel_window[1]),
		.weight_b(kernel[1]),
		.sum_in(pipe1_out),
		.sum_out(pipe2_out)
	);
	compute_unit U2(
		.clk,.rst,
		.pixel_a(pixel_window[2]),
		.weight_b(kernel[2]),
		.sum_in(pipe2_out),
		.sum_out(pipe3_out)
	);
	
	always_ff@(posedge clk) begin
		if(rst) begin
			state <= IDLE;
			count <= '0;
			done_signal <= '0;
			dina <= '0;
			wea <= '0;
			pixel_window <= '{default: '0};
			result_data <= '{default: '0};
		end else begin
		    done_signal <= '0;
			wea <= '0;
			case(state)
				IDLE : begin
					if(start) begin
						state <= LOAD;
						count <= 6'd0;
					end
				end
				LOAD: begin
					wea <= 1'b1;
					dina <= pixel_row_data[count[4:0]*8 +: 8];
					
					if(count[4:0] == 5'd31) begin
						state <= PROCESSING;
						count <= 6'd0;
						pixel_window <= '{default: '0};
					end
					else count <= count + 6'd1;
				end
				PROCESSING : begin
					if(count <= 6'd2) begin
						pixel_window[count[4:0]] <= doutb;
					end else begin
						for(int i=0;i<31;i=i+1) pixel_window[i] <= pixel_window[i+1];
						pixel_window[31] <= doutb;
					
						if(count >= 6'd5) begin // 파이프라인이 다 채워진 후 (2클럭 지연) 부터 결과 저장
							result_data[count[4:0] - 6'd5] <= pipe3_out;
						end
					end
					if(count[4:0] == 5'd31) state <= DONE;
					else count <= count + 6'd1;
				end
				DONE: begin
					done_signal <= 1'b1;
					state <= IDLE;
				end
			endcase
		end
	end
endmodule