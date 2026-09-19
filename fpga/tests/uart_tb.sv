module uart_tb;
  logic clk, rst_n, rx, loopback;
  wire tx;
  logic loader_active, ld_tx_valid, ld_rx_ready;
  logic [7:0] ld_tx_data;
  wire ld_tx_ready, ld_rx_valid;
  wire [7:0] ld_rx_data;
  mem_if bus(clk, rst_n);
  uart #(.DIVISOR(8), .RX_DEPTH(8)) DUT(
    .clk(clk), .rst_n(rst_n), .uart_rx(loopback ? tx : rx), .uart_tx(tx),
    .bus(bus), .loader_active(loader_active), .ld_tx_valid(ld_tx_valid),
    .ld_tx_data(ld_tx_data), .ld_tx_ready(ld_tx_ready), .ld_rx_valid(ld_rx_valid),
    .ld_rx_data(ld_rx_data), .ld_rx_ready(ld_rx_ready)
  );
endmodule
