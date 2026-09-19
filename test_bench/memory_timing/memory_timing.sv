module memory_timing;
  logic clk, rst_n;
  mem_if #(.DATA_W(64)) imem_if(clk, rst_n);
  mem_if dmem_if(clk, rst_n);
  mem_if #(.DATA_W(64)) ref_i(clk, rst_n);
  mem_if ref_d(clk, rst_n);
  assign ref_i.m_valid=imem_if.m_valid;
  assign ref_i.m_addr=imem_if.m_addr;
  assign ref_i.m_flush=imem_if.m_flush;
  assign ref_i.m_wdata=0;
  assign ref_i.m_wstrb=0;
  assign ref_d.m_valid=dmem_if.m_valid;
  assign ref_d.m_addr=dmem_if.m_addr;
  assign ref_d.m_flush=dmem_if.m_flush;
  assign ref_d.m_wdata=dmem_if.m_wdata;
  assign ref_d.m_wstrb=dmem_if.m_wstrb;
  bram_slave #(.DATA_W(64),.DEPTH(16),.WRITABLE(0),.INIT_FILE("imem.hex")) IMEM(clk,rst_n,ref_i);
  bram_slave #(.DEPTH(32),.INIT_FILE("dmem.hex")) DMEM(clk,rst_n,ref_d);
endmodule
