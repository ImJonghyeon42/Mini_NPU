module reset_sync(
    input logic clk,
    input logic async_rst_n,
    output logic sync_rst_n
);

    logic [2:0] rst_sync;
    
    always_ff @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            rst_sync <= 3'b000;
        end else begin
            rst_sync <= {rst_sync[1:0], 1'b1};
        end
    end
    
    assign sync_rst_n = rst_sync[2];
    
endmodule