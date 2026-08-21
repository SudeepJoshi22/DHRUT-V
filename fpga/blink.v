// Simple LED blink for the Sipeed Tang Nano 20K
// Onboard clock (XTAL) is 27MHz on this board.
// We divide it down so the LED blinks at a visible rate.

module blink (
    input  wire clk,      // 27MHz onboard oscillator
    output wire led0      // one onboard LED
);

    // 27,000,000 Hz clock. A 24-bit counter overflows roughly every
    // (2^24 / 27,000,000) ~= 0.62 seconds. We use the top bit as our
    // blink signal, giving a clearly visible on/off blink.
    reg [23:0] counter = 24'd0;

    always @(posedge clk) begin
        counter <= counter + 1'b1;
    end

    // Onboard LEDs on this board are active-LOW (0 = on, 1 = off),
    // so we invert the counter bit to get a clean visible blink.
    assign led0 = ~counter[23];

endmodule