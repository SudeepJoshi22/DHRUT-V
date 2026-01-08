// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vtop.h for the primary calling header

#ifndef VERILATED_VTOP_MEM_IF_H_
#define VERILATED_VTOP_MEM_IF_H_  // guard

#include "verilated.h"


class Vtop__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vtop_mem_if final {
  public:

    // DESIGN SPECIFIC STATE
    VL_IN8(clk,0,0);
    CData/*0:0*/ m_valid;
    CData/*0:0*/ s_ready;
    CData/*3:0*/ m_wstrb;
    IData/*31:0*/ m_addr;
    IData/*31:0*/ m_wdata;
    IData/*31:0*/ s_rdata;

    // INTERNAL VARIABLES
    Vtop__Syms* vlSymsp;
    const char* vlNamep;

    // CONSTRUCTORS
    Vtop_mem_if() = default;
    ~Vtop_mem_if() = default;
    void ctor(Vtop__Syms* symsp, const char* namep);
    void dtor();
    VL_UNCOPYABLE(Vtop_mem_if);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};

std::string VL_TO_STRING(const Vtop_mem_if* obj);

#endif  // guard
