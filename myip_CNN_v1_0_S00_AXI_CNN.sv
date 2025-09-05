`timescale 1 ns / 1 ps

module myip_CNN_v1_0_S00_AXI_CNN #
(
	// Users to add parameters here

	// User parameters ends
	// Do not modify the parameters beyond this line

	// Width of S_AXI data bus
	parameter integer C_S_AXI_DATA_WIDTH	= 32,
	// Width of S_AXI address bus
	parameter integer C_S_AXI_ADDR_WIDTH	= 5
)
(
	// Users to add ports here
	
	// ===== Register interface for CNN control (제어 전용) =====
	output wire [C_S_AXI_DATA_WIDTH-1:0] control_reg_out,   // Control register output (R/W)
	input wire [C_S_AXI_DATA_WIDTH-1:0] status_reg_in,      // Status register input (R/O)
	input wire [C_S_AXI_DATA_WIDTH-1:0] result_low_in,      // Result low 32-bit input (R/O)
	input wire [C_S_AXI_DATA_WIDTH-1:0] result_high_in,     // Result high 16-bit input (R/O)
	input wire [C_S_AXI_DATA_WIDTH-1:0] frame_count_in,     // Frame count input (R/O)
	input wire [C_S_AXI_DATA_WIDTH-1:0] error_code_in,      // Error code input (R/O)

	// User ports ends
	// Do not modify the ports beyond this line

	// ===== AXI4LITE Standard Interface =====
	// Global Clock Signal
	input wire  S_AXI_ACLK,
	// Global Reset Signal. This Signal is Active LOW
	input wire  S_AXI_ARESETN,
	// Write address (issued by master, acceped by Slave)
	input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
	// Write channel Protection type. This signal indicates the
	// privilege and security level of the transaction, and whether
	// the transaction is a data access or an instruction access.
	input wire [2 : 0] S_AXI_AWPROT,
	// Write address valid. This signal indicates that the master signaling
	// valid write address and control information.
	input wire  S_AXI_AWVALID,
	// Write address ready. This signal indicates that the slave is ready
	// to accept an address and associated control signals.
	output wire  S_AXI_AWREADY,
	// Write data (issued by master, acceped by Slave) 
	input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
	// Write strobes. This signal indicates which byte lanes hold
	// valid data. There is one write strobe bit for each eight
	// bits of the write data bus.    
	input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
	// Write valid. This signal indicates that valid write
	// data and strobes are available.
	input wire  S_AXI_WVALID,
	// Write ready. This signal indicates that the slave
	// can accept the write data.
	output wire  S_AXI_WREADY,
	// Write response. This signal indicates the status
	// of the write transaction.
	output wire [1 : 0] S_AXI_BRESP,
	// Write response valid. This signal indicates that the channel
	// is signaling a valid write response.
	output wire  S_AXI_BVALID,
	// Response ready. This signal indicates that the master
	// can accept a write response.
	input wire  S_AXI_BREADY,
	// Read address (issued by master, acceped by Slave)
	input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
	// Protection type. This signal indicates the privilege
	// and security level of the transaction, and whether the
	// transaction is a data access or an instruction access.
	input wire [2 : 0] S_AXI_ARPROT,
	// Read address valid. This signal indicates that the channel
	// is signaling valid read address and control information.
	input wire  S_AXI_ARVALID,
	// Read address ready. This signal indicates that the slave is
	// ready to accept an address and associated control signals.
	output wire  S_AXI_ARREADY,
	// Read data (issued by slave)
	output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
	// Read response. This signal indicates the status of the
	// read transfer.
	output wire [1 : 0] S_AXI_RRESP,
	// Read valid. This signal indicates that the channel is
	// signaling the required read data.
	output wire  S_AXI_RVALID,
	// Read ready. This signal indicates that the master can
	// accept the read data and response information.
	input wire  S_AXI_RREADY
);

	// ===== AXI4LITE Internal Signals =====
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
	reg  	axi_awready;
	reg  	axi_wready;
	reg [1 : 0] 	axi_bresp;
	reg  	axi_bvalid;
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
	reg  	axi_arready;
	reg [C_S_AXI_DATA_WIDTH-1 : 0] 	axi_rdata;
	reg [1 : 0] 	axi_rresp;
	reg  	axi_rvalid;

	// Example-specific design signals
	// local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	// ADDR_LSB is used for addressing 32/64 bit registers/memories
	// ADDR_LSB = 2 for 32 bits (n downto 2)
	// ADDR_LSB = 3 for 64 bits (n downto 3)
	localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
	localparam integer OPT_MEM_ADDR_BITS = 2;
	
	//----------------------------------------------
	//-- CNN Register Map (제어 전용, 픽셀 레지스터 제거)
	//------------------------------------------------
	// Address offsets (C 코드 #define과 일치)
	localparam REG_CONTROL_ADDR     = 3'h0;  // 0x00 - Control register (R/W)
	// PIXEL_DATA 레지스터 제거 (SPI 직접 연결로 불필요)
	localparam REG_STATUS_ADDR      = 3'h1;  // 0x04 - Status register (R/O)
	localparam REG_RESULT_LOW_ADDR  = 3'h2;  // 0x08 - Result low 32-bit (R/O)
	localparam REG_RESULT_HIGH_ADDR = 3'h3;  // 0x0C - Result high 16-bit (R/O)
	localparam REG_FRAME_COUNT_ADDR = 3'h4;  // 0x10 - Frame count (R/O)
	localparam REG_ERROR_CODE_ADDR  = 3'h5;  // 0x14 - Error code (R/O)
	
	//-- Slave Registers (6개 레지스터, 픽셀 레지스터 제거)
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0;  // Control register (R/W)
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg1;  // Status register (R/O) 
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg2;  // Result low (R/O)
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg3;  // Result high (R/O)
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg4;  // Frame count (R/O)
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg5;  // Error code (R/O)
	
	wire	 slv_reg_rden;
	wire	 slv_reg_wren;
	reg [C_S_AXI_DATA_WIDTH-1:0]	 reg_data_out;
	integer	 byte_index;
	reg	 aw_en;

	// ===== I/O Connections assignments =====
	assign S_AXI_AWREADY	= axi_awready;
	assign S_AXI_WREADY	= axi_wready;
	assign S_AXI_BRESP	= axi_bresp;
	assign S_AXI_BVALID	= axi_bvalid;
	assign S_AXI_ARREADY	= axi_arready;
	assign S_AXI_RDATA	= axi_rdata;
	assign S_AXI_RRESP	= axi_rresp;
	assign S_AXI_RVALID	= axi_rvalid;

	// ===== Register Interface Assignments (제어 전용) =====
	assign control_reg_out = slv_reg0;  // Control register output to CNN logic

	// ===== AXI4LITE Write Address Ready Generation =====
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awready <= 1'b0;
	      aw_en <= 1'b1;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          axi_awready <= 1'b1;
	          aw_en <= 1'b0;
	        end
	        else if (S_AXI_BREADY && axi_bvalid)
	            begin
	              aw_en <= 1'b1;
	              axi_awready <= 1'b0;
	            end
	      else           
	        begin
	          axi_awready <= 1'b0;
	        end
	    end 
	end       

	// ===== AXI4LITE Write Address Latching =====
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awaddr <= 0;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          axi_awaddr <= S_AXI_AWADDR;
	        end
	    end 
	end       

	// ===== AXI4LITE Write Ready Generation =====
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_wready <= 1'b0;
	    end 
	  else
	    begin    
	      if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en )
	        begin
	          axi_wready <= 1'b1;
	        end
	      else
	        begin
	          axi_wready <= 1'b0;
	        end
	    end 
	end       

	// ===== Memory Mapped Register Write Logic (제어 전용) =====
	assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      slv_reg0 <= 0;  // Control register
	      slv_reg1 <= 0;  // Status register (read-only)
	      slv_reg2 <= 0;  // Result low (read-only)
	      slv_reg3 <= 0;  // Result high (read-only)
	      slv_reg4 <= 0;  // Frame count (read-only)
	      slv_reg5 <= 0;  // Error code (read-only)
	    end 
	  else begin
	    if (slv_reg_wren)
	      begin
	        case ( axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	          REG_CONTROL_ADDR:  // Control register만 쓰기 가능
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          // 모든 다른 레지스터는 읽기 전용
	          default : begin
	                      // No write operation for read-only registers
	                    end
	        endcase
	      end
	      
	      // 읽기 전용 레지스터 실시간 업데이트
	      slv_reg1 <= status_reg_in;      // Status register
	      slv_reg2 <= result_low_in;      // Result low
	      slv_reg3 <= result_high_in;     // Result high
	      slv_reg4 <= frame_count_in;     // Frame count
	      slv_reg5 <= error_code_in;      // Error code
	  end
	end    

	// ===== AXI4LITE Write Response Logic =====
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_bvalid  <= 0;
	      axi_bresp   <= 2'b0;
	    end 
	  else
	    begin    
	      if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID)
	        begin
	          axi_bvalid <= 1'b1;
	          axi_bresp  <= 2'b0; // 'OKAY' response 
	        end                   
	      else
	        begin
	          if (S_AXI_BREADY && axi_bvalid) 
	            begin
	              axi_bvalid <= 1'b0; 
	            end  
	        end
	    end
	end   

	// ===== AXI4LITE Read Address Ready Generation =====
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_arready <= 1'b0;
	      axi_araddr  <= 32'b0;
	    end 
	  else
	    begin    
	      if (~axi_arready && S_AXI_ARVALID)
	        begin
	          axi_arready <= 1'b1;
	          axi_araddr  <= S_AXI_ARADDR;
	        end
	      else
	        begin
	          axi_arready <= 1'b0;
	        end
	    end 
	end       

	// ===== AXI4LITE Read Valid Generation =====
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_rvalid <= 0;
	      axi_rresp  <= 0;
	    end 
	  else
	    begin    
	      if (axi_arready && S_AXI_ARVALID && ~axi_rvalid)
	        begin
	          axi_rvalid <= 1'b1;
	          axi_rresp  <= 2'b0; // 'OKAY' response
	        end   
	      else if (axi_rvalid && S_AXI_RREADY)
	        begin
	          axi_rvalid <= 1'b0;
	        end                
	    end
	end    

	// ===== Memory Mapped Register Read Logic =====
	assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;
	
	always @(*)
	begin
	      // Address decoding for reading registers
	      case ( axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	        REG_CONTROL_ADDR     : reg_data_out <= slv_reg0;  // Control
	        REG_STATUS_ADDR      : reg_data_out <= slv_reg1;  // Status
	        REG_RESULT_LOW_ADDR  : reg_data_out <= slv_reg2;  // Result low
	        REG_RESULT_HIGH_ADDR : reg_data_out <= slv_reg3;  // Result high
	        REG_FRAME_COUNT_ADDR : reg_data_out <= slv_reg4;  // Frame count
	        REG_ERROR_CODE_ADDR  : reg_data_out <= slv_reg5;  // Error code
	        default : reg_data_out <= 0;
	      endcase
	end

	// ===== Output Register Read Data =====
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_rdata  <= 0;
	    end 
	  else
	    begin    
	      if (slv_reg_rden)
	        begin
	          axi_rdata <= reg_data_out;     // register read data
	        end   
	    end
	end    

	// ===== User Logic Area =====
	// Add user logic here

	// User logic ends

endmodule