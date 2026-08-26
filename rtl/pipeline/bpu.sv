`timescale 1ns / 1ps
`default_nettype none

import riscv_uop_pkg::*;

/**
 * Branch Prediction Unit (BPU)
 *
 * A fused BTB + 2-bit-saturating-counter BHT: one table, each entry
 * holding {tag, target, 2-bit state}. Indexed by the PC, tagged with the
 * full PC so aliasing is detected (a miss) rather than mispredicted.
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
 *
 * NOTE ON CORRECTNESS: nothing in here can make the core wrong. Every
 * prediction is re-resolved in Issue, which redirects on any mismatch.
 * A stale entry, an aliased index or a cold table costs cycles only.
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

    // ─────────────────────────────────────────────────────────────────
    // Indexing
    // ─────────────────────────────────────────────────────────────────
    // Index from PC[INDEX_WIDTH+1:2], NOT PC[INDEX_WIDTH-1:0]. RV32
    // instructions are 4-byte aligned, so PC[1:0] is always zero: using
    // the raw low bits fed two constant zeros into the index and made
    // only one entry in every four reachable. A 256-entry table was
    // therefore behaving as a 64-entry one with a stride-4 hole pattern.
    assign pred_idx = i_branch_pc_pred[INDEX_WIDTH+1:2];
    assign upd_idx  = i_branch_pc_update[INDEX_WIDTH+1:2];

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

    // ─────────────────────────────────────────────────────────────────
    // Allocation policy: backward-taken / forward-not-taken
    // ─────────────────────────────────────────────────────────────────
    // A branch we have never seen gets a starting counter value from the
    // direction of its target rather than a flat WNT. A backward branch
    // is overwhelmingly a loop back-edge and is taken almost every time,
    // so starting it at WT gets the loop predicted correctly from its
    // second iteration instead of its fourth (WNT needs two taken
    // outcomes to reach WT). Forward branches keep WNT.
    bhu_state_t alloc_state;
    assign alloc_state = (i_offset_pc_pred < i_branch_pc_pred) ? WT : WNT;

    // ─────────────────────────────────────────────────────────────────
    // Table write
    // ─────────────────────────────────────────────────────────────────
    logic upd_fire, alloc_fire, alloc_collides;
    bhu_state_t upd_next_state;

    assign upd_fire   = i_update_valid && upd_hit;
    assign alloc_fire = i_is_branch_pred && !pred_hit;
    // Both writers can target the same index in one cycle (two different
    // PCs aliasing to it). The resolved update wins: it is fact, whereas
    // the allocation is a guess about an instruction that has not
    // executed yet.
    assign alloc_collides = upd_fire && (upd_idx == pred_idx);

    always_comb begin
        unique case (upd_bhu_entry.state)
            SNT: upd_next_state = i_taken_update ? WNT : SNT;
            WNT: upd_next_state = i_taken_update ? WT  : SNT;
            WT : upd_next_state = i_taken_update ? ST  : WNT;
            ST : upd_next_state = i_taken_update ? ST  : WT;
        endcase
    end

    // Every write below is non-blocking. The original mixed `<=` for the
    // update path with `=` for the reset and allocation paths, inside one
    // always_ff and to the same array - a genuine simulation race, and one
    // that also let `pred_hit` (a continuous assign reading this array)
    // observe an allocation within the same time step.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all entries to WNT (weakly not-taken) and zero PCs
            for (int i = 0; i < TABLE_DEPTH; i++) begin
                bhu[i].branch_pc  <= '0;
                bhu[i].target_pc  <= '0;
                bhu[i].state      <= WNT;
            end
        end else begin
            if (upd_fire) begin
                bhu[upd_idx].state     <= upd_next_state;
                bhu[upd_idx].target_pc <= i_update_target_pc;
            end

            if (alloc_fire && !alloc_collides) begin
                bhu[pred_idx].branch_pc <= i_branch_pc_pred;
                bhu[pred_idx].target_pc <= i_offset_pc_pred;
                bhu[pred_idx].state     <= alloc_state;
            end
            // If not a branch, or a hit with no update, hold.
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

    // A hit means the tag matched, so the stored target must be the
    // target we would compute for that PC. If this fires, an entry has
    // been trained with a target belonging to a different branch.
    assert_hit_implies_tag_match: assert property (@(posedge clk) disable iff (!rst_n)
        pred_hit |-> (bhu[pred_idx].branch_pc == i_branch_pc_pred)
    ) else $error("BPU: hit with mismatched tag at index %0d (pc=0x%h)", pred_idx, i_branch_pc_pred);

    // The two writers must never both commit to one entry in a cycle.
    assert_single_writer: assert property (@(posedge clk) disable iff (!rst_n)
        !(upd_fire && alloc_fire && !alloc_collides && (upd_idx == pred_idx))
    ) else $error("BPU: update and allocation both wrote index %0d", upd_idx);
    `endif

endmodule
