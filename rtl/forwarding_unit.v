`timescale 1ns / 1ps
`default_nettype none
`include "rtl/parameters.vh"


module forwarding_unit( input i_rs1,
			input i_rs2,
			input i_rd_decode, // destination register address in reg file which is output of decode (after clock edge)
			input i_rd_execute, // destination register address in reg file which is output of execute (after clock edge)
			input i_opcode_decode,// opcode from output of decode stage (after clock edge)
			input i_rd_mem,
			input i_opcode_EX, // opcode from output of execute stage (after clock edge)
			input is_branch, // branch / jump signal 
			input is_branch_rs1, // source register address from decode if branch is detected 
			input is_branch_rs2,// source register address from decode if branch is detected 
			output o_forward_EX, // operand forwarding from output of execute to input of execute
			output o_forward_MEM, // operand forwarding from output of mem stage to input of execute stage 
			output o_forward_branch,// Goes to an decode stage ,for data dependancy due to branch instruction
			output o_stall
);
always@(*)
begin
	// Operand forwarding (Read after write case)
	if( (i_rs1 == i_rd_execute) || (i_rs2 == i_rd_execute) ) begin
	
		if( i_opcode_EX == `LD) begin
			o_forward_EX = 1'b0;
			o_forward_MEM = 1'b0;
		end
		else begin
			o_forward_EX = 1'b1;
		end
		
	end
	else if( (i_rs1 == i_rd_mem) || (i_rs2 == i_rd_mem) ) begin
			o_forward_MEM = 1'b1;;
	     end
	   
     
end
// Stalling logic 
always@(*)
begin
	// Stall the pipeline when there is requirement of data backwards
	if( (i_rs1 == i_rd_execute) || (i_rs2 == i_rd_execute) ) begin
	
		if( i_opcode_EX == `LD) begin
			o_stall == 1'b1;
		end
		else begin
			o_stall = 1'b0;
		end
		
	end
	else if( (i_rs1 == i_rd_mem) || (i_rs2 == i_rd_mem) ) begin
			o_stall = 1'b0;
	     end	
	// Stalling if there is a branch/jump instr after an instruction with dependency ,since branch decision is moved to decode stage
	
	if (is_branch) begin
		if( (is_branch_rs1 == i_rd_decode) || (is_branch_rs2 == i_rd_decode) ) begin
			o_stall = 1'b1;
			o_forward_branch = 1'b0;
			end 
		else if( ( i_rd_execute == is_branch_rs1) || (i_rd_execute == is_branch_rs2) ) begin
			o_stall = 1'b0;
			o_forward_branch = 1'b1;
			end
	end	
	
		
end

endmodule
		
		
		
