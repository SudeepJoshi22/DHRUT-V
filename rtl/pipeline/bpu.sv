`timescale 1ns / 1ps
`default_nettype none

import riscv_uop_pkg::*;

/**
 * Branch Prediction Unit (BPU)
 * 2-bit saturating counter per entry (indexed by PC[INDEX_WIDTH-1:0])
 *
 * Separate prediction and update ports to allow for pipeline timing.
 *
 * Prediction port:
 *   i_is_branch_pred   - high when the instruction being fetched is a branch
 *   i_branch_pc_pred   - PC of the branch being fetched (for indexing)
 *   i_offset_pc_pred   - target PC of the branch (PC + immediate) to store on a miss
 *   o_prediction       - 1 if predicted taken, 0 if not taken
 *   o_predicted_pc     - predicted target PC (valid when o_prediction is high)
 *
 * Update port:
 *   i_branch_pc_update - PC of the branch whose outcome is known
 *   i_taken_update     - actual outcome (1 taken, 0 not taken)
 *   i_update_valid     - high when update is valid
 *
 * Parameters:
 *   TABLE_DEPTH: number of entries in the BPU (must be power of 2)
 *   INDEX_WIDTH: $clog2(TABLE_DEPTH)
 *   XLEN:        register width (32 for RV32)
 */
module bpu #(
    parameter int TABLE_DEPTH = 256,
    parameter int INDEX_WIDTH = 8,  // $clog2(TABLE_DEPTH)
    parameter int XLEN = 32
) (
    input  logic        clk,
    input  logic        rst_n,
    // Prediction port
    input  logic        i_is_branch_pred,
    input  logic [XLEN-1:0] i_branch_pc_pred,
    input  logic [XLEN-1:0] i_offset_pc_pred,
    output logic        o_prediction,
    output logic [XLEN-1:0] o_predicted_pc,
    // Update port
    input  logic [XLEN-1:0] i_branch_pc_update,
    input  logic        i_taken_update,
    input  logic        i_update_valid,
    input  logic [XLEN-1:0] i_update_target_pc   // Target PC to store on update
);

    // FSM States for 2-bit saturating counter
    typedef enum logic [1:0] {
        SNT = 2'b00, // Strongly Not-Taken
        WNT = 2'b01, // Weakly Not-Taken
        WT  = 2'b10, // Weakly Taken
        ST  = 2'b11  // Strongly Taken
    } bhu_state_t;

    // Branch History Table entry
    typedef struct packed {
        logic [XLEN-1:0] branch_pc;
        logic [XLEN-1:0] target_pc;
        bhu_state_t      state;
    } bhu_entry_t;

    // Table arrays
    bhu_entry_t [TABLE_DEPTH-1:0] bhu;

    // Prediction index and hit
    logic [INDEX_WIDTH-1:0] pred_idx;
    logic pred_hit;
    bhu_entry_t pred_bhu_entry;

    // Update index and hit
    logic [INDEX_WIDTH-1:0] upd_idx;
    logic upd_hit;
    bhu_entry_t upd_bhu_entry;

    // Assign indices
    assign pred_idx = i_branch_pc_pred[INDEX_WIDTH-1:0];
    assign upd_idx  = i_branch_pc_update[INDEX_WIDTH-1:0];

    // Check if we have a valid entry for prediction (hit)
    assign pred_hit = (bhu[pred_idx].branch_pc == i_branch_pc_pred) && i_is_branch_pred;
    // Read the entry for prediction (always read, we'll use conditionally)
    assign pred_bhu_entry = bhu[pred_idx];

    // Check if we have a valid entry for update (hit)
    assign upd_hit = (bhu[upd_idx].branch_pc == i_branch_pc_update) && i_update_valid;
    // Read the entry for update (always read)
    assign upd_bhu_entry = bhu[upd_idx];

    // Prediction logic: taken if state is WT or ST
    assign o_prediction = pred_hit && (pred_bhu_entry.state inside {WT, ST});
    assign o_predicted_pc = pred_hit ? pred_bhu_entry.target_pc : '0;

    // Update logic (sequential)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all entries to WNT (weakly not-taken) and zero PCs
            for (int i = 0; i < TABLE_DEPTH; i++) begin
                bhu[i].branch_pc  = '0;
                bhu[i].target_pc  = '0;
                bhu[i].state      = WNT;
            end
        end else begin
            // Handle update first (if valid and hit)
            if (i_update_valid && upd_hit) begin
                // Update the state based on the actual outcome
                unique case (upd_bhu_entry.state)
                    SNT: bhu[upd_idx].state <= i_taken_update ? WNT : SNT;
                    WNT: bhu[upd_idx].state <= i_taken_update ? WT  : SNT;
                    WT : bhu[upd_idx].state <= i_taken_update ? ST  : WNT;
                    ST : bhu[upd_idx].state <= i_taken_update ? ST  : WT;
                endcase
                // Update the target PC when we have a valid update
                bhu[upd_idx].target_pc <= i_update_target_pc;
            end

            // Handle prediction (allocation on miss)
            // Note: prediction and update can happen in the same cycle for different branches.
            // We will allow both to occur; if the same entry is both hit for update and miss for prediction,
            // the update will happen first (in this always_ff block) and then the prediction allocation
            // will see the updated state but the same branch_pc and target_pc (since we didn't change them).
            // If we want to prioritize update over allocation for the same PC, we need to check.
            // For simplicity, we will allow allocation to overwrite if there is a miss on prediction,
            // even if we just updated the same entry (this would be unusual because if we updated,
            // it means we had a hit, so prediction would also be a hit, not a miss).
            if (i_is_branch_pred && !pred_hit) begin
                // Allocate a new entry: store the branch PC and target PC, initialize state to WNT
                bhu[pred_idx].branch_pc  = i_branch_pc_pred;
                bhu[pred_idx].target_pc  = i_offset_pc_pred;
                bhu[pred_idx].state      = WNT;
            end
            // If not a branch or hit, hold the current state (no change)
        end
    end

    // Optional simulation assertions (can be removed for synthesis)
    `ifdef SIMULATION
    // Ensure state never goes out of bounds
    assert property (@(posedge clk) disable iff (!rst_n)
        (bhu[pred_idx].state inside {SNT, WNT, WT, ST})
    ) else $error("BPU: Invalid state in table at prediction index %0d", pred_idx);
    assert property (@(posedge clk) disable iff (!rst_n)
        (bhu[upd_idx].state inside {SNT, WNT, WT, ST})
    ) else $error("BPU: Invalid state in table at update index %0d", upd_idx);
    `endif

endmodule
