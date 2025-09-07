`timescale 1ns/1ps
module Feature_Extractor(
	input logic clk,
	input logic rst,
	input logic start_signal,
	input logic pixel_valid_in,
	input logic [7:0] pixel_in,
	output logic signed [21:0] final_result_out,
	output logic final_result_valid,
	output logic final_done_signal
);
	logic signed [21:0] conv_result;
	logic conv_valid;
	logic conv_done_signal;
	
	logic Activation_valid;
	logic signed [21:0] Activation_result;
	
	// Conv 결과 버퍼 (30x30)
	logic signed [15:0] conv_buffer [0:29][0:29];
	logic [4:0] buffer_x, buffer_y;
	logic buffer_write_en;
	logic buffer_complete;
	
	// Max Pooling 입력 제어
	logic max_pool_start;
	logic conv_done_d1;
	logic [4:0] read_x, read_y;
	logic reading_buffer;
	logic read_valid;
	logic signed [21:0] buffered_data;
	
	conv_engine_2d	U0(
		.clk, .rst, .start_signal, 
		.pixel_in, .pixel_valid(pixel_valid_in),
		.result_out(conv_result), .result_valid(conv_valid),
		.done_signal(conv_done_signal)
	);
	
	Activation_Function U1(
		.clk, .rst,
		.pixel_valid(conv_valid), .pixel_in(conv_result),
		.result_valid(Activation_valid), .result_out(Activation_result)
	);
	
	// Conv 결과를 버퍼에 저장
	assign buffer_write_en = Activation_valid;
	
	always_ff @(posedge clk or negedge rst) begin
		if (!rst) begin
			buffer_x <= 5'b0;
			buffer_y <= 5'b0;
			buffer_complete <= 1'b0;
		end else if (buffer_write_en) begin
			conv_buffer[buffer_y][buffer_x] <= Activation_result[15:0];
			
			if (buffer_x == 29) begin
				buffer_x <= 5'b0;
				if (buffer_y == 29) begin
					buffer_y <= 5'b0;
					buffer_complete <= 1'b1;
					$display("[Feature_Extractor] Conv 버퍼 완료!");
				end else begin
					buffer_y <= buffer_y + 1;
				end
			end else begin
				buffer_x <= buffer_x + 1;
			end
		end else if (!conv_done_signal) begin
			buffer_complete <= 1'b0;
		end
	end
	
	// Conv 완료 시 Max Pooling 시작
	always_ff @(posedge clk or negedge rst) begin
		if (!rst) begin
			conv_done_d1 <= 1'b0;
		end else begin
			conv_done_d1 <= conv_done_signal;
		end
	end
	
	assign max_pool_start = buffer_complete && !conv_done_d1;
	
	// 버퍼에서 Max Pooling으로 데이터 순차 공급
	always_ff @(posedge clk or negedge rst) begin
		if (!rst) begin
			read_x <= 5'b0;
			read_y <= 5'b0;
			reading_buffer <= 1'b0;
			read_valid <= 1'b0;
		end else if (max_pool_start) begin
			reading_buffer <= 1'b1;
			read_x <= 5'b0;
			read_y <= 5'b0;
			read_valid <= 1'b1;
		end else if (reading_buffer) begin
			if (read_x == 29) begin
				read_x <= 5'b0;
				if (read_y == 29) begin
					read_y <= 5'b0;
					reading_buffer <= 1'b0;
					read_valid <= 1'b0;
				end else begin
					read_y <= read_y + 1;
				end
			end else begin
				read_x <= read_x + 1;
			end
		end
	end
	
	assign buffered_data = {{6{conv_buffer[read_y][read_x][15]}}, conv_buffer[read_y][read_x]};
	
	Max_Pooling #( .IMG_WIDTH(30), .IMG_HEIGHT(30))
	U2 (
		.clk, .rst, 
		.start_signal(max_pool_start),
		.pixel_in(buffered_data), 
		.pixel_valid(read_valid),
		.result_out(final_result_out), 
		.result_valid(final_result_valid), 
		.done_signal(final_done_signal)
	);
	
	// 디버그 출력
	always @(posedge clk) begin
		if (max_pool_start) begin
			$display("[Feature_Extractor] Max Pooling 시작!");
		end
		
		if (final_result_valid) begin
			$display("[Feature_Extractor] Max Pool 결과: %h", final_result_out);
		end
		
		if (final_done_signal) begin
			$display("[Feature_Extractor] 전체 완료! (225개 피처 생성)");
		end
	end
	
endmodule