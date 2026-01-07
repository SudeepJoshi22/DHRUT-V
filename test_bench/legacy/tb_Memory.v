`timescale 1ns / 1ps
`default_nettype none
`include "rtl/parameters.vh"
//`include "rtl/Memory.v"
module tb_Memory();
reg clk,rst_n,i_ready_dmem,i_valid_mem,i_stall;
reg [31:0] i_result,i_data_store,i_pc,i_read_data;
reg [6:0] i_opcode;
reg [2:0] i_func3;
reg[4:0] i_rd;
wire [31:0] o_wb_data,o_addr,o_wr_data;
wire [6:0] o_opcode;
wire o_valid_dmem,o_ready_mem;
wire [4:0] o_rd;

Memory mem(.clk(clk),
	   .rst_n(rst_n),
	   .i_result(i_result),
	   .i_data_store(i_data_store),
	   .i_pc(i_pc),
	   .i_opcode(i_opcode),
	   .i_func3(i_func3),
	   .i_rd(i_rd),
	   .o_rd(o_rd),
	   .o_wb_data(o_wb_data),
	   .o_opcode(o_opcode),
	   .i_ready_dmem(i_ready_dmem),
	   .i_valid_mem(i_valid_mem),
	   .i_read_data(i_read_data),
	   .i_stall(i_stall),
	   .o_addr(o_addr),
	   .o_valid_dmem(o_valid_dmem),
	   .o_ready_mem(o_ready_mem),
	   .o_wr_data(o_wr_data)
);
initial 
begin
	clk = 0;
	forever #10 clk=~clk;
	
end
initial 
begin
	$dumpfile("waveform.vcd");
    $dumpvars(0, tb_Memory);
    
    end

initial
begin
	rst_n =0;
#5 rst_n =1;
#5	// For Load type first address is sent by o_valid_dmem =1 , which makes i_ready_dmem =1 (Data_Memory is receiver)
	i_opcode = `LD; 
	i_result = 32'h0000_0014; 
	i_ready_dmem = 1;
	i_valid_mem = 1;
	i_func3 = `LW;
	i_read_data = 32'h0000_0010;
	i_rd=5'b01010;
#20
	i_opcode =`S;
	i_data_store = 32'h0000_0101;
	i_valid_mem=1;
	i_rd=5'b11100;
#20
	i_opcode =`R;
	i_result = 32'h0000_2004;
	i_rd=5'b10101;
#20
	i_opcode =`I;
	i_result = 32'h0000_2003;
	i_rd=5'b10000;
	
#1000 $finish;
end
endmodule

