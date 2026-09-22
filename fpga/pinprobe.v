// Map probe to an input pin using pinprobe.cst.
// LED0 blinks for a high input and stays on for a low input.
module pinprobe (
    input  wire clk,        // 27 MHz, pin 4 (known good)
    input  wire probe,      // the pin under test
    output wire led0        // pin 15 (known good), ACTIVE LOW
);
    reg [24:0] cnt = 25'd0;
    always @(posedge clk) cnt <= cnt + 25'd1;

    // led0 is active low, so 0 lights it.
    //   probe == 1 -> blink   (led0 follows a counter bit)
    //   probe == 0 -> solid on
    assign led0 = probe ? cnt[23] : 1'b0;
endmodule
