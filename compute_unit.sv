`timescale 1ns/1ps
module compute_unit (
    input logic clk, 
    input logic rst,
    input logic [7:0] pixel_a, 
    input logic signed [7:0] weight_b,
    input logic signed [17:0] sum_in,
    output logic signed [17:0] sum_out
);

    always_ff @(posedge clk) begin
        if (rst) begin
            sum_out <= '0;
        end else begin
            sum_out <= signed '(pixel_a) * weight_b + sum_in;
        end
    end
endmodule