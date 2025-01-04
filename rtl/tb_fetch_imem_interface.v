module tb_fetch_imem_interface (
    input  wire              clk,
    input  wire              rst_n
);

    // Internal signals
    wire [31:0]              fetch_iaddr;
    wire                     fetch_iaddr_vld;
    wire [31:0]              imem_data;
    reg                      imem_ack; // Controlled by a random delay generator
    wire                     fetch_pkt_vld;
    wire [`IF_PKT_WIDTH-1:0] fetch_pkt_data;

    // Random delay control signals
    reg [3:0]                random_delay; // Counter for random delay
    reg                      delay_active; // Indicates if delay is active

    // Instantiate the fetch unit
    fetch_unit u_fetch_unit (
        .clk(clk),
        .rst_n(rst_n),
        .i_stall(1'b0), // No stalling logic provided in this example
        .o_if_pkt_vld(fetch_pkt_vld),
        .o_if_pkt_data(fetch_pkt_data),
        .o_iaddr(fetch_iaddr),
        .o_iaddr_vld(fetch_iaddr_vld),
        .i_inst(imem_data),
        .i_inst_vld(imem_ack)
    );

    // Instantiate the instruction memory
    instr_mem u_instr_mem (
        .clk(clk),
        .rst_n(rst_n),
        .i_addr(fetch_iaddr),
        .i_stb(fetch_iaddr_vld),
        .o_ack(), // Not directly connected, handled manually
        .o_data(imem_data)
    );

    // Random delay logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            random_delay <= 0;
            delay_active <= 0;
            imem_ack <= 0;
        end else begin
            if (fetch_iaddr_vld && !delay_active) begin
                // Start a new random delay
                random_delay <= $urandom % 10 + 1; // Random delay between 1 and 10 cycles
                delay_active <= 1;
            end

            if (delay_active) begin
                if (random_delay > 0) begin
                    random_delay <= random_delay - 1;
                end else begin
                    // Delay complete, assert acknowledgment
                    imem_ack <= 1;
                    delay_active <= 0;
                end
            end else begin
                // Reset acknowledgment after one cycle
                imem_ack <= 0;
            end
        end
    end

    // For debugging and verification purposes, display fetch packet details
    always @(posedge clk) begin
        if (fetch_pkt_vld) begin
            $display("Fetch Packet Valid: PC = %h, Instruction = %h", 
                fetch_pkt_data[`ADDR_WIDTH-1:0], fetch_pkt_data[`IF_PKT_WIDTH-1:`ADDR_WIDTH]);
        end
    end

endmodule
