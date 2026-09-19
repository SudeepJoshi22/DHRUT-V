// Synthesis top for the Sipeed Tang Nano 20K.
//
// cpu_core cannot be a synthesis top on its own: its ports are SystemVerilog
// interfaces (mem_if.master imem_if / dmem_if), and an interface is not a set
// of wires until somebody instantiates it. With no parent, Yosys has nothing
// to bind them to -- hence "top-level module 'cpu_core' has unconnected
// interface port 'imem_if'" -- and it cannot resolve mem_if's DATA_W either,
// which would silently give imem the 32-bit default when the Phase-1b fetch
// path needs 64. tb_top.sv solves this for simulation; this file is the
// equivalent for hardware, and additionally terminates both buses in BSRAM
// and exposes scalar ports that tangnano20k.cst can actually constrain (a
// .cst can only reference flat ports, never an interface).
//
// Memory model matches the testbench: imem and dmem are SEPARATE arrays both
// initialised from the same program image, exactly as imem_driver.py and
// dmem_driver.py each load TEST_HEX into their own dict. Stores land only in
// dmem; self-modifying code is unsupported here just as it is in simulation.
module cpu_top #(
  // 32 KB each. imem is 64 bits wide (one access returns the two instructions
  // ifetch.sv expects in s_rdata[31:0] and s_rdata[63:32]), dmem is 32.
  parameter int    IMEM_DEPTH  = 4096,              // x 64-bit = 32 KB
  parameter int    DMEM_DEPTH  = 8192,              // x 32-bit = 32 KB
  parameter string IMEM_INIT   = "imem_init.hex",
  parameter string DMEM_INIT   = "dmem_init.hex",
  // Where the test program signals completion. tests/linker.ld places
  // .tohost at the first 0x1000 boundary after .text, so this varies per
  // program -- fpga/mkmem.py prints the real value out of the ELF.
  parameter logic [31:0] TOHOST_ADDR = 32'h8000_1000,
  // Software-driven LEDs: a store to this address latches its low bits onto
  // led[5:4]. See the snoop below and tests/asm/fpga_blink.S.
  parameter logic [31:0] LED_ADDR    = 32'h8000_0000 + DMEM_DEPTH * 4 - 4,
  parameter int    HEARTBEAT_BIT     = 23,          // 27 MHz >> 2^23 ~= 1.6 Hz
  parameter int    ACTIVITY_BIT      = 21,          // fetch-rate blink
  // External reset button (S1, pin 88).
  //
  // MEASURED ON HARDWARE, not assumed: the pinprobe design (fpga/pinprobe.v)
  // mirrored this pin onto the known-good led0 and showed it reads 0 when the
  // button is RELEASED and 1 when PRESSED. The button is therefore ACTIVE
  // HIGH, which is the opposite of the usual pull-up/press-to-ground wiring
  // this code originally assumed -- and that inversion held the core in reset
  // permanently, so the CPU only ran while the button was held down.
  //
  // Hence RST_BTN_ACTIVE_LOW = 0. Set it to 1 only for a board where the pin
  // idles high and the press pulls it to ground.
  parameter bit    USE_RST_BTN        = 1'b1,
  parameter bit    RST_BTN_ACTIVE_LOW = 1'b0
) (
  input  logic       clk,      // 27 MHz onboard oscillator
  // Reset button. NOT active-low despite what a name like rst_n_btn would
  // suggest -- on this board pressing drives it HIGH. RST_BTN_ACTIVE_LOW
  // above normalises whichever way it is wired.
  input  logic       rst_btn,
  output logic [5:0] led       // onboard LEDs, active low
);

  // ───────────────────────────────────────────────
  // Reset
  // ───────────────────────────────────────────────
  // The core resets asynchronously (always_ff @(posedge clk or negedge rst_n)),
  // so the reset must assert asynchronously but release synchronously to avoid
  // recovery/removal violations. A power-on counter also holds reset for the
  // first 256 cycles so the design comes up without touching the button.
  logic [7:0] por_cnt = 8'h00;
  always_ff @(posedge clk) begin
    if (!por_cnt[7]) por_cnt <= por_cnt + 8'd1;
  end

  // Button contribution to reset, normalised to active-low, or tied inactive
  // when the button is not trusted. btn_rst_n == 1 means "not resetting".
  logic btn_rst_n;
  assign btn_rst_n = !USE_RST_BTN       ? 1'b1
                   : RST_BTN_ACTIVE_LOW ? rst_btn
                                        : ~rst_btn;

  logic raw_rst_n;
  assign raw_rst_n = por_cnt[7] & btn_rst_n;

  logic [2:0] rst_sync_q;
  always_ff @(posedge clk or negedge raw_rst_n) begin
    if (!raw_rst_n) rst_sync_q <= 3'b000;
    else            rst_sync_q <= {rst_sync_q[1:0], 1'b1};
  end

  logic rst_n;
  assign rst_n = rst_sync_q[2];

  // ───────────────────────────────────────────────
  // Buses + core
  // ───────────────────────────────────────────────
  mem_if #(.DATA_W(64)) imem_if (.clk(clk), .rst_n(rst_n));
  mem_if #(.DATA_W(32)) dmem_if (.clk(clk), .rst_n(rst_n));

  cpu_core CORE (
    .clk     (clk),
    .rst_n   (rst_n),
    .imem_if (imem_if.master),
    .dmem_if (dmem_if.master)
  );

  bram_slave #(
    .DATA_W    (64),
    .DEPTH     (IMEM_DEPTH),
    .WRITABLE  (1'b0),
    .INIT_FILE (IMEM_INIT)
  ) IMEM (
    .clk   (clk),
    .rst_n (rst_n),
    .bus   (imem_if.slave)
  );

  bram_slave #(
    .DATA_W    (32),
    .DEPTH     (DMEM_DEPTH),
    .WRITABLE  (1'b1),
    .INIT_FILE (DMEM_INIT)
  ) DMEM (
    .clk   (clk),
    .rst_n (rst_n),
    .bus   (dmem_if.slave)
  );

  // ───────────────────────────────────────────────
  // Bringup status panel
  // ───────────────────────────────────────────────
  // Everything observed here is taken from the two buses at this level, so
  // cpu_core needs no debug ports added to it.
  //
  // Six LEDs have to cover four questions, so they are split 1+1+2+2:
  //   is the bitstream alive?      -> heartbeat, independent of the core, so
  //                                   "bad bitstream" and "stuck core" look
  //                                   different rather than identical
  //   is the core running or hung? -> fetch activity, which BLINKS while
  //                                   fetching and FREEZES on a hang. Sticky
  //                                   flags cannot show this: they say where a
  //                                   run stopped, never whether it is alive
  //   did it finish, and pass?     -> tohost stickies, the only indicator for
  //                                   existing tests (add.S etc.) that predate
  //                                   software-driven LEDs
  //   what is the program doing?   -> two LEDs the CPU drives directly
  //
  // Trading the two tohost LEDs for more software-driven bits is a one-line
  // change here if a given bringup session wants a wider pattern.
  logic [HEARTBEAT_BIT:0] hb_cnt_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) hb_cnt_q <= '0;
    else        hb_cnt_q <= hb_cnt_q + 1'b1;
  end

  logic fetch_fire, dmem_fire, dmem_wr_fire, tohost_hit, led_hit;
  assign fetch_fire   = imem_if.m_valid && imem_if.s_ready;
  assign dmem_fire    = dmem_if.m_valid && dmem_if.s_ready;
  assign dmem_wr_fire = dmem_fire && (dmem_if.m_wstrb != 4'b0000);
  assign tohost_hit   = dmem_wr_fire
                        && ({dmem_if.m_addr[31:2], 2'b00} == TOHOST_ADDR);
  assign led_hit      = dmem_wr_fire
                        && ({dmem_if.m_addr[31:2], 2'b00} == LED_ADDR);

  // Fetch-activity counter: advances only on a completed fetch, so the LED
  // blinks at a rate proportional to fetch throughput and stops dead the
  // moment the core stalls permanently.
  logic [ACTIVITY_BIT:0] act_cnt_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)          act_cnt_q <= '0;
    else if (fetch_fire) act_cnt_q <= act_cnt_q + 1'b1;
  end

  // Software-driven LEDs. This is deliberately a SNOOP on the existing dmem
  // write, not a peripheral: no address decoder, no second bus slave, no
  // change to bram_slave. The store also lands in RAM, harmlessly. Real MMIO
  // (and the decoder it needs) belongs with the UART work -- see
  // fpga/UART_PLAN.md.
  logic [1:0] user_led_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)      user_led_q <= 2'b00;
    else if (led_hit) user_led_q <= dmem_if.m_wdata[1:0];
  end

  logic done_q, pass_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      done_q <= 1'b0;
      pass_q <= 1'b0;
    end else if (tohost_hit) begin
      done_q <= 1'b1;
      // scoreboard.py treats tohost==1 as PASS; anything else is a failure
      // code, so light PASS only on an exact 1.
      if (dmem_if.m_wdata == 32'h0000_0001) pass_q <= 1'b1;
    end
  end

  logic [5:0] status;
  assign status[0]   = hb_cnt_q[HEARTBEAT_BIT];   // clock + bitstream alive
  assign status[1]   = act_cnt_q[ACTIVITY_BIT];   // fetching (frozen = hung)
  assign status[2]   = done_q;                    // tohost written
  assign status[3]   = pass_q;                    // tohost == 1 (PASS)
  assign status[5:4] = user_led_q;                // driven by the program

  // Onboard LEDs are active low.
  assign led = ~status;

endmodule
