module flatten_buffer(
    input logic clk,
    input logic rst,
    input logic i_data_valid,
    input logic signed [21:0] i_data_in,
    output logic o_buffer_full,
    output logic signed [21:0] o_flattened_data [0:224]
);

parameter BUFFER_SIZE = 225;
logic [7:0] write_ptr;
logic buffer_full_reg;

always_ff @(posedge clk) begin
    if (rst) begin
        write_ptr <= 0;
        buffer_full_reg <= 0;
        for (int i = 0; i < BUFFER_SIZE; i++) begin
            o_flattened_data[i] <= 0;
        end
    end else begin
        if (i_data_valid && !buffer_full_reg) begin
            o_flattened_data[write_ptr] <= i_data_in;
            
            if (write_ptr == BUFFER_SIZE - 1) begin
                buffer_full_reg <= 1;
                $display("--- [DEBUG] flatten_buffer: Buffer FULL");
            end else begin
                write_ptr <= write_ptr + 1;
            end
        end
    end
end

assign o_buffer_full = buffer_full_reg;

endmodule