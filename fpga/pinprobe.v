// Pin probe: answers "what is actually on that pin?" using only led0, the one
// LED pin on this board we have confirmed (pin 15, from tangnano20k.cst).
//
// WHY THIS EXISTS
// cpu_top.cst's rst_n_btn (pin 88) and led[1..5] were extrapolated from
// led0=15, never checked against board documentation. A wrong reset pin holds
// the core in reset forever, which on the LED panel is indistinguishable from
// a dead CPU -- so verify the pin before debugging the CPU.
//
// HOW TO READ IT
//   led0 BLINKING (~1.6 Hz)  -> the probed pin reads 1
//   led0 SOLID ON          -> the probed pin reads 0
//   led0 SOLID OFF         -> no bitstream, no clock, or wrong led0 pin
//
// Press and release the button and watch led0 change:
//   blinks released, solid pressed -> active LOW  (standard: pull-up, press to GND)
//                                     => USE_RST_BTN=1, RST_BTN_ACTIVE_LOW=1
//   solid released, blinks pressed -> active HIGH (press to VCC)
//                                     => USE_RST_BTN=1, RST_BTN_ACTIVE_LOW=0
//   no change at all               -> pin 88 is not this button; leave
//                                     USE_RST_BTN=0 until the real pin is known
//
// Repoint IO_LOC "probe" in pinprobe.cst to test any other pin the same way.
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
