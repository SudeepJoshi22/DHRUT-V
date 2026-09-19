// RAM retains its existing high-bit aliases. Low addresses go to the UART,
// whose exact register decode returns zero for unmapped accesses.
module dmem_splitter(mem_if.slave cpu, mem_if.master ram, mem_if.master uart);
  assign ram.m_addr = cpu.m_addr;
  assign uart.m_addr = cpu.m_addr;
  assign ram.m_wdata = cpu.m_wdata;
  assign uart.m_wdata = cpu.m_wdata;
  assign ram.m_wstrb = cpu.m_wstrb;
  assign uart.m_wstrb = cpu.m_wstrb;
  assign ram.m_flush = cpu.m_flush;
  assign uart.m_flush = cpu.m_flush;
  assign ram.m_valid = cpu.m_valid && cpu.m_addr[31];
  assign uart.m_valid = cpu.m_valid && !cpu.m_addr[31];
  assign cpu.s_ready = cpu.m_addr[31] ? ram.s_ready : uart.s_ready;
  assign cpu.s_rdata = cpu.m_addr[31] ? ram.s_rdata : uart.s_rdata;
endmodule
