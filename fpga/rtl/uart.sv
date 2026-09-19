// 8N1 UART, shared between the serial loader and CPU MMIO.
// CPU registers: TXDATA +0 (bit31 busy), RXDATA +4 (bit31 empty, read pops),
// STATUS +8 (bit0 tx_busy, bit1 rx_valid, bit2 sticky overrun, W1C bit2).
// Stores to a busy TXDATA wait; unmapped offsets respond with zero.
module uart #(
  parameter int DIVISOR = 234,  // 27 MHz / 115200, nearest integer
  parameter int RX_DEPTH = 8,
  parameter logic [31:0] BASE_ADDR = 32'h1000_0000
) (
  input logic clk,
  input logic rst_n,
  input logic uart_rx,
  output logic uart_tx,
  mem_if.slave bus,
  input logic loader_active,
  input logic ld_tx_valid,
  input logic [7:0] ld_tx_data,
  output logic ld_tx_ready,
  output logic ld_rx_valid,
  output logic [7:0] ld_rx_data,
  input logic ld_rx_ready
);
  localparam int CW = $clog2(DIVISOR);
  localparam int PW = $clog2(RX_DEPTH);
  initial begin
    if (DIVISOR < 4) $fatal(1, "UART divisor must be >=4");
    if (RX_DEPTH < 2 || (RX_DEPTH & (RX_DEPTH-1)) != 0)
      $fatal(1, "UART FIFO depth must be a power of two >=2");
  end

  logic tx_busy;
  logic [9:0] tx_shift;
  logic [3:0] tx_left;
  logic [CW-1:0] tx_timer;
  logic send;
  logic [7:0] send_data;
  assign uart_tx = tx_busy ? tx_shift[0] : 1'b1;
  assign ld_tx_ready = loader_active && !tx_busy;

  logic response;
  logic [31:0] response_addr, response_data;
  logic accept, is_write, tx_write;
  assign is_write = |bus.m_wstrb;
  assign tx_write = is_write && bus.m_addr == BASE_ADDR && bus.m_wstrb[0];
  assign accept = !loader_active && !response && bus.m_valid && !bus.m_flush
                  && (!tx_write || !tx_busy);
  assign bus.s_ready = response && !loader_active && bus.m_valid
                      && !bus.m_flush && bus.m_addr == response_addr;
  assign bus.s_rdata = response_data;
  assign send = loader_active ? (ld_tx_valid && ld_tx_ready) : (accept && tx_write);
  assign send_data = loader_active ? ld_tx_data : bus.m_wdata[7:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_busy <= 0;
      tx_shift <= '1;
      tx_left <= 0;
      tx_timer <= 0;
    end else if (send) begin
      tx_busy <= 1;
      tx_shift <= {1'b1, send_data, 1'b0};
      tx_left <= 10;
      tx_timer <= CW'(DIVISOR-1);
    end else if (tx_busy) begin
      if (tx_timer == 0) begin
        tx_shift <= {1'b1, tx_shift[9:1]};
        tx_left <= tx_left - 1'b1;
        tx_timer <= CW'(DIVISOR-1);
        if (tx_left == 1) tx_busy <= 0;
      end else tx_timer <= tx_timer - 1'b1;
    end
  end

  // Two-flop input synchronizer and midpoint sampling, LSB first.
  logic rx_meta, rx_sync;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin rx_meta <= 1; rx_sync <= 1; end
    else begin rx_meta <= uart_rx; rx_sync <= rx_meta; end
  end
  typedef enum logic [1:0] {RX_IDLE, RX_START, RX_BITS, RX_STOP} rx_state_t;
  rx_state_t rx_state;
  logic [CW-1:0] rx_timer;
  logic [2:0] rx_bit;
  logic [7:0] rx_shift;
  logic rx_done;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_state <= RX_IDLE;
      rx_timer <= 0;
      rx_bit <= 0;
      rx_shift <= 0;
      rx_done <= 0;
    end else begin
      rx_done <= 0;
      case (rx_state)
        RX_IDLE: if (!rx_sync) begin
          rx_state <= RX_START;
          rx_timer <= CW'(DIVISOR/2-1);
        end
        RX_START: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
          else if (rx_sync) rx_state <= RX_IDLE; // reject a short low glitch
          else begin
            rx_state <= RX_BITS;
            rx_timer <= CW'(DIVISOR-1);
            rx_bit <= 0;
          end
        RX_BITS: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
          else begin
            rx_shift[rx_bit] <= rx_sync;
            rx_timer <= CW'(DIVISOR-1);
            if (rx_bit == 7) rx_state <= RX_STOP;
            else rx_bit <= rx_bit + 1'b1;
          end
        RX_STOP: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
          else begin
            rx_done <= rx_sync; // bad stop bit: drop the frame
            rx_state <= RX_IDLE;
          end
        default: rx_state <= RX_IDLE;
      endcase
    end
  end

  logic [7:0] fifo [0:RX_DEPTH-1];
  logic [PW-1:0] rd_ptr, wr_ptr;
  logic [PW:0] count;
  logic pop, push, overrun, clear_overrun;
  assign ld_rx_valid = loader_active && count != 0;
  assign ld_rx_data = count != 0 ? fifo[rd_ptr] : 8'h00;
  assign pop = count != 0 && (loader_active ? ld_rx_ready
                    : (accept && !is_write && bus.m_addr == BASE_ADDR + 4));
  assign push = rx_done && (count < (PW+1)'(RX_DEPTH) || pop);
  assign clear_overrun = accept && is_write && bus.m_addr == BASE_ADDR + 8
                         && bus.m_wstrb[0] && bus.m_wdata[2];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_ptr <= 0;
      wr_ptr <= 0;
      count <= 0;
      overrun <= 0;
    end else begin
      if (clear_overrun) overrun <= 0;
      if (rx_done && !push) overrun <= 1;
      if (push) begin fifo[wr_ptr] <= rx_shift; wr_ptr <= wr_ptr + 1'b1; end
      if (pop) rd_ptr <= rd_ptr + 1'b1;
      case ({push, pop})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      response <= 0;
      response_addr <= 0;
      response_data <= 0;
    end else begin
      response <= 0;
      if (accept) begin
        response <= 1;
        response_addr <= bus.m_addr;
        case (bus.m_addr)
          BASE_ADDR: response_data <= {tx_busy, 31'b0};
          BASE_ADDR + 4: response_data <= {count == 0, 23'b0, count != 0 ? fifo[rd_ptr] : 8'h00};
          BASE_ADDR + 8: response_data <= {29'b0, overrun, count != 0, tx_busy};
          default: response_data <= 0;
        endcase
      end
    end
  end
endmodule
