// On-chip block-RAM slave for mem_if.
//
// Replaces the cocotb imem/dmem drivers for FPGA builds. The handshake
// contract it has to honour, taken from the masters:
//
//   ifetch.sv : fetch_fire = m_valid && s_ready, and instr0/instr1 are
//               taken straight from s_rdata on that same cycle.
//   lsu.sv    : o_valid = valid_q && s_ready, o_load_data from s_rdata,
//               again same cycle.
//
// So s_rdata MUST already hold the data on the cycle s_ready is high --
// this is not a "ready now, data next cycle" bus.
//
// Gowin BSRAM is synchronous (address in on a clock edge, data out the
// cycle after), so the response cannot be combinational. The FSM below
// therefore runs one wait state: the request is captured (and the BRAM
// read issued) in IDLE, and answered in RESP when dout is valid. Both
// masters hold m_addr stable while waiting -- ifetch's pc_q only advances
// on fetch_fire, and lsu's valid_q only clears on s_ready -- so holding a
// request across a cycle is safe.
//
// Withdrawal: s_ready is qualified on the master still asserting m_valid
// for the SAME address and not flushing, mirroring the "don't answer a
// fetch the core has withdrawn" rule in imem_driver.py. Without it, a
// mispredict flush during the wait state would hand back data fetched for
// the old block while pc_q has already moved -- the core would pair the
// new PC with the old instruction. There is no combinational loop: m_valid
// depends only on registered state (i_flush, fq_full), never on s_ready.
//
// Addressing: only the low bits of m_addr index the array, so the upper
// bits alias. That is what puts the 0x8000_0000 link address at index 0
// with no decoder. It also means the image must fit in DEPTH entries.
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

  // Storage. Two shapes, because Yosys' Gowin BRAM rules
  // (tools/oss-cad-suite/share/yosys/gowin/brams.txt) have no mapping for a
  // read combined with a BYTE-MASKED PARTIAL write of a wider word. Written
  // that way the whole array falls into fabric -- a 2048x32 dmem costs a few
  // thousand LUT4s of storage plus a ~2048:1 address mux per output bit.
  // Splitting it into byte-wide arrays, each written as a WHOLE word under
  // its own strobe, is the form the rules do match.
  //
  // A non-loadable ROM keeps the single-array shape. Loadable IMEM uses
  // byte lanes too, so a received byte writes through the same single port.
  //
  // Both paths preserve what inference depends on -- synchronous read, and
  // NO reset anywhere on the array -- and both keep the original timing: a
  // store commits at capture time, which is safe because lsu.sv has no flush
  // input and so never withdraws a store.
  generate
    if (WRITABLE || LOADABLE) begin : g_ram
      // Each lane loads its OWN image. Splitting a word-wide $readmemh into
      // lanes in an initial block does not elaborate ("evaluation does not
      // resolve to a constant in design initialization"), so fpga/mkmem.py
      // emits one file per lane: INIT_FILE "dmem_init.hex" is read here as
      // "dmem_init_b0.hex" .. "b3.hex". INIT_STEM carries the name without
      // its .hex suffix so the lane index can be appended.
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
