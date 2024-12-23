module tb_fetch_axi_interface (
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
localparam ID_WIDTH = 8;

// Signals for Fetch module
wire [ADDR_WIDTH-1:0] fetch_araddr;
wire fetch_arvalid;
wire fetch_arready;
wire [DATA_WIDTH-1:0] fetch_rdata;
wire fetch_rvalid;
wire fetch_rready;
wire fetch_if_pkt_valid;
wire [IF_PKT_WIDTH-1:0] fetch_if_pkt_data;

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

// Instantiate ROM module (replacing AXI RAM with ROM)
rom_axi_lite #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
) u_rom_axi_lite (
.clk(clk),
.resetn(rst_n),
    .i_axil_araddr(fetch_araddr),
    .i_axil_arvalid(fetch_arvalid),
    .o_axil_arready(fetch_arready),
    .o_axil_rdata(fetch_rdata),
    .o_axil_rvalid(fetch_rvalid),
    .i_axil_rready(fetch_rready)
);

initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb_fetch_axi_interface);
end

endmodule

