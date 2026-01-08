// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtop.h for the primary calling header

#include "Vtop__pch.h"

void Vtop_mem_if___ico_sequent__TOP__tb_top__DOT__imem_if__0(Vtop_mem_if* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+          Vtop_mem_if___ico_sequent__TOP__tb_top__DOT__imem_if__0\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.clk = vlSymsp->TOP.tb_top__DOT__clk;
    vlSelfRef.m_addr = vlSymsp->TOP.tb_top__DOT__dut__DOT__pc_q;
    vlSelfRef.m_valid = (1U & (~ (IData)(vlSymsp->TOP.tb_top__DOT__dut__DOT__waiting)));
}

void Vtop_mem_if___nba_sequent__TOP__tb_top__DOT__imem_if__0(Vtop_mem_if* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+          Vtop_mem_if___nba_sequent__TOP__tb_top__DOT__imem_if__0\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.m_valid = (1U & (~ (IData)(vlSymsp->TOP.tb_top__DOT__dut__DOT__waiting)));
    vlSelfRef.m_addr = vlSymsp->TOP.tb_top__DOT__dut__DOT__pc_q;
}

std::string VL_TO_STRING(const Vtop_mem_if* obj) {
    VL_DEBUG_IF(VL_DBG_MSGF("+          Vtop_mem_if::VL_TO_STRING\n"); );
    // Body
    return (obj ? obj->vlNamep : "null");
}
