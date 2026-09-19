`timescale 1ns/1ps
module loader_check;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_btn = 1, uart_rx = 1;
  wire uart_tx;
  wire [5:0] led;
  localparam int N = @FRAME_SIZE@;
  localparam int EXPECTED_ERRORS = @EXPECTED_ERRORS@;
  byte unsigned frame [0:N-1];
  byte unsigned received[$];
  cpu_top #(.UART_DIVISOR(8), .BOOT_CYCLES(2000), .TIMEOUT_CYCLES(3000),
            .TOHOST_ADDR(32'h@TOHOST@)) dut (.*);
  initial begin
    byte unsigned value;
    forever begin
      @(negedge uart_tx);
      #120; // 1.5 bit periods, sample first data bit
      for (int b=0; b<8; b++) begin value[b] = uart_tx; #80; end
      if (!uart_tx) $fatal(1, "bad UART stop bit");
      received.push_back(value);

    end
  end
  task automatic send_byte(input byte unsigned value);
    @(negedge clk); uart_rx = 0;
    repeat (8) @(negedge clk);
    for (int b=0; b<8; b++) begin uart_rx=value[b]; repeat (8) @(negedge clk); end
    uart_rx=1; repeat (8) @(negedge clk);
  endtask
  task automatic expect_byte(input byte unsigned expected);
    byte unsigned value;
    wait(received.size() > 0);
    value = received.pop_front();
    if (value != expected) $fatal(1, "UART expected %x got %x", expected, value);
  endtask
  task automatic reset_board;
    @(negedge clk); rst_btn=1; uart_rx=1;
    repeat (150) @(negedge clk);
    received.delete();
    rst_btn=0;
    expect_byte("R");
  endtask
  task automatic header(input int unsigned length);
    send_byte("D"); send_byte("H"); send_byte("R"); send_byte("V");
    for (int b=0; b<4; b++) send_byte(length[b*8 +: 8]);
  endtask
  task automatic expect_failed;
    expect_byte("E");
    repeat (4000) @(negedge clk);
    if (dut.rst_n) $fatal(1, "failed loader released CPU");
  endtask
  task automatic result_line;
    string line;
    byte unsigned value;
    bit found;
    line=""; found=0;
    while (!found) begin
      wait(received.size() > 0);
      value=received.pop_front();
      if (value == 10) begin
        $display("UART: %s", line); $fflush();
        if (line.len() >= 13 && line.substr(0,12) == "DHRUTV_RESULT") begin
          if (line.substr(line.len()-9, line.len()-2) != $sformatf("errors=%0d", EXPECTED_ERRORS))
            $fatal(1, "benchmark failed: %s", line);
          found=1;
        end
        line="";
      end else line={line,value};
    end
    wait(dut.done_q);
    if (dut.pass_q != (EXPECTED_ERRORS == 0))
      $fatal(1, "completion status did not match expected errors");
  endtask
  initial begin
    $readmemh("frame.hex",frame);
    reset_board();
    result_line(); // timeout fallback runs the baked image and prints
    reset_board(); header(0); expect_failed();
    reset_board(); header(32765); expect_failed();
    reset_board(); header(16); send_byte(8'hff); expect_failed();
    if (dut.image_valid) $fatal(1, "partial write did not invalidate image");
    reset_board(); expect_failed(); // reset cannot resurrect corrupt RAM
    reset_board(); header(1); send_byte(8'h55);
    repeat (4) send_byte(0);
    expect_failed(); // checksum error
    reset_board();
    for (int n=0; n<N; n++) send_byte(frame[n]);
    expect_byte("K");
    result_line();
    if (!dut.image_valid) $fatal(1, "accepted image remains invalid");
    $display("PASS loader: fallback, bounds, interruption, checksum, reset recovery, CPU UART output");
    $finish;
  end
  initial begin #100000000; $fatal(1,"loader watchdog"); end
endmodule
