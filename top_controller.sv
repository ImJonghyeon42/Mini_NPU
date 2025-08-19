`timescale 1ns/1ps
module top_controller(
	input logic clk,
	input logic rst,
	input logic start,
	input logic [7:0] rx_data,
	input logic  rx_valid,
	output logic [7:0] tx_data, // ���� �߽� ��ġ (0~29)
	output logic [7:0] confidence, //�ŷڵ� (�� ������ ��� ����)
	output logic done_signal
);

	logic start_signal;
	logic conv_engine_done;
	logic [5:0]  count;
	logic [255:0] flattened_pixel_data;
	logic [7:0] pixel_row_data [0:31];
	logic signed [17:0] result_data [0:29];
	
	parameter signed [17:0] THRESHOLD = 100;// �������� �ν��� �ּ� ���� (������ ���ſ�)
	localparam MAX_PEAKS = 4;
	
	logic [7:0] peak_positions [0:MAX_PEAKS -1];
	logic signed [17:0] peak_values [0 : MAX_PEAKS -1];
	logic [$clog2(MAX_PEAKS+1) : 0] peak_count;
	
	logic [7:0] best_peak1_pos, best_peak2_pos;
	logic signed [17:0] best_peak1_val, best_peak2_val;
	
	logic [7:0] last_center_pos;
	
	logic [7:0] min_diff_reg;
	logic [2:0] p1_reg, p2_reg;  // 3��Ʈ�� ��� (0~7)
	
	enum logic [3:0] {IDLE, RECEIVE_DATA, COMPUTE, FIND_LANES, SELECT_PAIR, CALC_CENTER, SEND_RESULT} state;
	
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
			state <= IDLE;
			count <= '0;
			start_signal <= '0;
			done_signal <= '0;
			tx_data <= '0;
			pixel_row_data <= '{default: '0};
			confidence <= '0;
			last_center_pos <= 8'd15;
			peak_count <= '0;
			peak_positions <= '{default : '0};
			peak_values <= '{default : '0};
	        best_peak1_pos <= '0; best_peak2_pos <= '0;
	        best_peak1_val <= '0; best_peak2_val <= '0;			
			min_diff_reg <= 8'd255;
			p1_reg <= '0; p2_reg <= '0;
		end
		else begin
			start_signal <= '0;
			done_signal <= 1'b0;
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
							start_signal <= 1'b1;
						end
						else count <= count + 6'd1;
					end
				end
				COMPUTE : begin
					if(conv_engine_done) begin
						state <= FIND_LANES;
						peak_count <= '0;
						for(int k=0; k<MAX_PEAKS; k++) begin
							peak_positions[k] <= '0;
							peak_values[k] <= '0;						
						end
						count <= 6'd0; 
					end
				end
				FIND_LANES : begin
					if(count[4:0] < 30) begin
						// THRESHOLD üũ �� ��ũ ����
						if(((result_data[count[4:0]] < 0) ? -result_data[count[4:0]] : result_data[count[4:0]]) > THRESHOLD && peak_count < MAX_PEAKS) begin
							peak_positions[peak_count] <= count[4:0];
							peak_values[peak_count] <= (result_data[count[4:0]] < 0) ? -result_data[count[4:0]] : result_data[count[4:0]];
							peak_count <= peak_count + 1'b1;
						end
						count <= count + 6'd1;
					end else begin
						// SELECT_PAIR �ʱ�ȭ
						state <= SELECT_PAIR;
						min_diff_reg <= 8'd255;
						p1_reg <= 3'd0;
						p2_reg <= 3'd1;  // p2�� �׻� p1+1���� ����
						best_peak1_pos <= '0;
						best_peak2_pos <= '0;
						best_peak1_val <= '0;
						best_peak2_val <= '0;
					end	
				end
				SELECT_PAIR : begin
					// ��ũ�� 2�� �̻� �־�� �� ���� ����
					if(peak_count >= 2) begin
						// p1�� ��ȿ ���� ���� �ִ��� Ȯ��
						if(p1_reg < peak_count - 1) begin
							// p2�� ��ȿ ���� ���� �ִ��� Ȯ��
							if(p2_reg < peak_count) begin
								// ���� ���� (p1_reg, p2_reg) �˻�
								// peak_positions�� 0�� �ƴ����� �̹� FIND_LANES���� �����
								
								// �߽� ��ġ ���
								logic [7:0] current_center;
								logic [7:0] diff;
								current_center <= (peak_positions[p1_reg] + peak_positions[p2_reg]) >> 1;
								diff <= (current_center > last_center_pos) ? 
								       (current_center - last_center_pos) : 
								       (last_center_pos - current_center);
								
								// �ּ� ���� ������Ʈ
								if(diff < min_diff_reg) begin
									min_diff_reg <= diff;
									best_peak1_pos <= peak_positions[p1_reg];
									best_peak2_pos <= peak_positions[p2_reg];
									best_peak1_val <= peak_values[p1_reg];
									best_peak2_val <= peak_values[p2_reg];
								end
								
								// p2�� �������� ���� (������ ����!)
								p2_reg <= p2_reg + 1;
								
							end else begin
								// p2 ���� �Ϸ� �� p1 ����, p2 �ʱ�ȭ
								p1_reg <= p1_reg + 1;
								p2_reg <= p1_reg + 2;  // ���ο� p1�� ���� p2 = (p1+1) + 1
							end
						end else begin
							// ��� ���� �˻� �Ϸ�
							state <= CALC_CENTER;
						end
					end else begin
						// ��ũ ���� �� �ٷ� CALC_CENTER��
						state <= CALC_CENTER;
					end
				end								
				CALC_CENTER: begin
					if(best_peak1_pos != '0 && best_peak2_pos != '0) begin
						tx_data <= (best_peak1_pos + best_peak2_pos) >> 1;
						confidence <= ((best_peak1_val > 255) ? 8'd127 : (best_peak1_val[7:0] >> 1)) + 
						              ((best_peak2_val > 255) ? 8'd127 : (best_peak2_val[7:0] >> 1));
					end else begin
						tx_data <= last_center_pos;
						confidence <= 8'd0;
					end
					state <= SEND_RESULT;		
				end
				SEND_RESULT: begin					
					done_signal <= 1'b1;
					state <= IDLE;
					last_center_pos <= tx_data;
				end
			endcase
		end
	end
endmodule