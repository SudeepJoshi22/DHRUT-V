/*
   Copyright 2024 Sudeep Joshi

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License. */

`timescale 1ns / 1ps
`default_nettype none	

module Fetch #(
	parameter IF_PKT_WIDTH = 64
)(
	input wire			clk,
	input wire 			rst_n,
	/*** Fetch-Decode Stage Interface ***/
	input wire			i_stall,
	output wire			o_if_pkt_valid,
	output wire [IF_PKT_WIDTH-1:0]	o_if_pkt_data, // IF-Packet => {pc,instruction}	
	/*** PC Redirect Logic ***/
	input wire			i_boj,
	input wire [`ADDR_WIDTH-1:0] 	i_boj_pc,
	input wire			i_trap,
	input wire [`ADDR_WIDTH-1:0] 	i_trap_pc,
	input wire 			i_flush,
	input wire [`ADDR_WIDTH-1:0] 	i_redir_pc,
	/*** CPU-Memory Interface(AXI-lite compitable master interface) ***/
	// Address Read(AR) channel (Valid-Ready master)
	output wire [`ADDR_WIDTH-1:0] 	o_axil_araddr,
	output wire			o_axil_arvalid,
	input wire 			i_axil_arready,
	// Read Response(R) channel (Valid-Ready slave)
	input wire [`DATA_WIDTH-1:0]	i_axil_rdata,
	input wire 			i_axil_rvalid,
	output wire 			o_axil_rready
);

	/*** PC Control Logic ***/

	// Internal Wires
	wire [`ADDR_WIDTH-1:0]	is_next_pc;
	wire 			is_flush; // Internal conditons for flush

	// Internal Registers
	reg [`ADDR_WIDTH-1:0]	pc;
	reg [`ADDR_WIDTH-1:0]	ir_addr;

	// PC Change Logic

	assign is_flush = (i_boj ^ ir_prediction) || i_trap; 

	assign is_next_pc = ~rst_n ? `PC_RESET :
				(i_trap ? i_trap_pc :
				(is_flush ? i_boj_pc :
				(is_prediction ? is_predicted_pc : 
				pc + 'd4)));
	
	always @(posedge clk, negedge rst_n) begin
		if(~rst_n) 
			pc <= `PC_RESET;
		else
			pc <= is_next_pc;
	end



	/*** Branch Prediction ***/

	// Internal Wires
	wire			is_prediction;
	wire [`ADDR_WIDTH-1:0]	is_predicted_pc;
	wire 			is_branch;
	
	reg 			ir_prediction; // Flop the prediction

	assign is_branch = (i_axil_rdata[6:0] == `B);
	
	bpu branch_prediction_unit (
		.clk(clk),
		.rst_n(rst_n),
		.i_is_branch(is_branch),
		.i_branch_pc(pc),
		.i_offset_pc(i_boj_pc),
		.i_actually_taken(i_boj),
		.o_prediction(is_prediction),
		.o_predicted_pc(is_predicted_pc)
	);

	always @(posedge clk, negedge rst_n) begin
		if(~rst_n)
			ir_prediction <= 0;
		else
			ir_prediction <= is_prediction;
	end

	/*** Pipeline Control ***/
	
	// Internal Wires
	wire			is_stall;

	// Internal Registers	
	reg 			ir_if_pkt_valid;
	reg [IF_PKT_WIDTH-1:0]  ir_if_pkt_data;

	// Stall Logic
	assign is_stall = i_stall || ~i_axil_arready;
	
	// Stage Enable

	assign o_if_pkt_valid = ir_if_pkt_valid;
	assign o_if_pkt_data = ir_if_pkt_data;

	/*** AR Channel Logic ***/
	// Internal Wires
	wire 			is_addr_valid;

	// Internal Registers
	reg			ir_axil_arvalid;
	reg [`DATA_WIDTH-1:0]	ir_axil_ardata;

	// AR Channel Valid
	always @(posedge clk, negedge rst_n) begin
		if (~rst_n || is_flush)
			ir_axil_arvalid <= 0;
		else if(!ir_axil_arvalid || i_axil_arready) begin
			ir_axil_arvalid <= is_addr_valid; 
		end
	end	
	
	assign is_addr_valid = rst_n && ~i_stall && ~is_flush;

	// AR Channel Data	
	always @(posedge clk, negedge rst_n) begin
		if(~rst_n || is_flush)
			ir_axil_ardata <= 0;
		else if(!ir_axil_arvalid || o_axil_arvalid) begin
			ir_axil_ardata <= pc;	
			
			if(!is_addr_valid) 
				ir_axil_ardata <= 0;
		end	

	end

	assign o_axil_arvalid = ir_axil_arvalid;
	assign o_axil_araddr = ir_axil_ardata;	
	//assign o_axil_araddr = pc;

	/*** R Channel Logic ***/ 
	
	// Internal Wires
	wire is_axil_rready;

	assign is_axil_rready = rst_n && ~i_stall && ~is_flush;

	// Internal Registers
	reg ir_axil_rready;

	// R Channel Ready
	always @(posedge clk, negedge rst_n) begin
		if(!rst_n)
			ir_axil_rready <= 0;
		else
			ir_axil_rready <= is_axil_rready; 
	end	

	assign o_axil_rready = ir_axil_rready;

	// R Channel Data

	// Flop the Instruction Address
	always @(posedge clk, negedge rst_n) begin
		if(is_flush) 
			ir_addr <= 0; 
		else if(o_axil_arvalid)
			ir_addr <= o_axil_araddr;
	end

	always @(posedge clk, negedge rst_n) begin
		if(~rst_n || is_flush)
			ir_if_pkt_data <= 0;
		else if(i_axil_rvalid && o_axil_rready)
			ir_if_pkt_data <= {ir_addr,i_axil_rdata}; 
	end


	// Clocking the valid for this stage
	always @(posedge clk, negedge rst_n) begin
		if(~rst_n || is_flush)
			ir_if_pkt_valid <= 0;
		else if(i_axil_rvalid && o_axil_rready)
			ir_if_pkt_valid <= 1; 
	end

endmodule
