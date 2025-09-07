module Seven_Segment_Display(
    input logic clk,
    input logic rst_n,
    input logic [15:0] display_value,
    output logic [6:0] seg_out,
    output logic [3:0] seg_sel
);

    logic [1:0] digit_sel;
    logic [3:0] current_digit;
    logic [19:0] refresh_counter;
    
    // 새로고침 카운터 (약 1kHz)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            refresh_counter <= 20'h0;
            digit_sel <= 2'b00;
        end else begin
            refresh_counter <= refresh_counter + 1;
            if (refresh_counter == 20'h0) begin
                digit_sel <= digit_sel + 1;
            end
        end
    end
    
    // 자릿수 선택
    always_comb begin
        case (digit_sel)
            2'b00: begin
                current_digit = display_value[3:0];
                seg_sel = 4'b1110;
            end
            2'b01: begin
                current_digit = display_value[7:4];
                seg_sel = 4'b1101;
            end
            2'b10: begin
                current_digit = display_value[11:8];
                seg_sel = 4'b1011;
            end
            2'b11: begin
                current_digit = display_value[15:12];
                seg_sel = 4'b0111;
            end
        endcase
    end
    
    // 7-Segment 디코더
    always_comb begin
        case (current_digit)
            4'h0: seg_out = 7'b1000000;  // 0
            4'h1: seg_out = 7'b1111001;  // 1
            4'h2: seg_out = 7'b0100100;  // 2
            4'h3: seg_out = 7'b0110000;  // 3
            4'h4: seg_out = 7'b0011001;  // 4
            4'h5: seg_out = 7'b0010010;  // 5
            4'h6: seg_out = 7'b0000010;  // 6
            4'h7: seg_out = 7'b1111000;  // 7
            4'h8: seg_out = 7'b0000000;  // 8
            4'h9: seg_out = 7'b0010000;  // 9
            4'hA: seg_out = 7'b0001000;  // A
            4'hB: seg_out = 7'b0000011;  // b
            4'hC: seg_out = 7'b1000110;  // C
            4'hD: seg_out = 7'b0100001;  // d
            4'hE: seg_out = 7'b0000110;  // E
            4'hF: seg_out = 7'b0001110;  // F
        endcase
    end
    
endmodule