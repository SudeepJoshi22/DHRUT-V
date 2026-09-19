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

  // Clocked masters expose simulator scheduling differences: requests change
  // in the same NBA update as the CPU's real fetch/LSU outputs.
  logic [7:0] step_q;
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) step_q <= 0;
    else step_q <= step_q + 1'b1;
  mem_if #(.DATA_W(64)) edge_i(clk, rst_n);
  mem_if #(.DATA_W(64)) edge_ref_i(clk, rst_n);
  mem_if edge_d(clk, rst_n);
  mem_if edge_ref_d(clk, rst_n);
  assign edge_i.m_valid = step_q[1:0] != 0;
  assign edge_i.m_addr = 32'h8000_0000 + {25'b0, step_q[4:1], 3'b0};
  assign edge_i.m_flush = step_q[3];
  assign edge_i.m_wdata = 0;
  assign edge_i.m_wstrb = 0;
  assign edge_d.m_valid = edge_i.m_valid;
  assign edge_d.m_addr = edge_i.m_addr;
  assign edge_d.m_flush = edge_i.m_flush;
  assign edge_d.m_wdata = {24'b0, step_q};
  assign edge_d.m_wstrb = step_q[3:0];
  assign edge_ref_i.m_valid = edge_i.m_valid;
  assign edge_ref_i.m_addr = edge_i.m_addr;
  assign edge_ref_i.m_flush = edge_i.m_flush;
  assign edge_ref_i.m_wdata = 0;
  assign edge_ref_i.m_wstrb = 0;
  assign edge_ref_d.m_valid = edge_d.m_valid;
  assign edge_ref_d.m_addr = edge_d.m_addr;
  assign edge_ref_d.m_flush = edge_d.m_flush;
  assign edge_ref_d.m_wdata = edge_d.m_wdata;
  assign edge_ref_d.m_wstrb = edge_d.m_wstrb;
  bram_slave #(.DATA_W(64),.DEPTH(16),.WRITABLE(0),.INIT_FILE("imem.hex")) EDGE_IMEM(clk,rst_n,edge_ref_i);
  bram_slave #(.DEPTH(32),.INIT_FILE("dmem.hex")) EDGE_DMEM(clk,rst_n,edge_ref_d);
endmodule
