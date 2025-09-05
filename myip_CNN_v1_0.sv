`timescale 1 ns / 1 ps

module myip_CNN_v1_0 #
(
	// Users to add parameters here
	
	// User parameters ends
	// Do not modify the parameters beyond this line
	
	// Parameters of Axi Slave Bus Interface S00_AXI_CNN
	parameter integer C_S00_AXI_CNN_DATA_WIDTH	= 32,
	parameter integer C_S00_AXI_CNN_ADDR_WIDTH	= 5
)
(
	// Users to add ports here
	// ===== 외부 Physical SPI 핀들 (핵심 수정) =====
    input wire  spi_sclk,
    input wire  spi_mosi,
    input wire  spi_cs_n,
	
	// ===== 상태 및 제어 신호들 =====
	output wire       o_cnn_busy,         // CNN 처리 중
	output wire       o_cnn_done,         // CNN 완료
	output wire       o_frame_processing, // 프레임 처리 중
	output wire [7:0] o_debug_state,      // 디버그 상태
	
	// ===== 인터럽트 신호 =====
	output wire       o_cnn_interrupt,    // CNN 완료 인터럽트
	
	// User ports ends
	// Do not modify the ports beyond this line
	
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
	
	// SPI 수신기 모듈과 내부 모듈들을 연결할 wire
    wire        pixel_valid_internal;
    wire [7:0]  pixel_data_internal;
    wire        frame_start_internal;
	// CNN Processing Core signals
	wire cnn_start;               // Start CNN processing (pulse)
	wire cnn_reset;               // CNN reset (pulse)
	wire cnn_busy;                // CNN is processing
	wire cnn_result_valid;        // CNN result is valid
	wire signed [47:0] cnn_result; // CNN final result (48-bit)
	
	// Status and counter signals
	wire [31:0] frame_counter;    // Processed frame counter
	wire [31:0] error_code;       // Error code register
	
	// AXI Lite register interface (제어 전용)
	wire [31:0] axi_control_reg;   // Control register (REG_CONTROL)
	wire [31:0] axi_status_reg;    // Status register (REG_STATUS) 
	wire [31:0] axi_result_low;    // Result low 32-bit (REG_RESULT_LOW)
	wire [31:0] axi_result_high;   // Result high 16-bit (REG_RESULT_HIGH)
	wire [31:0] axi_frame_count;   // Frame count (REG_FRAME_COUNT)
	wire [31:0] axi_error_code;    // Error code (REG_ERROR_CODE)

	
	// ===== 1. SPI 수신기 인스턴스화 (핵심 추가) =====
    simple_spi_receiver u_spi_receiver (
        .clk(s00_axi_cnn_aclk),
        .rst(~s00_axi_cnn_aresetn),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_cs_n(spi_cs_n),
        .o_pixel_data(pixel_data_internal),
        .o_pixel_valid(pixel_valid_internal),
        .o_frame_start(frame_start_internal)
    );
	// ===== CNN Processing Core (SPI 직접 연결) =====
	
	CNN_TOP u_cnn_top (
		.clk(s00_axi_cnn_aclk),
		.rst(~s00_axi_cnn_aresetn | cnn_reset),
		.start_signal(cnn_start),
		// SPI에서 직접 연결 (핵심 수정)
		.pixel_valid(pixel_valid_internal),
		.pixel_in(pixel_data_internal),
		.final_result_valid(cnn_result_valid),
		.final_lane_result(cnn_result)
	);

	// ===== Control Logic (제어 전용) =====
	
	cnn_control_logic_simple u_control_logic (
		.clk(s00_axi_cnn_aclk),
		.rst_n(s00_axi_cnn_aresetn),
		
		// AXI Control Interface (제어만)
		.control_reg(axi_control_reg),
		.status_reg(axi_status_reg),
		.frame_count_reg(axi_frame_count),
		.error_code_reg(axi_error_code),
		
		// CNN Interface
		.cnn_start(cnn_start),
		.cnn_reset(cnn_reset),
		.cnn_busy(cnn_busy),
		.cnn_result_valid(cnn_result_valid),
		
		// SPI Frame 모니터링
		.spi_frame_start(frame_start_internal),
		.spi_pixel_valid(pixel_valid_internal),
		
		// Output counters
		.frame_counter(frame_counter),
		.error_code(error_code)
	);

	// ===== AXI Lite Register Mapping =====
	
	// Status register mapping (SPI 기반 업데이트)
	assign axi_status_reg = {
		26'b0,                    // Reserved bits [31:6]
		spi_frame_start,          // SPI_FRAME_START [5]
		spi_pixel_valid,          // SPI_PIXEL_VALID [4]
		cnn_result_valid,         // RESULT_VALID [3]
		(cnn_busy || cnn_start),  // CNN_BUSY [2]
		1'b0,                     // Reserved [1]
		s00_axi_cnn_aresetn       // SYSTEM_READY [0]
	};
	
	// Result register mapping
	assign axi_result_low = cnn_result[31:0];           // Lower 32 bits
	assign axi_result_high = {16'b0, cnn_result[47:32]}; // Upper 16 bits
	
	// Frame count and error code
	assign axi_frame_count = frame_counter;
	assign axi_error_code = error_code;

	// ===== AXI Lite Slave Interface (제어 전용) =====
	
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
		
		// Register Interface (제어 전용)
		.control_reg_out(axi_control_reg),
		.status_reg_in(axi_status_reg),
		.result_low_in(cnn_result[31:0]),
		.result_high_in({16'b0, cnn_result[47:32]}),
		.frame_count_in(axi_frame_count),
		.error_code_in(axi_error_code)
	);

	// ===== 외부 포트 신호 할당 =====
	
	// 상태 출력 신호들
	assign o_cnn_busy = cnn_busy || cnn_start;
	assign o_cnn_done = cnn_result_valid;
	assign o_frame_processing = spi_frame_start || spi_pixel_valid;
	assign o_debug_state = {
		cnn_result_valid,         // [7]
		spi_frame_start,          // [6] 
		spi_pixel_valid,          // [5]
		cnn_busy,                 // [4]
		cnn_start,                // [3]
		1'b0,                     // [2] Reserved
		1'b0,                     // [1] Reserved
		s00_axi_cnn_aresetn       // [0]
	};
	
	// 인터럽트 신호 (CNN 완료시 발생)
	assign o_cnn_interrupt = cnn_result_valid;

	// ===== User Logic Area =====
	// Add user logic here

	// User logic ends

endmodule