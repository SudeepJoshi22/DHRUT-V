// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtop.h for the primary calling header

#include "Vtop__pch.h"

VL_ATTR_COLD void Vtop_mem_if___eval_initial__TOP__tb_top__DOT__imem_if(Vtop_mem_if* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+          Vtop_mem_if___eval_initial__TOP__tb_top__DOT__imem_if\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.m_wdata = 0U;
    vlSelfRef.m_wstrb = 0U;
}

VL_ATTR_COLD void Vtop_mem_if___ctor_var_reset(Vtop_mem_if* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+          Vtop_mem_if___ctor_var_reset\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->vlNamep);
    vlSelf->clk = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16707436170211756652ull);
    vlSelf->m_valid = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 8711207929187084452ull);
    vlSelf->s_ready = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 869066129896787687ull);
    vlSelf->m_addr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 10737892889211211088ull);
    vlSelf->m_wdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 15494961946000700504ull);
    vlSelf->m_wstrb = VL_SCOPED_RAND_RESET_I(4, __VscopeHash, 16102823512841672097ull);
    vlSelf->s_rdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 2301979449509909042ull);
}
