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

module Core (
    input  wire                             clk,
    input  wire                             rst_n,
    /*** I-mem Interface ***/
    output wire [`ADDR_WIDTH-1:0]           o_iaddr,
    output wire                             o_iaddr_vld,    // Request for instruction when address is valid
    input  wire [`INST_WIDTH-1:0]           i_inst,
    input  wire                             i_inst_vld,     // Instruction is obtained when inst_vld is asserted
    /*** D-mem Interface ***/
    input  wire [`N-1:0]                    i_rdata,        // 32-bit Read data
    input  wire                             i_d_valid,      // Valid signal
    output wire                             o_wr_en,        // Write enable signal
    output wire [3:0]                       o_sel,          // Select signal for byte-enable (4 bits for 32-bit word)
    output wire [`ADDR_WIDTH-1:0]           o_addr,         // 32-bit Address signal
    output wire                             o_addr_vld,
    output wire [`N-1:0]                    o_wdata         // 32-bit Write data
);

    /*** Internal wires for pipeline stages ***/
    // Fetch-Decode Interface
    wire [`IF_PKT_WIDTH-1:0]                is_if_pkt_data; // IF-Packet {pc, instruction}
    wire                                    is_if_pkt_vld;
    
    // Decode-Execute Interface
    wire [`N-1:0]                           is_rs1_data;
    wire [`N-1:0]                           is_rs2_data;
    wire [`N-1:0]                           is_imm_data;
    wire [4:0]                              is_rd;
    wire [6:0]                              is_opcode;
    wire [2:0]                              is_func3;
    wire [3:0]                              is_alu_ctrl;
    wire [`ADDR_WIDTH-1:0]                  is_pc;
    wire                                    is_id_valid;
    wire                                    is_decode_stall;

    // Execute-Memory Interface
    wire [`N-1:0]                           is_result;
    wire [`N-1:0]                           is_data_store;
    wire [`ADDR_WIDTH-1:0]                  is_ex_pc;
    wire [2:0]                              is_ex_func3;
    wire [4:0]                              is_ex_rd;
    wire [6:0]                              is_ex_opcode;
    wire                                    is_ex_valid;
    wire                                    is_execute_stall;

    // Memory-WriteBack Interface
    wire [4:0]                              is_wb_rd;
    wire [6:0]                              is_wb_opcode;
    wire [`N-1:0]                           is_wb_data;
    wire                                    is_mem_vld;
    wire                                    is_memory_stall;

    // Memory-WriteBack Interface
    wire [`N-1:0]			    is_rf_data;
    wire [4:0]				    is_rf_rd;
    wire 				    is_rf_wr;	 

    /*** Instantiating Pipeline Stages ***/
    Fetch u_fetch (
        .clk(clk),
        .rst_n(rst_n),
        .i_stall(is_decode_stall),
        .o_if_pkt_vld(is_if_pkt_vld),
        .o_if_pkt_data(is_if_pkt_data),
        .o_iaddr(o_iaddr),
        .o_iaddr_vld(o_iaddr_vld),
        .i_inst(i_inst),
        .i_inst_vld(i_inst_vld)
    );

    Decode u_decode (
        .clk(clk),
        .rst_n(rst_n),
        .i_if_pkt_data(is_if_pkt_data),
        .i_if_pkt_valid(is_if_pkt_vld),
        .o_stall(is_decode_stall),
        .i_write_data(is_rf_data),
        .i_rd(is_rf_rd),
        .i_wr(is_rf_wr),
        .i_stall(is_execute_stall),
        .o_rs1_data(is_rs1_data),
        .o_rs2_data(is_rs2_data),
        .o_imm_data(is_imm_data),
        .o_rd(is_rd),
        .o_opcode(is_opcode),
        .o_func3(is_func3),
        .o_alu_ctrl(is_alu_ctrl),
        .o_pc(is_pc),
        .o_id_valid(is_id_valid)
    );

    Execute u_execute (
        .clk(clk),
        .rst_n(rst_n),
        .i_rs1_data(is_rs1_data),
        .i_rs2_data(is_rs2_data),
        .i_imm_data(is_imm_data),
        .i_rd(is_rd),
        .i_pc(is_pc),
        .i_alu_ctrl(is_alu_ctrl),
        .i_func3(is_func3),
        .i_opcode(is_opcode),
        .i_id_valid(is_id_valid),
        .o_stall(is_execute_stall),
        .i_stall(is_memory_stall),
        .o_result(is_result),
        .o_data_store(is_data_store),
        .o_pc(is_ex_pc),
        .o_func3(is_ex_func3),
        .o_rd(is_ex_rd),
        .o_opcode(is_ex_opcode),
        .o_ex_valid(is_ex_valid)
    );

    Memory u_memory (
        .clk(clk),
        .rst_n(rst_n),
        .i_result(is_result),
        .i_data_store(is_data_store),
        .i_pc(is_ex_pc),
        .i_func3(is_ex_func3),
        .i_rd(is_ex_rd),
        .i_opcode(is_ex_opcode),
        .i_ex_valid(is_ex_valid),
        .o_stall(is_memory_stall),
        .o_wb_rd(is_wb_rd),
        .o_opcode(is_wb_opcode),
        .o_wb_data(is_wb_data),
        .o_mem_vld(is_mem_vld),
        .i_rdata(i_rdata),
        .i_d_valid(i_d_valid),
        .o_wr_en(o_wr_en),
        .o_sel(o_sel),
        .o_addr(o_addr),
        .o_addr_vld(o_addr_vld),
        .o_wdata(o_wdata)
    );

    Writeback u_writeback (
        .clk(clk),
        .rst_n(rst_n),
        .i_rd(is_wb_rd),
        .i_opcode(is_wb_opcode),
        .i_wb_data(is_wb_data),
        .i_mem_vld(is_mem_vld),
        .o_rf_wr(is_rf_wr),
        .o_rf_rd(is_rf_rd),
        .o_rf_data(is_rf_data)
    );

endmodule

