// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtop.h for the primary calling header

#include "Vtop__pch.h"

VL_ATTR_COLD void Vtop_mem_if___eval_initial__TOP__tb_top__DOT__imem_if(Vtop_mem_if* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+          Vtop_mem_if___eval_initial__TOP__tb_top__DOT__imem_if\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.wdata = 0U;
    vlSelfRef.wstrb = 0U;
}

VL_ATTR_COLD void Vtop_mem_if___ctor_var_reset(Vtop_mem_if* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+          Vtop_mem_if___ctor_var_reset\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->vlNamep);
    vlSelf->clk = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16707436170211756652ull);
    vlSelf->valid = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 4944192500720994163ull);
    vlSelf->ready = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 898948264233693212ull);
    vlSelf->addr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 14934084843038794831ull);
    vlSelf->wdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 12890271867161903902ull);
    vlSelf->wstrb = VL_SCOPED_RAND_RESET_I(4, __VscopeHash, 15125268524300477597ull);
    vlSelf->rdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 10065165116613087284ull);
}
