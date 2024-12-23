module rom_axi_lite #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input wire clk,
    input wire resetn,
    // Address Read (AR) channel
    input wire [ADDR_WIDTH-1:0] i_axil_araddr,
    input wire                  i_axil_arvalid,
    output reg                  o_axil_arready,

    // Read Response (R) channel
    output reg [DATA_WIDTH-1:0] o_axil_rdata,
    output reg                  o_axil_rvalid,
    input wire                  i_axil_rready
);

    // ROM memory
    reg [DATA_WIDTH-1:0] rom [`PC_RESET + `INSTR_MEM_SIZE - 1:`PC_RESET];

    initial begin
    	$readmemh("instr_mem.mem", rom);
	//$readmemh("instr_mem.mem", mem, `PC_RESET, `PC_RESET + `INSTR_MEM_SIZE);
    end
    
    always @(posedge clk, resetn) begin
	if(!resetn) begin
		o_axil_arready <= 0;
		o_axil_rvalid <= 0;
		o_axil_rdata <= 0;
	end
	else begin
		o_axil_arready <= i_axil_rready;
		o_axil_rdata <= rom[i_axil_araddr];
		o_axil_rvalid <= i_axil_arvalid;
	end
    end
endmodule
