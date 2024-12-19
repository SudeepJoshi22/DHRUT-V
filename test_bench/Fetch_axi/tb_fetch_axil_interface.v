module tb_fetch_axil_interface (
    input wire clk,
    input wire rst_n,
    output wire [`ADDR_WIDTH-1:0] araddr,
    output wire arvalid,
    output wire arready,
    output wire [`DATA_WIDTH-1:0] rdata,
    output wire rvalid,
    output wire rready
);

// Local Parameters
localparam ADDR_WIDTH = `ADDR_WIDTH; 
localparam DATA_WIDTH = `DATA_WIDTH;

// Signals for Fetch module
wire [ADDR_WIDTH-1:0] fetch_araddr;
wire fetch_arvalid;
wire fetch_arready;
wire [DATA_WIDTH-1:0] fetch_rdata;
wire fetch_rvalid;
wire fetch_rready;

// Signals for AXI-lite RAM module
wire [ADDR_WIDTH-1:0] ram_araddr;
wire [2:0] ram_arprot = 3'b000; // Default value for ARPROT
wire ram_arvalid;
wire ram_arready;
wire [DATA_WIDTH-1:0] ram_rdata;
wire [1:0] ram_rresp; // Unused
wire ram_rvalid;
wire ram_rready;

// Debug Outputs
assign araddr = fetch_araddr;
assign arvalid = fetch_arvalid;
assign arready = fetch_arready;
assign rdata = fetch_rdata;
assign rvalid = fetch_rvalid;
assign rready = fetch_rready;

// Instantiate Fetch module
Fetch u_fetch (
    .clk(clk),
    .rst_n(rst_n),
    .o_axil_araddr(fetch_araddr),
    .o_axil_arvalid(fetch_arvalid),
    .i_axil_arready(fetch_arready),
    .i_axil_rdata(fetch_rdata),
    .i_axil_rvalid(fetch_rvalid),
    .o_axil_rready(fetch_rready)
);

// Instantiate AXI-lite RAM module
axil_ram #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
) u_axil_ram (
    .clk(clk),
    .rst(~rst_n), // Convert active-low reset to active-high
    .s_axil_araddr(fetch_araddr),
    .s_axil_arprot(ram_arprot),
    .s_axil_arvalid(fetch_arvalid),
    .s_axil_arready(fetch_arready),
    .s_axil_rdata(fetch_rdata),
    .s_axil_rresp(ram_rresp), // Unused
    .s_axil_rvalid(fetch_rvalid),
    .s_axil_rready(fetch_rready),
    .s_axil_awaddr(), // Unused
    .s_axil_awprot(), // Unused
    .s_axil_awvalid(), // Unused
    .s_axil_awready(), // Unused
    .s_axil_wdata(), // Unused
    .s_axil_wstrb(), // Unused
    .s_axil_wvalid(), // Unused
    .s_axil_wready(), // Unused
    .s_axil_bresp(), // Unused
    .s_axil_bvalid(), // Unused
    .s_axil_bready() // Unused
);

initial begin
	$dumpfile("waves.vcd");
	$dumpvars(0, tb_fetch_axil_interface);
end

endmodule

