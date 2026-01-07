// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vtop.h for the primary calling header

#ifndef VERILATED_VTOP___024ROOT_H_
#define VERILATED_VTOP___024ROOT_H_  // guard

#include "verilated.h"
class Vtop_mem_if;


class Vtop__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vtop___024root final {
  public:
    // CELLS
    Vtop_mem_if* __PVT__tb_top__DOT__imem_if;

    // DESIGN SPECIFIC STATE
    CData/*0:0*/ tb_top__DOT__clk;
    CData/*0:0*/ tb_top__DOT__rst_n;
    CData/*0:0*/ tb_top__DOT__dut__DOT__clk;
    CData/*0:0*/ tb_top__DOT__dut__DOT__rst_n;
    CData/*0:0*/ tb_top__DOT__dut__DOT__stall;
    CData/*0:0*/ tb_top__DOT__dut__DOT__flush;
    CData/*0:0*/ tb_top__DOT__dut__DOT__if_valid;
    CData/*0:0*/ tb_top__DOT__dut__DOT__waiting;
    CData/*0:0*/ __VstlFirstIteration;
    CData/*0:0*/ __VicoFirstIteration;
    CData/*0:0*/ __Vtrigprevexpr___TOP__tb_top__DOT__dut__DOT__clk__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__tb_top__DOT__dut__DOT__rst_n__0;
    IData/*31:0*/ tb_top__DOT__dut__DOT__redirect_pc;
    IData/*31:0*/ tb_top__DOT__dut__DOT__if_pc;
    IData/*31:0*/ tb_top__DOT__dut__DOT__if_instr;
    IData/*31:0*/ tb_top__DOT__dut__DOT__pc_q;
    IData/*31:0*/ tb_top__DOT__dut__DOT__pc_d;
    IData/*31:0*/ __VactIterCount;
    VlUnpacked<QData/*63:0*/, 1> __VstlTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VicoTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VactTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VnbaTriggered;

    // INTERNAL VARIABLES
    Vtop__Syms* vlSymsp;
    const char* vlNamep;

    // CONSTRUCTORS
    Vtop___024root(Vtop__Syms* symsp, const char* namep);
    ~Vtop___024root();
    VL_UNCOPYABLE(Vtop___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
