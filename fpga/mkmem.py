#!/usr/bin/env python3
"""Convert objcopy Verilog byte hex into word and byte-lane BRAM images.

Instruction and data arrays use the same image. Low address bits index each
array; validate ELF data, BSS and stack bounds to prevent capacity overflow.
Usage: mkmem.py image.hex --elf program.elf --outdir directory"""

import argparse
import pathlib
import subprocess
import sys

NOP = 0x00000013
BASE = 0x80000000


def validate_layout(byte_mem, imem_depth, dmem_depth, symbols=None):
    """Reject wraparound, including ELF BSS/stack not present in objcopy hex."""
    for name, depth in [("imem", imem_depth), ("dmem", dmem_depth)]:
        if depth <= 0 or depth & (depth - 1):
            raise ValueError(f"{name} depth must be a positive power of two")
    limit = BASE + min(imem_depth * 8, dmem_depth * 4)
    if not byte_mem or min(byte_mem) < BASE or max(byte_mem) >= limit:
        raise ValueError(f"image must fit both memories in 0x{BASE:08x}..0x{limit-1:08x}")
    # The LED snoop still occupies the top dmem word until UART/MMIO lands.
    data_limit = BASE + dmem_depth * 4 - 4
    if max(byte_mem) >= data_limit:
        raise ValueError("image overlaps the reserved LED word at top of dmem")
    for name in ("_ebss", "_stack_top", "_end"):
        if symbols and name in symbols and not BASE <= symbols[name] <= data_limit:
            raise ValueError(f"{name}=0x{symbols[name]:08x} exceeds usable dmem end 0x{data_limit:08x}")


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


def symbols_from_elf(elf):
    """Read image bounds and tohost with the installed cross-toolchain."""
    for nm in ("riscv-none-elf-nm", "riscv64-unknown-elf-nm", "riscv32-unknown-elf-nm"):
        try:
            out = subprocess.check_output([nm, "-n", str(elf)], text=True,
                                          stderr=subprocess.DEVNULL)
        except (FileNotFoundError, subprocess.CalledProcessError):
            continue
        symbols = {}
        for line in out.splitlines():
            parts = line.split()
            if len(parts) == 3:
                symbols[parts[2]] = int(parts[0], 16)
        return symbols
    raise ValueError(f"cannot read {elf}: put a RISC-V nm on PATH and provide a valid ELF")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image", help="objcopy -O verilog hex (tests/build/<t>/<t>.hex)")
    ap.add_argument("--elf", help="matching ELF, to report the real tohost address")
    ap.add_argument("--outdir", default=".", type=pathlib.Path)
    ap.add_argument("--imem-depth", type=int, default=4096)  # x 64-bit = 32 KB
    ap.add_argument("--dmem-depth", type=int, default=8192)  # x 32-bit = 32 KB
    args = ap.parse_args()

    byte_mem = load_verilog_hex(args.image)
    if not byte_mem:
        sys.exit(f"error: {args.image} contained no data")
    try:
        symbols = symbols_from_elf(args.elf) if args.elf else {}
        validate_layout(byte_mem, args.imem_depth, args.dmem_depth, symbols)
    except ValueError as error:
        sys.exit(f"error: {error}")
    if not args.elf:
        print("note   : no ELF supplied; reserved stack/BSS bounds cannot be checked")

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

    # Generate a separate initialization file for each BRAM byte lane.
    for name, words, lanes in (("imem", imem, 8), ("dmem", dmem, 4)):
        for b in range(lanes):
            lane = [(w >> (8 * b)) & 0xFF for w in words]
            write_hex(args.outdir / f"{name}_init_b{b}.hex", lane, 1)
    print(f"wrote  : {ipath} ({args.imem_depth} x 64-bit, "
          f"{args.imem_depth * 8 // 1024} KB)")
    print(f"wrote  : {dpath} ({args.dmem_depth} x 32-bit, "
          f"{args.dmem_depth * 4 // 1024} KB)")
    print(f"wrote  : {args.outdir}/imem_init_b0..b7.hex "
          f"(byte lanes, {args.imem_depth} x 8-bit each)")
    print(f"wrote  : {args.outdir}/dmem_init_b0..b3.hex "
          f"(byte lanes, {args.dmem_depth} x 8-bit each)")

    if args.elf:
        th = symbols.get("tohost")
        if th is None:
            print("tohost : not found (is the ELF built, and nm on PATH?)")
        else:
            print(f"tohost : 0x{th:08x}   -> build with "
                  f"TOHOST_ADDR=32'h{th:08x} if it differs from the default")


if __name__ == "__main__":
    main()
