// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Tracing implementation internals

#include "verilated_vcd_c.h"
#include "Vtop__Syms.h"


void Vtop___024root__trace_chg_0_sub_0(Vtop___024root* vlSelf, VerilatedVcd::Buffer* bufp);

void Vtop___024root__trace_chg_0(void* voidSelf, VerilatedVcd::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_chg_0\n"); );
    // Body
    Vtop___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vtop___024root*>(voidSelf);
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    if (VL_UNLIKELY(!vlSymsp->__Vm_activity)) return;
    Vtop___024root__trace_chg_0_sub_0((&vlSymsp->TOP), bufp);
}

void Vtop___024root__trace_chg_0_sub_0(Vtop___024root* vlSelf, VerilatedVcd::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_chg_0_sub_0\n"); );
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    uint32_t* const oldp VL_ATTR_UNUSED = bufp->oldp(vlSymsp->__Vm_baseCode + 1);
    bufp->chgBit(oldp+0,(vlSelfRef.tb_top__DOT__clk));
    bufp->chgBit(oldp+1,(vlSelfRef.tb_top__DOT__rst_n));
    bufp->chgBit(oldp+2,(vlSelfRef.tb_top__DOT__dut__DOT__clk));
    bufp->chgBit(oldp+3,(vlSelfRef.tb_top__DOT__dut__DOT__rst_n));
    bufp->chgBit(oldp+4,(vlSelfRef.tb_top__DOT__dut__DOT__i_stall));
    bufp->chgBit(oldp+5,(vlSelfRef.tb_top__DOT__dut__DOT__i_flush));
    bufp->chgIData(oldp+6,(vlSelfRef.tb_top__DOT__dut__DOT__i_redirect_pc),32);
    bufp->chgBit(oldp+7,(vlSelfRef.tb_top__DOT__dut__DOT__o_if_valid));
    bufp->chgIData(oldp+8,(vlSelfRef.tb_top__DOT__dut__DOT__o_if_pc),32);
    bufp->chgIData(oldp+9,(vlSelfRef.tb_top__DOT__dut__DOT__o_if_instr),32);
    bufp->chgIData(oldp+10,(vlSelfRef.tb_top__DOT__dut__DOT__pc_q),32);
    bufp->chgIData(oldp+11,(vlSelfRef.tb_top__DOT__dut__DOT__pc_d),32);
    bufp->chgBit(oldp+12,(vlSelfRef.tb_top__DOT__dut__DOT__waiting));
    bufp->chgBit(oldp+13,(vlSymsp->TOP__tb_top__DOT__imem_if.clk));
    bufp->chgBit(oldp+14,(vlSymsp->TOP__tb_top__DOT__imem_if.m_valid));
    bufp->chgBit(oldp+15,(vlSymsp->TOP__tb_top__DOT__imem_if.s_ready));
    bufp->chgIData(oldp+16,(vlSymsp->TOP__tb_top__DOT__imem_if.m_addr),32);
    bufp->chgIData(oldp+17,(vlSymsp->TOP__tb_top__DOT__imem_if.m_wdata),32);
    bufp->chgCData(oldp+18,(vlSymsp->TOP__tb_top__DOT__imem_if.m_wstrb),4);
    bufp->chgIData(oldp+19,(vlSymsp->TOP__tb_top__DOT__imem_if.s_rdata),32);
}

void Vtop___024root__trace_cleanup(void* voidSelf, VerilatedVcd* /*unused*/) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtop___024root__trace_cleanup\n"); );
    // Locals
    VlUnpacked<CData/*0:0*/, 1> __Vm_traceActivity;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        __Vm_traceActivity[__Vi0] = 0;
    }
    // Body
    Vtop___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vtop___024root*>(voidSelf);
    Vtop__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    vlSymsp->__Vm_activity = false;
    __Vm_traceActivity[0U] = 0U;
}
