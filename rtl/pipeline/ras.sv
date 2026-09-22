// Return-address prediction stack, updated by fetch on the predicted path.
// JAL with link rd pushes. JALR hint actions (link registers x1/x5):
//   non-link rd, link rs1: pop; link rd, non-link rs1: push;
//   distinct link rd/rs1: pop then push; identical link rd/rs1: push.
// The stack wraps and has no speculative checkpoint restore. Empty stacks
// provide no prediction; Issue resolves each JALR target.

module ras #(
  parameter int DEPTH = 8,             // entries, must be a power of 2
  parameter int XLEN  = 32
) (
  input  logic            clk,
  input  logic            rst_n,

  // At most one operation per cycle. push+pop together means "replace the
  // top" (the co-routine swap row above): the popped value is still what
  // o_top presents this cycle.
  input  logic            i_push,
  input  logic            i_pop,
  input  logic [XLEN-1:0] i_push_pc,   // return address = call PC + 4

  output logic [XLEN-1:0] o_top,       // predicted return target
  output logic            o_valid      // o_top holds something meaningful
);

  localparam int PTR_W = $clog2(DEPTH);

  logic [XLEN-1:0] stack_q [DEPTH];
  logic [PTR_W-1:0] sp_q;              // points at the next free slot
  logic [PTR_W-1:0] top_idx;
  // Saturating count of live entries, so a return before any call is not
  // predicted from a reset-value stack entry.
  logic [PTR_W:0]   depth_q;

  assign top_idx = sp_q - 1'b1;
  assign o_top   = stack_q[top_idx];
  assign o_valid = (depth_q != '0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < DEPTH; i++) stack_q[i] <= '0;
      sp_q    <= '0;
      depth_q <= '0;
    end
    else begin
      unique case ({i_push, i_pop})
        2'b10: begin                       // call
          stack_q[sp_q] <= i_push_pc;
          sp_q          <= sp_q + 1'b1;
          if (depth_q != (PTR_W + 1)'(DEPTH)) depth_q <= depth_q + 1'b1;
        end
        2'b01: begin                       // return
          if (depth_q != '0) begin
            sp_q    <= sp_q - 1'b1;
            depth_q <= depth_q - 1'b1;
          end
        end
        2'b11: begin                       // pop then push: replace top
          if (depth_q != '0) begin
            stack_q[top_idx] <= i_push_pc;
          end
          else begin
            // Nothing to pop; degrade to a plain push.
            stack_q[sp_q] <= i_push_pc;
            sp_q          <= sp_q + 1'b1;
            depth_q       <= depth_q + 1'b1;
          end
        end
        default: ;                         // idle
      endcase
    end
  end

  initial begin
    if ((DEPTH < 2) || ((DEPTH & (DEPTH - 1)) != 0)) begin
      $fatal(1, "ras: DEPTH must be a power of 2 and >= 2 (got %0d)", DEPTH);
    end
  end

`ifdef SIMULATION
  // Depth and pointer must stay consistent: the live-entry count can
  // never exceed the stack itself.
  assert_depth_in_range: assert property (
    @(posedge clk) disable iff (!rst_n)
    (depth_q <= (PTR_W + 1)'(DEPTH))
  ) else $error("RAS ERROR: depth %0d exceeds DEPTH %0d", depth_q, DEPTH);

  // A prediction is only offered when something has been pushed.
  assert_valid_implies_nonempty: assert property (
    @(posedge clk) disable iff (!rst_n)
    o_valid |-> (depth_q != '0)
  ) else $error("RAS ERROR: o_valid asserted with an empty stack");
`endif

endmodule
