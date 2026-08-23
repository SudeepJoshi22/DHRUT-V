// Generic request/response memory interface.
//
// DATA_W parameterises the data path so instruction fetch can be widened
// independently of the data side: imem is instantiated at 64 (two
// instructions per access, see rtl/pipeline/ifetch.sv) while dmem keeps
// the 32-bit default. Address remains 32-bit in both cases.
interface mem_if #(
    parameter int DATA_W = 32
  ) (
    input logic clk,
    input logic rst_n
    );

  logic              m_valid;
  logic              s_ready;
  logic [31:0]       m_addr;
  logic [DATA_W-1:0] m_wdata;
  logic [DATA_W/8-1:0] m_wstrb;
  logic [DATA_W-1:0] s_rdata;
  logic              m_flush;

  // Master modport (CPU side)
  modport master (
    output m_valid,
    output m_addr,
    output m_wdata,
    output m_wstrb,
    output m_flush,
    input  s_ready,
    input  s_rdata
  );

  // Slave modport (memory side)
  modport slave (
    input  m_valid,
    input  m_addr,
    input  m_wdata,
    input  m_wstrb,
    input  m_flush,
    output s_ready,
    output s_rdata
  );

endinterface
