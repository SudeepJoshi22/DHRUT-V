// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table implementation internals

#include "Vtop__pch.h"

Vtop__Syms::Vtop__Syms(VerilatedContext* contextp, const char* namep, Vtop* modelp)
    : VerilatedSyms{contextp}
    // Setup internal state of the Syms class
    , __Vm_modelp{modelp}
    // Setup top module instance
    , TOP{this, namep}
{
    // Check resources
    Verilated::stackCheck(250);
    // Setup sub module instances
    TOP__tb_top__DOT__imem_if.ctor(this, "tb_top.imem_if");
    // Configure time unit / time precision
    _vm_contextp__->timeunit(-9);
    _vm_contextp__->timeprecision(-12);
    // Setup each module's pointers to their submodules
    TOP.__PVT__tb_top__DOT__imem_if = &TOP__tb_top__DOT__imem_if;
    // Setup each module's pointer back to symbol table (for public functions)
    TOP.__Vconfigure(true);
    TOP__tb_top__DOT__imem_if.__Vconfigure(true);
    // Setup scopes
    __Vscopep_tb_top = new VerilatedScope{this, "tb_top", "tb_top", "tb_top", -9, VerilatedScope::SCOPE_MODULE};
    __Vscopep_tb_top__dut = new VerilatedScope{this, "tb_top.dut", "dut", "if_stage", -9, VerilatedScope::SCOPE_MODULE};
    __Vscopep_tb_top__imem_if = new VerilatedScope{this, "tb_top.imem_if", "imem_if", "mem_if", -9, VerilatedScope::SCOPE_MODULE};
    // Set up scope hierarchy
    __Vhier.add(0, __Vscopep_tb_top);
    __Vhier.add(__Vscopep_tb_top, __Vscopep_tb_top__dut);
    __Vhier.add(__Vscopep_tb_top, __Vscopep_tb_top__imem_if);
    // Setup export functions - final: 0
    // Setup export functions - final: 1
    // Setup public variables
    __Vscopep_tb_top->varInsert("clk", &(TOP.tb_top__DOT__clk), false, VLVT_UINT8, VLVD_NODIR|VLVF_PUB_RW, 0, 0);
    __Vscopep_tb_top->varInsert("rst_n", &(TOP.tb_top__DOT__rst_n), false, VLVT_UINT8, VLVD_NODIR|VLVF_PUB_RW, 0, 0);
    __Vscopep_tb_top__dut->varInsert("clk", &(TOP.tb_top__DOT__dut__DOT__clk), false, VLVT_UINT8, VLVD_NODIR|VLVF_PUB_RW, 0, 0);
    __Vscopep_tb_top__dut->varInsert("i_flush", &(TOP.tb_top__DOT__dut__DOT__i_flush), false, VLVT_UINT8, VLVD_NODIR|VLVF_PUB_RW, 0, 0);
    __Vscopep_tb_top__dut->varInsert("i_redirect_pc", &(TOP.tb_top__DOT__dut__DOT__i_redirect_pc), false, VLVT_UINT32, VLVD_NODIR|VLVF_PUB_RW, 0, 1 ,31,0);
    __Vscopep_tb_top__dut->varInsert("i_stall", &(TOP.tb_top__DOT__dut__DOT__i_stall), false, VLVT_UINT8, VLVD_NODIR|VLVF_PUB_RW, 0, 0);
    __Vscopep_tb_top__dut->varInsert("o_if_instr", &(TOP.tb_top__DOT__dut__DOT__o_if_instr), false, VLVT_UINT32, VLVD_NODIR|VLVF_PUB_RW, 0, 1 ,31,0);
    __Vscopep_tb_top__dut->varInsert("o_if_pc", &(TOP.tb_top__DOT__dut__DOT__o_if_pc), false, VLVT_UINT32, VLVD_NODIR|VLVF_PUB_RW, 0, 1 ,31,0);
    __Vscopep_tb_top__dut->varInsert("o_if_valid", &(TOP.tb_top__DOT__dut__DOT__o_if_valid), false, VLVT_UINT8, VLVD_NODIR|VLVF_PUB_RW, 0, 0);
    __Vscopep_tb_top__dut->varInsert("pc_d", &(TOP.tb_top__DOT__dut__DOT__pc_d), false, VLVT_UINT32, VLVD_NODIR|VLVF_PUB_RW, 0, 1 ,31,0);
    __Vscopep_tb_top__dut->varInsert("pc_q", &(TOP.tb_top__DOT__dut__DOT__pc_q), false, VLVT_UINT32, VLVD_NODIR|VLVF_PUB_RW, 0, 1 ,31,0);
    __Vscopep_tb_top__dut->varInsert("rst_n", &(TOP.tb_top__DOT__dut__DOT__rst_n), false, VLVT_UINT8, VLVD_NODIR|VLVF_PUB_RW, 0, 0);
    __Vscopep_tb_top__dut->varInsert("waiting", &(TOP.tb_top__DOT__dut__DOT__waiting), false, VLVT_UINT8, VLVD_NODIR|VLVF_PUB_RW, 0, 0);
    __Vscopep_tb_top__imem_if->varInsert("clk", &(TOP__tb_top__DOT__imem_if.clk), false, VLVT_UINT8, VLVD_IN|VLVF_PUB_RW, 0, 0);
    __Vscopep_tb_top__imem_if->varInsert("m_addr", &(TOP__tb_top__DOT__imem_if.m_addr), false, VLVT_UINT32, VLVD_NODIR|VLVF_PUB_RW, 0, 1 ,31,0);
    __Vscopep_tb_top__imem_if->varInsert("m_valid", &(TOP__tb_top__DOT__imem_if.m_valid), false, VLVT_UINT8, VLVD_NODIR|VLVF_PUB_RW, 0, 0);
    __Vscopep_tb_top__imem_if->varInsert("m_wdata", &(TOP__tb_top__DOT__imem_if.m_wdata), false, VLVT_UINT32, VLVD_NODIR|VLVF_PUB_RW, 0, 1 ,31,0);
    __Vscopep_tb_top__imem_if->varInsert("m_wstrb", &(TOP__tb_top__DOT__imem_if.m_wstrb), false, VLVT_UINT8, VLVD_NODIR|VLVF_PUB_RW, 0, 1 ,3,0);
    __Vscopep_tb_top__imem_if->varInsert("s_rdata", &(TOP__tb_top__DOT__imem_if.s_rdata), false, VLVT_UINT32, VLVD_NODIR|VLVF_PUB_RW, 0, 1 ,31,0);
    __Vscopep_tb_top__imem_if->varInsert("s_ready", &(TOP__tb_top__DOT__imem_if.s_ready), false, VLVT_UINT8, VLVD_NODIR|VLVF_PUB_RW, 0, 0);
}

Vtop__Syms::~Vtop__Syms() {
    // Tear down scope hierarchy
    __Vhier.remove(0, __Vscopep_tb_top);
    __Vhier.remove(__Vscopep_tb_top, __Vscopep_tb_top__dut);
    __Vhier.remove(__Vscopep_tb_top, __Vscopep_tb_top__imem_if);
    // Clear keys from hierarchy map after values have been removed
    __Vhier.clear();
    if (__Vm_dumping) _traceDumpClose();
    // Tear down scopes
    VL_DO_CLEAR(delete __Vscopep_tb_top, __Vscopep_tb_top = nullptr);
    VL_DO_CLEAR(delete __Vscopep_tb_top__dut, __Vscopep_tb_top__dut = nullptr);
    VL_DO_CLEAR(delete __Vscopep_tb_top__imem_if, __Vscopep_tb_top__imem_if = nullptr);
    // Tear down sub module instances
    TOP__tb_top__DOT__imem_if.dtor();
}

void Vtop__Syms::_traceDump() {
    const VerilatedLockGuard lock{__Vm_dumperMutex};
    __Vm_dumperp->dump(VL_TIME_Q());
}

void Vtop__Syms::_traceDumpOpen() {
    const VerilatedLockGuard lock{__Vm_dumperMutex};
    if (VL_UNLIKELY(!__Vm_dumperp)) {
        __Vm_dumperp = new VerilatedVcdC();
        __Vm_modelp->trace(__Vm_dumperp, 0, 0);
        const std::string dumpfile = _vm_contextp__->dumpfileCheck();
        __Vm_dumperp->open(dumpfile.c_str());
        __Vm_dumping = true;
    }
}

void Vtop__Syms::_traceDumpClose() {
    const VerilatedLockGuard lock{__Vm_dumperMutex};
    __Vm_dumping = false;
    VL_DO_CLEAR(delete __Vm_dumperp, __Vm_dumperp = nullptr);
}
