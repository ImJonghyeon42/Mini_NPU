module flatten_buffer(
    input logic clk,
    input logic rst,
    input logic i_data_valid,
    input logic signed [21:0] i_data_in,
    output logic o_buffer_full,
    output logic signed [21:0] o_flattened_data [0:224]
);

// ===== LUT 최적화: 파라미터와 카운터 단순화 =====
parameter BUFFER_SIZE = 225;
logic [7:0] write_ptr;     // 카운터 크기 축소
logic buffer_full_reg;

always_ff @(posedge clk or negedge rst) begin  
    if (!rst) begin  
        write_ptr <= 8'b0;
        buffer_full_reg <= 1'b0;
        // 초기화 루프 제거 (synthesis 최적화를 위해)
    end else begin
        if (i_data_valid && !buffer_full_reg) begin
            o_flattened_data[write_ptr] <= i_data_in;
            
            if (write_ptr == (BUFFER_SIZE - 1)) begin
                buffer_full_reg <= 1'b1;
                write_ptr <= 8'b0;  // 리셋
            end else begin
                write_ptr <= write_ptr + 1;
            end
        end
        
        // 버퍼 초기화 조건 단순화
        if (!i_data_valid && buffer_full_reg) begin
            buffer_full_reg <= 1'b0;
        end
    end
end

assign o_buffer_full = buffer_full_reg;

endmodule