`timescale 1 ns / 1 ps

module myip_CNN_v1_0_S00_AXI_CNN #
(
	parameter integer C_S_AXI_DATA_WIDTH	= 32,
	parameter integer C_S_AXI_ADDR_WIDTH	= 5
)
(
	// ===== Register interface for CNN control (픽셀 레지스터 복원) =====
	output wire [C_S_AXI_DATA_WIDTH-1:0] control_reg_out,   // Control register output (R/W)
	output wire [C_S_AXI_DATA_WIDTH-1:0] pixel_reg_out,     // Pixel data register output (W/O) - 복원
	input wire [C_S_AXI_DATA_WIDTH-1:0] status_reg_in,      // Status register input (R/O)
	input wire [C_S_AXI_DATA_WIDTH-1:0] result_low_in,      // Result low 32-bit input (R/O)
	input wire [C_S_AXI_DATA_WIDTH-1:0] result_high_in,     // Result high 16-bit input (R/O)
	input wire [C_S_AXI_DATA_WIDTH-1:0] frame_count_in,     // Frame count input (R/O)
	input wire [C_S_AXI_DATA_WIDTH-1:0] error_code_in,      // Error code input (R/O)

	// ===== AXI4LITE Standard Interface =====
	input wire  S_AXI_ACLK,
	input wire  S_AXI_ARESETN,
	input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
	input wire [2 : 0] S_AXI_AWPROT,
	input wire  S_AXI_AWVALID,
	output wire  S_AXI_AWREADY,
	input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
	input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
	input wire  S_AXI_WVALID,
	output wire  S_AXI_WREADY,
	output wire [1 : 0] S_AXI_BRESP,
	output wire  S_AXI_BVALID,
	input wire  S_AXI_BREADY,
	input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
	input wire [2 : 0] S_AXI_ARPROT,
	input wire  S_AXI_ARVALID,
	output wire  S_AXI_ARREADY,
	output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
	output wire [1 : 0] S_AXI_RRESP,
	output wire  S_AXI_RVALID,
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

	localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
	localparam integer OPT_MEM_ADDR_BITS = 2;
	
	//----------------------------------------------
	//-- CNN Register Map (픽셀 레지스터 포함)
	//------------------------------------------------
	localparam REG_CONTROL_ADDR     = 3'h0;  // 0x00 - Control register (R/W)
	localparam REG_PIXEL_DATA_ADDR  = 3'h1;  // 0x04 - Pixel data register (W/O) - 복원
	localparam REG_STATUS_ADDR      = 3'h2;  // 0x08 - Status register (R/O)
	localparam REG_RESULT_LOW_ADDR  = 3'h3;  // 0x0C - Result low 32-bit (R/O)
	localparam REG_RESULT_HIGH_ADDR = 3'h4;  // 0x10 - Result high 16-bit (R/O)
	localparam REG_FRAME_COUNT_ADDR = 3'h5;  // 0x14 - Frame count (R/O)
	localparam REG_ERROR_CODE_ADDR  = 3'h6;  // 0x18 - Error code (R/O)
	
	//-- Slave Registers (7개 레지스터)
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0;  // Control register (R/W)
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg1;  // Pixel data register (W/O) - 복원
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg2;  // Status register (R/O) 
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg3;  // Result low (R/O)
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg4;  // Result high (R/O)
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg5;  // Frame count (R/O)
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg6;  // Error code (R/O)
	
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

	// ===== Register Interface Assignments =====
	assign control_reg_out = slv_reg0;  // Control register output to CNN logic
	assign pixel_reg_out = slv_reg1;     // Pixel data register output to CNN logic - 복원

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

	// ===== Memory Mapped Register Write Logic =====
	assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      slv_reg0 <= 0;  // Control register
	      slv_reg1 <= 0;  // Pixel data register - 복원
	      slv_reg2 <= 0;  // Status register (read-only)
	      slv_reg3 <= 0;  // Result low (read-only)
	      slv_reg4 <= 0;  // Result high (read-only)
	      slv_reg5 <= 0;  // Frame count (read-only)
	      slv_reg6 <= 0;  // Error code (read-only)
	    end 
	  else begin
	    if (slv_reg_wren)
	      begin
	        case ( axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	          REG_CONTROL_ADDR:  // Control register is writable
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          REG_PIXEL_DATA_ADDR:  // Pixel data register is writable - 복원
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) begin
	                slv_reg1[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	              end  
	          // All other registers are read-only
	          default : begin
	                      // No write operation for read-only registers
	                    end
	        endcase
	      end
	      
	      // Update read-only registers from input signals (실시간 반영)
	      slv_reg2 <= status_reg_in;      // Status register
	      slv_reg3 <= result_low_in;      // Result low
	      slv_reg4 <= result_high_in;     // Result high
	      slv_reg5 <= frame_count_in;     // Frame count
	      slv_reg6 <= error_code_in;      // Error code
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
	        REG_PIXEL_DATA_ADDR  : reg_data_out <= slv_reg1;  // Pixel data - 복원
	        REG_STATUS_ADDR      : reg_data_out <= slv_reg2;  // Status
	        REG_RESULT_LOW_ADDR  : reg_data_out <= slv_reg3;  // Result low
	        REG_RESULT_HIGH_ADDR : reg_data_out <= slv_reg4;  // Result high
	        REG_FRAME_COUNT_ADDR : reg_data_out <= slv_reg5;  // Frame count
	        REG_ERROR_CODE_ADDR  : reg_data_out <= slv_reg6;  // Error code
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

endmodule