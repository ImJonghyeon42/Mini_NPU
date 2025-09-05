`timescale 1ns/1ps
module Max_Pooling(
    input logic clk, 
    input logic rst,
    input logic start_signal,
    input logic pixel_valid,
    input logic signed [21:0] pixel_in,
    output logic signed [21:0] result_out,
    output logic result_valid,
    output logic done_signal
);
    parameter IMG_WIDTH = 30;
    parameter IMG_HEIGHT = 30;
    
    logic signed [21:0] image_buffer [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    logic [5:0] input_x, input_y;
    logic input_complete;
    logic [4:0] output_x, output_y;
    logic output_complete;
    
    enum logic [2:0] {IDLE, INPUT_PHASE, PROCESSING_PHASE, DONE} state, next_state;
    
    always_comb begin
        next_state = state;
        case(state)
            IDLE: if(start_signal) next_state = INPUT_PHASE;
            INPUT_PHASE: if(input_complete) next_state = PROCESSING_PHASE;
            PROCESSING_PHASE: if(output_complete) next_state = DONE;
            DONE: next_state = IDLE;
        endcase
    end
    
    always_ff@(posedge clk or negedge rst) begin  
        if(!rst) state <= IDLE;  
        else state <= next_state;
    end
    
    always_ff@(posedge clk or negedge rst) begin 
        if(!rst) begin 
            input_x <= '0;
            input_y <= '0;
            input_complete <= '0;
        end else if(state == INPUT_PHASE && pixel_valid) begin
            image_buffer[input_y][input_x] <= pixel_in;
            
            if(input_x == IMG_WIDTH-1) begin
                input_x <= '0;
                if(input_y == IMG_HEIGHT-1) begin
                    input_y <= '0;
                    input_complete <= 1'b1;
                end else begin
                    input_y <= input_y + 1;
                end
            end else begin
                input_x <= input_x + 1;
            end
        end else if(state == IDLE) begin
            input_complete <= '0;
            input_x <= '0;
            input_y <= '0;
        end
    end
    
    logic processing_enable;
    logic signed [21:0] block_00, block_01, block_10, block_11;
    logic signed [21:0] block_max;
    
    assign processing_enable = (state == PROCESSING_PHASE);
    
    always_comb begin
        if(processing_enable) begin
            block_00 = image_buffer[output_y*2][output_x*2];
            block_01 = image_buffer[output_y*2][output_x*2+1];
            block_10 = image_buffer[output_y*2+1][output_x*2];
            block_11 = image_buffer[output_y*2+1][output_x*2+1];
        end else begin
            block_00 = '0;
            block_01 = '0;
            block_10 = '0;
            block_11 = '0;
        end
    end
    
    logic signed [21:0] max_top, max_bot;
    always_comb begin
        max_top = (block_00 >= block_01) ? block_00 : block_01;
        max_bot = (block_10 >= block_11) ? block_10 : block_11;
        block_max = (max_top >= max_bot) ? max_top : max_bot;
    end
    
    always_ff@(posedge clk or negedge rst) begin  
        if(!rst) begin  
            output_x <= '0;
            output_y <= '0;
            output_complete <= '0;
            result_out <= '0;
            result_valid <= '0;
        end else if(state == PROCESSING_PHASE) begin
            result_valid <= 1'b1;
            result_out <= block_max;
            
            if(output_x == 14) begin
                output_x <= '0;
                if(output_y == 14) begin
                    output_y <= '0;
                    output_complete <= 1'b1;
                end else begin
                    output_y <= output_y + 1;
                end
            end else begin
                output_x <= output_x + 1;
            end
        end else begin
            result_valid <= '0;
            if(state == IDLE) begin
                output_complete <= '0;
                output_x <= '0;
                output_y <= '0;
            end
        end
    end
    
    always @(posedge clk) begin
        if (result_valid && output_y < 2) begin
            $display("BLOCK_POOL[%0t]: out(%0d,%0d) block=[%h,%h,%h,%h] → max=%h", 
                     $time, output_x, output_y, 
                     block_00, block_01, block_10, block_11, block_max);
        end
    end
    
    assign done_signal = (state == DONE);
    
endmodule