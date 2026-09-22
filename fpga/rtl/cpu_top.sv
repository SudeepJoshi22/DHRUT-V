// Tang Nano 20K top: CPU, BRAM, UART, serial loader and status LEDs.
// Instruction and data memories use the same initial image. The loader writes
// both memories; CPU stores update data memory only.
module cpu_top #(
  // 32 KB each. imem is 64 bits wide (one access returns the two instructions
  // ifetch.sv expects in s_rdata[31:0] and s_rdata[63:32]), dmem is 32.
  parameter bit ENABLE_LOADER = 1'b1,
  parameter int UART_DIVISOR = 234,
  parameter int BOOT_CYCLES = 13500000,
  parameter int TIMEOUT_CYCLES = 27000000,
  parameter int    IMEM_DEPTH  = 4096,              // x 64-bit = 32 KB
  parameter int    DMEM_DEPTH  = 8192,              // x 32-bit = 32 KB
  parameter string IMEM_INIT   = "imem_init.hex",
  parameter string DMEM_INIT   = "dmem_init.hex",
  // Legacy baked-image completion address. Uploaded benchmarks use fixed MMIO
  // 0x1000_000c, so a moving ELF .tohost no longer requires re-synthesis.
  parameter logic [31:0] TOHOST_ADDR = 32'h8000_1000,
  // Software-driven LEDs: a store to this address latches its low bits onto
  // led[5:4]. See the snoop below and tests/asm/fpga_blink.S.
  parameter logic [31:0] LED_ADDR    = 32'h8000_0000 + DMEM_DEPTH * 4 - 4,
  parameter int    HEARTBEAT_BIT     = 23,          // 27 MHz >> 2^23 ~= 1.6 Hz
  parameter int    ACTIVITY_BIT      = 21,          // fetch-rate blink
  // S1 (pin 88) is active high: released=0, pressed=1.
  parameter bit    USE_RST_BTN        = 1'b1,
  parameter bit    RST_BTN_ACTIVE_LOW = 1'b0
) (
  input  logic       clk,      // 27 MHz onboard oscillator
  // Reset button. NOT active-low despite what a name like rst_n_btn would
  // suggest -- on this board pressing drives it HIGH. RST_BTN_ACTIVE_LOW
  // above normalises whichever way it is wired.
  input  logic       rst_btn,
  input logic uart_rx,
  output logic uart_tx,
  output logic [5:0] led       // onboard LEDs, active low
);

  // Power-on reset asserts asynchronously and releases through a synchronizer.
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
  logic sys_rst_n, loading, accepted, image_valid = 1'b1;
  logic ld_en;
  logic [31:0] ld_addr;
  logic [7:0] ld_data, rx_data, tx_data;
  logic rx_valid, rx_ready, tx_valid, tx_ready;
  assign sys_rst_n = rst_sync_q[2];
  assign rst_n = sys_rst_n && !loading;
  // A button reset cannot restore the baked image after a partial upload.
  // Preserve validity until reconfiguration or a successful replacement.
  always_ff @(posedge clk) begin
    if (ld_en) image_valid <= 0;
    if (accepted) image_valid <= 1;
  end
  generate if (ENABLE_LOADER) begin : g_loader
    prog_loader #(.CAPACITY((IMEM_DEPTH*8 < DMEM_DEPTH*4-4) ? IMEM_DEPTH*8 : DMEM_DEPTH*4-4),
                  .BOOT_CYCLES(BOOT_CYCLES), .TIMEOUT_CYCLES(TIMEOUT_CYCLES)) LOADER (
      .clk(clk), .rst_n(sys_rst_n), .image_valid(image_valid), .loading(loading), .accepted(accepted),
      .rx_valid(rx_valid), .rx_data(rx_data), .rx_ready(rx_ready),
      .tx_valid(tx_valid), .tx_data(tx_data), .tx_ready(tx_ready),
      .ld_en(ld_en), .ld_addr(ld_addr), .ld_data(ld_data));
  end else begin : g_no_loader
    assign loading = 0; assign accepted = 0; assign ld_en = 0;
    assign ld_addr = 0; assign ld_data = 0;
    assign rx_ready = 0; assign tx_valid = 0; assign tx_data = 0;
  end endgenerate

  // ───────────────────────────────────────────────
  // Buses + core
  // ───────────────────────────────────────────────
  mem_if #(.DATA_W(64)) imem_if (.clk(clk), .rst_n(rst_n));
  mem_if #(.DATA_W(32)) dmem_if (.clk(clk), .rst_n(rst_n));

  mem_if #(.DATA_W(32)) ram_if (.clk(clk), .rst_n(rst_n));
  mem_if #(.DATA_W(32)) uart_if (.clk(clk), .rst_n(sys_rst_n));
  dmem_splitter DBUS (.cpu(dmem_if.slave), .ram(ram_if.master), .uart(uart_if.master));
  uart #(.DIVISOR(UART_DIVISOR)) UART (
    .clk(clk), .rst_n(sys_rst_n), .uart_rx(uart_rx), .uart_tx(uart_tx), .bus(uart_if.slave),
    .loader_active(loading), .ld_tx_valid(tx_valid), .ld_tx_data(tx_data), .ld_tx_ready(tx_ready),
    .ld_rx_valid(rx_valid), .ld_rx_data(rx_data), .ld_rx_ready(rx_ready));

  cpu_core CORE (
    .clk     (clk),
    .rst_n   (rst_n),
    .imem_if (imem_if.master),
    .dmem_if (dmem_if.master)
  );

  bram_slave #(
    .DATA_W    (64),
    .DEPTH     (IMEM_DEPTH),
    .LOADABLE  (ENABLE_LOADER),
    .WRITABLE  (1'b0),
    .INIT_FILE (IMEM_INIT)
  ) IMEM (
    .clk   (clk),
    .rst_n (rst_n),
    .loading(loading), .ld_en(ld_en), .ld_addr(ld_addr), .ld_data(ld_data),
    .bus   (imem_if.slave)
  );

  bram_slave #(
    .DATA_W    (32),
    .DEPTH     (DMEM_DEPTH),
    .LOADABLE  (ENABLE_LOADER),
    .WRITABLE  (1'b1),
    .INIT_FILE (DMEM_INIT)
  ) DMEM (
    .clk   (clk),
    .rst_n (rst_n),
    .loading(loading), .ld_en(ld_en), .ld_addr(ld_addr), .ld_data(ld_data),
    .bus   (ram_if.slave)
  );

  // Status LEDs: heartbeat, fetch activity, completion, pass and two software bits.
  // CPU reset holds the status counters and completion flags clear.
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
                        && (({dmem_if.m_addr[31:2], 2'b00} == TOHOST_ADDR)
                            || dmem_if.m_addr == 32'h1000_000c);
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

  // Software-driven LEDs remain a snoop on the RAM write. The store lands in
  // RAM harmlessly; UART and completion signaling use decoded low-address
  // MMIO through dmem_splitter.
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
