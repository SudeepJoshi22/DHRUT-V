#!/usr/bin/env python3
"""
Turn a test's Verilog byte-hex image into $readmemh files for cpu_top's BSRAMs.

tools/simulate.sh produces the program image with `objcopy -O verilog`, which
emits "@ADDR" lines followed by space-separated bytes. $readmemh, though, wants
one entry per line at the array's own width -- 64 bits for imem (ifetch.sv gets
two instructions per access) and 32 bits for dmem. This script does that split.

Both files are written from the SAME image, matching the testbench, where
imem_driver.py and dmem_driver.py each load TEST_HEX into their own dict.

Indices are computed exactly as bram_slave.sv computes them --
(addr >> shift) & (depth-1) -- so the upper-bit aliasing that maps the
0x8000_0000 link address to index 0 is reproduced here rather than assumed.

Usage:
  ./mkmem.py <image.hex> [--elf <prog.elf>] [--outdir .]
             [--imem-depth 1024] [--dmem-depth 2048]
"""

import argparse
import pathlib
import subprocess
import sys

NOP = 0x00000013


def load_verilog_hex(path):
    """Parse objcopy -O verilog output into {byte_addr: byte_value}."""
    mem = {}
    addr = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            if line.startswith("@"):
                addr = int(line[1:], 16)
                continue
            for tok in line.split():
                mem[addr] = int(tok, 16)
                addr += 1
    return mem


def pack_words(byte_mem, width_bytes):
    """Pack bytes into little-endian words of width_bytes, keyed by byte addr."""
    words = {}
    for a in byte_mem:
        base = a - (a % width_bytes)
        if base in words:
            continue
        val = 0
        for i in range(width_bytes):
            val |= byte_mem.get(base + i, 0) << (8 * i)
        words[base] = val
    return words


def build_array(words, depth, width_bytes, fill):
    """Map packed words onto the BSRAM array, mirroring bram_slave.sv indexing."""
    shift = width_bytes.bit_length() - 1  # 8 -> 3, 4 -> 2
    arr = [fill] * depth
    seen = {}
    collisions = []
    for addr, val in sorted(words.items()):
        idx = (addr >> shift) & (depth - 1)
        if idx in seen and seen[idx] != addr:
            collisions.append((seen[idx], addr, idx))
        seen[idx] = addr
        arr[idx] = val
    return arr, collisions


def write_hex(path, arr, width_bytes):
    digits = width_bytes * 2
    with open(path, "w") as f:
        for v in arr:
            f.write(f"{v:0{digits}x}\n")


def tohost_from_elf(elf):
    """Read the .tohost symbol address; linker.ld floats it after .text."""
    for nm in ("riscv-none-elf-nm", "riscv64-unknown-elf-nm", "riscv32-unknown-elf-nm"):
        try:
            out = subprocess.check_output([nm, "-n", str(elf)], text=True,
                                          stderr=subprocess.DEVNULL)
        except (FileNotFoundError, subprocess.CalledProcessError):
            continue
        for line in out.splitlines():
            parts = line.split()
            if len(parts) == 3 and parts[2] == "tohost":
                return int(parts[0], 16)
        return None
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image", help="objcopy -O verilog hex (tests/build/<t>/<t>.hex)")
    ap.add_argument("--elf", help="matching ELF, to report the real tohost address")
    ap.add_argument("--outdir", default=".", type=pathlib.Path)
    ap.add_argument("--imem-depth", type=int, default=1024)  # x 64-bit = 8 KB
    ap.add_argument("--dmem-depth", type=int, default=2048)  # x 32-bit = 8 KB
    args = ap.parse_args()

    byte_mem = load_verilog_hex(args.image)
    if not byte_mem:
        sys.exit(f"error: {args.image} contained no data")

    lo, hi = min(byte_mem), max(byte_mem)
    print(f"image  : {args.image}")
    print(f"span   : 0x{lo:08x} .. 0x{hi:08x}  ({hi - lo + 1} bytes)")

    imem, ic = build_array(pack_words(byte_mem, 8), args.imem_depth, 8,
                           (NOP << 32) | NOP)
    dmem, dc = build_array(pack_words(byte_mem, 4), args.dmem_depth, 4, 0)

    for name, cols, depth, kb in (("imem", ic, args.imem_depth, args.imem_depth * 8 // 1024),
                                  ("dmem", dc, args.dmem_depth, args.dmem_depth * 4 // 1024)):
        if cols:
            a, b, idx = cols[0]
            print(f"ERROR  : {name} too small ({kb} KB) -- 0x{a:08x} and "
                  f"0x{b:08x} both alias to index {idx}; "
                  f"{len(cols)} collision(s). Increase {name.upper()}_DEPTH.",
                  file=sys.stderr)
            sys.exit(1)

    args.outdir.mkdir(parents=True, exist_ok=True)
    ipath = args.outdir / "imem_init.hex"
    dpath = args.outdir / "dmem_init.hex"
    write_hex(ipath, imem, 8)
    write_hex(dpath, dmem, 4)
    print(f"wrote  : {ipath} ({args.imem_depth} x 64-bit, "
          f"{args.imem_depth * 8 // 1024} KB)")
    print(f"wrote  : {dpath} ({args.dmem_depth} x 32-bit, "
          f"{args.dmem_depth * 4 // 1024} KB)")

    if args.elf:
        th = tohost_from_elf(args.elf)
        if th is None:
            print("tohost : not found (is the ELF built, and nm on PATH?)")
        else:
            print(f"tohost : 0x{th:08x}   -> build with "
                  f"TOHOST_ADDR=32'h{th:08x} if it differs from the default")


if __name__ == "__main__":
    main()
