// Synchronous block-RAM slave. IDLE captures a request; RESP returns its data.
// s_ready requires a valid, unflushed request at the captured address.
// Only low address bits index storage; upper addresses alias.
module bram_slave #(
  parameter int    DATA_W    = 32,     // 64 for imem (2 instr/access), 32 for dmem
  parameter int    DEPTH     = 2048,   // entries, must be a power of two
  parameter bit    LOADABLE  = 1'b0,
  parameter bit    WRITABLE  = 1'b1,   // CPU writes; loader writes use LOADABLE
  parameter string INIT_FILE = ""      // $readmemh image, one entry per line
) (
  input  logic clk,
  input  logic rst_n,
  mem_if.slave bus,
  input logic loading, ld_en,
  input logic [31:0] ld_addr,
  input logic [7:0] ld_data
);

  // INIT_FILE minus a trailing ".hex", for building the per-lane filenames
  // in the writable branch below. Empty stays empty (no init).
  localparam string INIT_STEM =
      (INIT_FILE == "") ? "" :
      (INIT_FILE.len() > 4 && INIT_FILE.substr(INIT_FILE.len()-4, INIT_FILE.len()-1) == ".hex")
        ? INIT_FILE.substr(0, INIT_FILE.len()-5) : INIT_FILE;

  localparam int BYTES      = DATA_W / 8;
  localparam int BYTE_SHIFT = $clog2(BYTES);   // 3 for 64-bit, 2 for 32-bit
  localparam int IDX_W      = $clog2(DEPTH);

  logic [IDX_W-1:0] idx;
  logic             is_write;
  logic             accept;

  assign idx      = bus.m_addr[BYTE_SHIFT +: IDX_W];
  assign is_write = WRITABLE && (bus.m_wstrb != '0);
  assign accept   = bus.m_valid && !bus.m_flush;

  localparam logic S_IDLE = 1'b0;
  localparam logic S_RESP = 1'b1;

  logic              state_q;
  logic [31:0]       req_addr_q;
  logic [DATA_W-1:0] rdata_w;      // read data presented to the bus

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q    <= S_IDLE;
      req_addr_q <= '0;
    end else begin
      case (state_q)
        S_IDLE: if (accept) begin
                  req_addr_q <= bus.m_addr;
                  state_q    <= S_RESP;
                end
        S_RESP: state_q <= S_IDLE;
        default: state_q <= S_IDLE;
      endcase
    end
  end

  // Writable/loadable memory uses byte lanes for block-RAM inference.
  // Arrays have synchronous reads and no reset; writes commit on capture.
  generate
    if (WRITABLE || LOADABLE) begin : g_ram
      // Initialize each byte lane from the corresponding INIT_STEM_bN.hex file.
      for (genvar b = 0; b < BYTES; b++) begin : g_lane
        logic [7:0] mem_b [0:DEPTH-1];
        logic [7:0] rd_q;

        initial begin
          if (INIT_STEM != "")
            $readmemh($sformatf("%s_b%0d.hex", INIT_STEM, b), mem_b);
        end

        wire port_en = (LOADABLE && loading) ? ld_en : (state_q == S_IDLE && accept);
        wire [IDX_W-1:0] port_idx = (LOADABLE && loading) ? ld_addr[BYTE_SHIFT +: IDX_W] : idx;
        wire port_we = (LOADABLE && loading) ? (ld_addr[BYTE_SHIFT-1:0] == BYTE_SHIFT'(b))
                                             : (is_write && bus.m_wstrb[b]);
        wire [7:0] port_data = (LOADABLE && loading) ? ld_data : bus.m_wdata[b*8 +: 8];
        always_ff @(posedge clk) begin
          if (port_en) begin
            rd_q <= mem_b[port_idx];
            if (port_we) mem_b[port_idx] <= port_data;
          end
        end

        assign rdata_w[b*8 +: 8] = rd_q;
      end
    end
    else begin : g_rom
      logic [DATA_W-1:0] mem [0:DEPTH-1];
      logic [DATA_W-1:0] rd_q;

      initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
      end

      always_ff @(posedge clk) begin
        if (state_q == S_IDLE && accept) rd_q <= mem[idx];
      end

      assign rdata_w = rd_q;
    end
  endgenerate

  assign bus.s_ready = (state_q == S_RESP)
                       && bus.m_valid
                       && !bus.m_flush
                       && (bus.m_addr == req_addr_q);
  assign bus.s_rdata = rdata_w;

endmodule
