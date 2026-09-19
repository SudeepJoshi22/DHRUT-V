// Byte stream: DHRV, LE32 length, payload, LE32 additive checksum.
// Once a header is recognized, any failure requires reset. Never boot a
// partial image. image_valid survives button resets in the top-level wrapper.
module prog_loader #(
  parameter int CAPACITY = 32764,
  parameter int BOOT_CYCLES = 13500000,
  parameter int TIMEOUT_CYCLES = 27000000
)(
  input logic clk, rst_n, image_valid,
  output logic loading, accepted,
  input logic rx_valid,
  input logic [7:0] rx_data,
  output logic rx_ready,
  output logic tx_valid,
  output logic [7:0] tx_data,
  input logic tx_ready,
  output logic ld_en,
  output logic [31:0] ld_addr,
  output logic [7:0] ld_data
);
  typedef enum logic [3:0] {HELLO, MAGIC, LENGTH, PAYLOAD, CHECKSUM, ACK, DRAIN, RUN, FAILED} state_t;
  state_t state;
  logic [1:0] pos;
  logic [31:0] timer, length, offset, sum, received;
  logic good;
  logic [7:0] magic_byte;
  always_comb begin
    case (pos)
      0: magic_byte = "D";
      1: magic_byte = "H";
      2: magic_byte = "R";
      default: magic_byte = "V";
    endcase
  end
  assign loading = state != RUN;
  assign rx_ready = state == MAGIC || state == LENGTH || state == PAYLOAD || state == CHECKSUM;
  assign tx_valid = state == ACK || state == HELLO;
  assign tx_data = state == HELLO ? "R" : (good ? "K" : "E");
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= HELLO;
      pos <= 0; timer <= 0; length <= 0; offset <= 0;
      sum <= 0; received <= 0; good <= 0; accepted <= 0;
      ld_en <= 0; ld_addr <= 0; ld_data <= 0;
    end else begin
      ld_en <= 0;
      accepted <= 0;
      case (state)
        HELLO: if (tx_ready) state <= MAGIC;
        MAGIC: begin
          timer <= timer + 1;
          if (rx_valid) begin
            if (rx_data == magic_byte) begin
              pos <= pos + 1'b1;
              if (pos == 3) begin state <= LENGTH; timer <= 0; end
            end else pos <= rx_data == "D" ? 1 : 0;
          end
          if (timer >= BOOT_CYCLES-1) begin
            if (image_valid) state <= RUN;
            else begin state <= ACK; good <= 0; end
          end
        end
        LENGTH, PAYLOAD, CHECKSUM: begin
          timer <= timer + 1;
          if (rx_valid) begin
            timer <= 0;
            if (state == LENGTH) begin
              length <= {rx_data, length[31:8]};
              pos <= pos + 1'b1;
              if (pos == 3) begin
                if ({rx_data, length[31:8]} == 0 || {rx_data, length[31:8]} > CAPACITY) begin
                  state <= ACK; good <= 0;
                end else state <= PAYLOAD;
              end
            end else if (state == PAYLOAD) begin
              ld_en <= 1;
              ld_addr <= offset;
              ld_data <= rx_data;
              offset <= offset + 1;
              sum <= sum + {24'b0, rx_data};
              if (offset == length-1) state <= CHECKSUM;
            end else begin
              received <= {rx_data, received[31:8]};
              pos <= pos + 1'b1;
              if (pos == 3) begin
                good <= {rx_data, received[31:8]} == sum;
                state <= ACK;
              end
            end
          end else if (timer >= TIMEOUT_CYCLES-1) begin state <= ACK; good <= 0; end
        end
        ACK: if (tx_ready) state <= DRAIN;
        // UART is busy after accepting ACK; wait for the complete stop bit.
        DRAIN: if (tx_ready) begin
          if (good) begin accepted <= 1; state <= RUN; end
          else state <= FAILED;
        end
        default: ; // RUN and FAILED persist until reset
      endcase
    end
  end
endmodule
