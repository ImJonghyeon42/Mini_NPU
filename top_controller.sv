`timescale 1ns/1ps
module top_controller(
	input logic clk,
	input logic rst,
	input logic start,
	input logic [7:0] rx_data,
	input logic  rx_valid,
	output logic [7:0] tx_data, // 차선 중심 위치 (0~29)
	output logic [7:0] confidence, //신뢰도 (두 차선의 평균 선명도)
	output logic done_signal
);

	logic start_signal;
	logic conv_engine_done;
	logic signed [17:0] max_val_reg;
	logic [7:0] max_position_reg;
	logic [5:0]  count;
	logic [255:0] flattened_pixel_data;
	logic [7:0] pixel_row_data [0:31];
	logic signed [17:0] result_data [0:29];
	
	parameter signed [17:0] THRESHOLD = 100;// 차선으로 인식할 최소 선명도 (노이즈 제거용)
	logic [7:0] peak1_pos, peak2_pos;
	logic signed [17:0] peak1_val, peak2_val;
	
	enum logic [3:0] {IDLE, RECEIVE_DATA, COMPUTE, FIND_LANES, CALC_CENTER, SEND_RESULT} state;
	
	always_comb begin
		for( int i=0;i<32;i++) flattened_pixel_data[i*8 +: 8] = pixel_row_data[i];
	end
	
	conv_engine U0(
		.clk, .rst,
		.start(start_signal),
		.pixel_row_data(flattened_pixel_data),
		.done_signal(conv_engine_done),
		.result_data
	);

	always_ff@(posedge clk) begin
		if(rst) begin
			max_val_reg <= '0;
			state <= IDLE;
			count <= '0;
			start_signal <= '0;
			done_signal <= '0;
			tx_data <= '0;
			pixel_row_data <= '{default: '0};
			confidence <= '0;
			peak1_pos <= '0;
			peak2_pos <= '0;
			peak1_val <= '0; peak2_val; <= '0;
		end
		else begin
			start_signal <= '0;
			done_signal <= 0;
			case(state) 
				IDLE : begin
				    if(start) begin 
				        state <= RECEIVE_DATA;
				        count <= '0;
				    end
				end
				RECEIVE_DATA : begin
					if(rx_valid) begin
						pixel_row_data[count[4:0]] <= rx_data;
						if(count[4:0] == 5'd31) begin
							state <= COMPUTE;
							count <= '0;
							start_signal <= '1;
						end
						else count <= count +6'd1;
					end
				end
				COMPUTE : begin
					if(conv_engine_done) begin
						state <= FIND_LANES;
						max_val_reg <= '0;
						peak1_val <= '0; peak2_val; <= '0;
						peak1_pos <= '0;
						peak2_pos <= '0;
						count <= 6'd0; // 6'd1 -> 6'd0
					end
				end
				FIND_MAX : begin
					logic signed [17:0] current_val = (result_data[count[4:0]] < 0) ? -result_data[count[4:0]] : result_data[count[4:0]];
					
					if(current_val > THRESHOLD) begin
						if(count[4:0] < 15) begin
							if(current_val > peak1_val) begin
								peak1_val <= current_val;
								peak1_pos <= count[4:0];
							end
						end
						else begin
							if(current_val > peak2_val) begin
								peak2_val <= current_val;
								peak2_pos <= count[4:0];
							end
						end
					end
					if(count[4:0] == 5'd29) begin
						state <= CALC_CENTER;
					end
					else begin
						count <= count + 6'd1;
					end
					
				CALC_CENTER: begin
					if(peak1_val > THRESHOLD && peak2_val > THRESHOLD) begin
						tx_data <= (peak1_pos + peak2_pos) >> 1; //나누기 2
						confidence <= ((peak1_val >> 1) + (peak2_val >> 1)[7:0];				
					end else begin
						tx_data <= 8'd0;
						confidence <= 8'd0;
					end
						state <= SEND_RESULT;		
				end
				SEND_RESULT: begin					
					done_signal <= 1'b1;
					state <= IDLE;
				end
			endcase
		end
	end
endmodule
	