`timescale 1 ns / 1 ps

module myip_CNN_v1_0 #
(
	parameter integer C_S00_AXI_CNN_DATA_WIDTH	= 32,
	parameter integer C_S00_AXI_CNN_ADDR_WIDTH	= 5
)
(
	// ===== 외부 연결용 포트들 (선택적) =====
	/*
	output wire              o_cnn_busy,          // CNN 처리 중
	output wire              o_cnn_done,          // CNN 완료
	output wire              o_frame_processing,  // 프레임 처리 중
	output wire [7:0]        o_debug_state,       // 디버그 상태
	output wire              o_cnn_interrupt,     // CNN 완료 인터럽트
	*/
	// ===== AXI Slave Bus Interface S00_AXI_CNN =====
	input wire  s00_axi_cnn_aclk,
	input wire  s00_axi_cnn_aresetn,
	input wire [C_S00_AXI_CNN_ADDR_WIDTH-1 : 0] s00_axi_cnn_awaddr,
	input wire [2 : 0] s00_axi_cnn_awprot,
	input wire  s00_axi_cnn_awvalid,
	output wire  s00_axi_cnn_awready,
	input wire [C_S00_AXI_CNN_DATA_WIDTH-1 : 0] s00_axi_cnn_wdata,
	input wire [(C_S00_AXI_CNN_DATA_WIDTH/8)-1 : 0] s00_axi_cnn_wstrb,
	input wire  s00_axi_cnn_wvalid,
	output wire  s00_axi_cnn_wready,
	output wire [1 : 0] s00_axi_cnn_bresp,
	output wire  s00_axi_cnn_bvalid,
	input wire  s00_axi_cnn_bready,
	input wire [C_S00_AXI_CNN_ADDR_WIDTH-1 : 0] s00_axi_cnn_araddr,
	input wire [2 : 0] s00_axi_cnn_arprot,
	input wire  s00_axi_cnn_arvalid,
	output wire  s00_axi_cnn_arready,
	output wire [C_S00_AXI_CNN_DATA_WIDTH-1 : 0] s00_axi_cnn_rdata,
	output wire [1 : 0] s00_axi_cnn_rresp,
	output wire  s00_axi_cnn_rvalid,
	input wire  s00_axi_cnn_rready
);

	// ===== Internal Signals =====
	
	// CNN Processing Core signals
    wire cnn_core_start;               
    wire cnn_core_reset;               
    wire cnn_core_busy;                
    wire cnn_core_result_valid;        // CNN에서만 구동
    wire signed [47:0] cnn_core_result;
	
	// MicroBlaze controlled pixel interface (복원)
    wire ctrl_pixel_valid;             
    wire [7:0] ctrl_pixel_data;        
    wire ctrl_frame_start;             
    wire ctrl_frame_complete;  
	
	// Status and counter signals
   wire [31:0] frame_counter;    
    wire [31:0] error_code;
	
	// AXI Lite register interface (픽셀 레지스터 복원)
    wire [31:0] axi_control_reg;   
    wire [31:0] axi_pixel_reg;     
    wire [31:0] axi_status_reg;    
    wire [31:0] axi_result_low;    
    wire [31:0] axi_result_high;   
    wire [31:0] axi_frame_count;   
    wire [31:0] axi_error_code;  

	// ===== CNN Processing Core (MicroBlaze 제어) =====
	
	CNN_TOP u_cnn_top (
        .clk(s00_axi_cnn_aclk),
        .rst(s00_axi_cnn_aresetn & ~cnn_core_reset),
        .start_signal(cnn_core_start),
        // Control Logic에서 오는 신호들
        .pixel_valid(ctrl_pixel_valid),
        .pixel_in(ctrl_pixel_data),
        // CNN에서만 구동하는 출력들
        .final_result_valid(cnn_core_result_valid),  // CNN만 구동
        .final_lane_result(cnn_core_result),
		.cnn_busy(cnn_core_busy)
	);

	// ===== Control Logic (픽셀 처리 복원) =====
	
	/*
	cnn_control_logic_simple u_control_logic (
		.clk(s00_axi_cnn_aclk),
		.rst_n(s00_axi_cnn_aresetn),
		
		// AXI Control Interface (픽셀 레지스터 포함)
        .control_reg(axi_control_reg),
        .pixel_reg(axi_pixel_reg),
        .status_reg(axi_status_reg),
        .frame_count_reg(axi_frame_count),
        .error_code_reg(axi_error_code),
		
		// CNN Interface
        .cnn_start(cnn_core_start),      // Control Logic만 구동
        .cnn_reset(cnn_core_reset),      // Control Logic만 구동
        .cnn_busy(cnn_core_busy),        // 입력 (읽기 전용)
        .cnn_result_valid(cnn_core_result_valid),
		
		// Pixel Interface (MicroBlaze controlled) - 복원
        .pixel_valid(ctrl_pixel_valid),      // Control Logic만 구동
        .pixel_data(ctrl_pixel_data),        // Control Logic만 구동
        .frame_start(ctrl_frame_start),      // Control Logic만 구동
        .frame_complete(ctrl_frame_complete), 
		
		// Output counters
        .frame_counter(frame_counter),
        .error_code(error_code)
	);
	*/

assign ctrl_pixel_valid = axi_control_reg[2];      // 직접 연결
assign ctrl_frame_start = axi_control_reg[3];      // 직접 연결  
assign ctrl_frame_complete = axi_control_reg[4];   // 직접 연결
assign ctrl_pixel_data = axi_pixel_reg[7:0];  

assign cnn_core_start = axi_control_reg[0];        // 직접 연결
assign cnn_core_reset = axi_control_reg[1];        // 직접 연결

assign frame_counter = 32'h12345678;
assign error_code = 32'h87654321;
	// ===== AXI Lite Register Mapping =====
	
	// Status register mapping (MicroBlaze 기반)
    assign axi_status_reg = {
        27'b0,                    // Reserved bits [31:5]
        ctrl_frame_complete,      // FRAME_COMPLETE [4]
        ctrl_frame_start,         // FRAME_START [3] 
        ctrl_pixel_valid,         // PIXEL_VALID [2]
        cnn_core_result_valid,    // RESULT_VALID [1] - CNN 출력 직접 사용
        cnn_core_busy             // CNN_BUSY [0] - CNN 출력 직접 사용
    };
	
	
	// Result register mapping
    assign axi_result_low = cnn_core_result[31:0];           
    assign axi_result_high = {16'b0, cnn_core_result[47:32]}; 
	
	// Frame count and error code
    assign axi_frame_count = frame_counter;
    assign axi_error_code = error_code;

	// ===== AXI Lite Slave Interface (픽셀 레지스터 포함) =====
	
	myip_CNN_v1_0_S00_AXI_CNN # ( 
        .C_S_AXI_DATA_WIDTH(C_S00_AXI_CNN_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_CNN_ADDR_WIDTH)
	) myip_CNN_v1_0_S00_AXI_CNN_inst (
        .S_AXI_ACLK(s00_axi_cnn_aclk),
        .S_AXI_ARESETN(s00_axi_cnn_aresetn),
		.S_AXI_AWADDR(s00_axi_cnn_awaddr),
		.S_AXI_AWPROT(s00_axi_cnn_awprot),
		.S_AXI_AWVALID(s00_axi_cnn_awvalid),
		.S_AXI_AWREADY(s00_axi_cnn_awready),
		.S_AXI_WDATA(s00_axi_cnn_wdata),
		.S_AXI_WSTRB(s00_axi_cnn_wstrb),
		.S_AXI_WVALID(s00_axi_cnn_wvalid),
		.S_AXI_WREADY(s00_axi_cnn_wready),
		.S_AXI_BRESP(s00_axi_cnn_bresp),
		.S_AXI_BVALID(s00_axi_cnn_bvalid),
		.S_AXI_BREADY(s00_axi_cnn_bready),
		.S_AXI_ARADDR(s00_axi_cnn_araddr),
		.S_AXI_ARPROT(s00_axi_cnn_arprot),
		.S_AXI_ARVALID(s00_axi_cnn_arvalid),
		.S_AXI_ARREADY(s00_axi_cnn_arready),
		.S_AXI_RDATA(s00_axi_cnn_rdata),
		.S_AXI_RRESP(s00_axi_cnn_rresp),
		.S_AXI_RVALID(s00_axi_cnn_rvalid),
		.S_AXI_RREADY(s00_axi_cnn_rready),
		
		// Register Interface (픽셀 레지스터 복원)
        .control_reg_out(axi_control_reg),
        .pixel_reg_out(axi_pixel_reg),
        .status_reg_in(axi_status_reg),
        .result_low_in(axi_result_low),
        .result_high_in(axi_result_high),
        .frame_count_in(axi_frame_count),
        .error_code_in(axi_error_code)
	);


	


endmodule