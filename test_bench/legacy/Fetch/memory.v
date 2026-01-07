module main_memory #(parameter MEMORY_DEPTH=1024) ( //Instruction and Data memory (combined memory)
    input wire i_clk,
    // Instruction Memory
    input wire[$clog2(MEMORY_DEPTH)-1:0] i_inst_addr,
    output reg[31:0] o_inst_out,
    input wire i_stb_inst, // request for instruction
    output reg o_ack_inst, //ack (high if new instruction is now on the bus)
    // Data Memory
    input wire i_wb_cyc,
    input wire i_wb_stb,
    input wire i_wb_we,
    input wire[$clog2(MEMORY_DEPTH)-1:0] i_wb_addr,
    input wire[31:0] i_wb_data,
    input wire[3:0] i_wb_sel,
    output reg o_wb_ack,
    output wire o_wb_stall,
    output reg[31:0] o_wb_data
);
    reg[31:0] memory_regfile[MEMORY_DEPTH/4 - 1:0];
    integer i;
    assign o_wb_stall = 0; // never stall

    initial begin //initialize memory to zero
        o_ack_inst <= 0;
        o_wb_ack <= 0;
        o_inst_out <= 0;
    end
    
    //reading must be registered to be inferred as block ram
    always @(posedge i_clk) begin 
        o_ack_inst <= i_stb_inst; //go high next cycle after receiving request (data o_inst_out is also sent at next cycle)
        o_wb_ack <= i_wb_stb && i_wb_cyc;
        o_inst_out <= memory_regfile[{i_inst_addr>>2}]; //read instruction 
        o_wb_data <= memory_regfile[i_wb_addr[$clog2(MEMORY_DEPTH)-1:2]]; //read data    
    end

    // write data
    always @(posedge i_clk) begin
        if(i_wb_we && i_wb_stb && i_wb_cyc) begin
            if(i_wb_sel[0]) memory_regfile[i_wb_addr[$clog2(MEMORY_DEPTH)-1:2]][7:0] <= i_wb_data[7:0]; 
            if(i_wb_sel[1]) memory_regfile[i_wb_addr[$clog2(MEMORY_DEPTH)-1:2]][15:8] <= i_wb_data[15:8];
            if(i_wb_sel[2]) memory_regfile[i_wb_addr[$clog2(MEMORY_DEPTH)-1:2]][23:16] <= i_wb_data[23:16];
            if(i_wb_sel[3]) memory_regfile[i_wb_addr[$clog2(MEMORY_DEPTH)-1:2]][31:24] <= i_wb_data[31:24];
        end      
        
    end
    
endmodule
