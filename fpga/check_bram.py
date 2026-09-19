#!/usr/bin/env python3
"""Run an existing ELF/hex pair through cpu_top's actual BRAM wrapper.

Uses an isolated Verilator binary testbench, not the shared pyUVM build.
Example: python3 fpga/check_bram.py coremark_fixed --expected-cycles 383043
"""
import argparse
from pathlib import Path
import subprocess
import sys

from mkmem import symbols_from_elf

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("test")
    parser.add_argument("--expected-cycles", type=int)
    args = parser.parse_args()
    source = ROOT / "tests/build" / args.test
    elf = source / f"{args.test}.elf"
    build = ROOT / "tests/build" / f"bram_{args.test}"
    build.mkdir(parents=True, exist_ok=True)
    symbols = symbols_from_elf(elf)
    tohost = symbols["tohost"]
    cycle_address = symbols.get("dhrutv_final_total_cycles", symbols.get("dhrutv_final_cycles", 0))
    subprocess.run([sys.executable, str(ROOT / "fpga/mkmem.py"),
                    str(source / f"{args.test}.hex"), "--elf", str(elf),
                    "--outdir", str(build)], check=True)
    # Paths are passed to subprocess as arguments; the HDL uses fixed filenames
    # in the isolated run directory, keeping build paths out of HDL string literals.
    top = build / "bram_check.sv"
    top.write_text(f"""`timescale 1ns/1ps
module bram_check;
  logic clk = 0;
  always #5 clk = ~clk;
  wire [5:0] led;
  cpu_top #(.ENABLE_LOADER(0), .TOHOST_ADDR(32'h{tohost:08x})) dut(.clk(clk), .rst_btn(1'b0), .uart_rx(1'b1), .uart_tx(), .led(led));
  integer elapsed = 0;
  logic [31:0] measured = 0;
  always @(posedge clk) begin
    elapsed <= elapsed + 1;
    if (elapsed > 1000000) $fatal(1, "CPU BRAM watchdog timeout");
    if (dut.dmem_if.m_valid && dut.dmem_if.s_ready && dut.dmem_if.m_wstrb == 4'hf) begin
      if (dut.dmem_if.m_addr == 32'h{cycle_address:08x}) measured = dut.dmem_if.m_wdata;
      if (dut.dmem_if.m_addr == 32'h{tohost:08x}) begin
        if (dut.dmem_if.m_wdata != 1) $fatal(1, "CPU BRAM tohost failure: %x", dut.dmem_if.m_wdata);
        if ({int(bool(cycle_address))} && measured == 0) $fatal(1, "Missing timed result");
        if ({int(args.expected_cycles is not None)} && measured != 32'd{args.expected_cycles or 0})
          $fatal(1, "Cycle mismatch: measured %0d expected {args.expected_cycles}", measured);
        #1;
        if (led[3:2] != 2'b00) $fatal(1, "Completion LEDs did not latch PASS");
        $display("PASS cpu_top BRAM: tohost=1 timed_cycles=%0d total_cycles=%0d", measured, elapsed);
        $finish;
      end
    end
  end
endmodule
""")
    files = [(ROOT / "fpga" / line.strip()).resolve()
             for line in (ROOT / "fpga/cpu_top_filelist.f").read_text().splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    with (build / "build.log").open("w") as log:
        subprocess.run(["verilator", "--binary", "--timing", "--assert", "-Wno-fatal",
                        "-Wno-MULTIDRIVEN", "+define+SIMULATION", "--top-module", "bram_check",
                        "--Mdir", str(build / "obj"), "-j", "2", *map(str, files), str(top)],
                       cwd=build, stdout=log, stderr=subprocess.STDOUT, check=True)
    with (build / "simulation.log").open("w") as log:
        subprocess.run([str(build / "obj/Vbram_check")], cwd=build,
                       stdout=log, stderr=subprocess.STDOUT, timeout=60, check=True)
    print((build / "simulation.log").read_text())


if __name__ == "__main__":
    main()
