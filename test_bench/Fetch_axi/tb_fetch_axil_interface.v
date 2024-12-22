module tb_fetch_axil_interface (
    input wire clk,
    input wire rst_n,
    input wire stall,
    input wire boj,
    input wire [ADDR_WIDTH-1:0] boj_pc,
    input wire trap,
    input wire [ADDR_WIDTH-1:0] trap_pc,
    input wire flush,
    input wire [ADDR_WIDTH-1:0] redir_pc,
    output wire [ADDR_WIDTH-1:0] araddr,
    output wire arvalid,
    output wire arready,
    output wire [DATA_WIDTH-1:0] rdata,
    output wire rvalid,
    output wire rready,
    output wire if_pkt_valid,
    output wire [IF_PKT_WIDTH-1:0] if_pkt_data
);

// Local Parameters
localparam ADDR_WIDTH = 32;
localparam DATA_WIDTH = 32;
localparam IF_PKT_WIDTH = 64;

// Signals for Fetch module
wire [ADDR_WIDTH-1:0] fetch_araddr;
wire fetch_arvalid;
wire fetch_arready;
wire [DATA_WIDTH-1:0] fetch_rdata;
wire fetch_rvalid;
wire fetch_rready;
wire fetch_if_pkt_valid;
wire [IF_PKT_WIDTH-1:0] fetch_if_pkt_data;

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
assign if_pkt_valid = fetch_if_pkt_valid;
assign if_pkt_data = fetch_if_pkt_data;

// Instantiate Fetch module
Fetch #(
    .IF_PKT_WIDTH(IF_PKT_WIDTH)
) u_fetch (
    .clk(clk),
    .rst_n(rst_n),
    // Fetch-Decode Stage Interface
    .i_stall(stall),
    .o_if_pkt_valid(fetch_if_pkt_valid),
    .o_if_pkt_data(fetch_if_pkt_data),
    // PC Redirect Logic
    .i_boj(boj),
    .i_boj_pc(boj_pc),
    .i_trap(trap),
    .i_trap_pc(trap_pc),
    .i_flush(flush),
    .i_redir_pc(redir_pc),
    // CPU-Memory Interface
    .o_axil_araddr(fetch_araddr),
    .o_axil_arvalid(fetch_arvalid),
    .i_axil_arready(fetch_arready),
    .i_axil_rdata(fetch_rdata),
    .i_axil_rvalid(fetch_rvalid),
    .o_axil_rready(fetch_rready)
);

// Instantiate AXI-lite RAM module
/*
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
*/


initial begin
	$dumpfile("waves.vcd");
        $dumpvars(0, tb_fetch_axil_interface);
end




endmodule

