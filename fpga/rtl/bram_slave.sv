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
  parameter bit    WRITABLE  = 1'b1,   // 0 makes this a ROM (imem)
  parameter string INIT_FILE = ""      // $readmemh image, one entry per line
) (
  input  logic clk,
  input  logic rst_n,
  mem_if.slave bus
);

  localparam int BYTES      = DATA_W / 8;
  localparam int BYTE_SHIFT = $clog2(BYTES);   // 3 for 64-bit, 2 for 32-bit
  localparam int IDX_W      = $clog2(DEPTH);

  logic [DATA_W-1:0] mem [0:DEPTH-1];

  initial begin
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

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
  logic [DATA_W-1:0] rdata_q;

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

  // Single-port BSRAM access: the read and the byte-enable write share one
  // always_ff with no reset, which is what lets this infer as BSRAM rather
  // than a wall of FFs. A store commits here, at capture time; that is safe
  // because lsu.sv has no flush input and so never withdraws a store.
  always_ff @(posedge clk) begin
    if (state_q == S_IDLE && accept) begin
      rdata_q <= mem[idx];
      if (is_write) begin
        for (int b = 0; b < BYTES; b++) begin
          if (bus.m_wstrb[b]) mem[idx][b*8 +: 8] <= bus.m_wdata[b*8 +: 8];
        end
      end
    end
  end

  assign bus.s_ready = (state_q == S_RESP)
                       && bus.m_valid
                       && !bus.m_flush
                       && (bus.m_addr == req_addr_q);
  assign bus.s_rdata = rdata_q;

endmodule
