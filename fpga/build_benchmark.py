#!/usr/bin/env python3
"""Build UART-enabled hardware firmware without running a simulator."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from mkmem import load_verilog_hex, symbols_from_elf, validate_layout

ROOT = Path(__file__).resolve().parent.parent


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('benchmark', choices=['dhrystone', 'coremark'])
    ap.add_argument('--iterations', type=int, required=True)
    ap.add_argument('--validation', action='store_true', help='CoreMark validation seeds')
    ap.add_argument('--clock-hz', type=int, default=27000000)
    args = ap.parse_args()
    if args.validation and args.benchmark != 'coremark':
        ap.error('--validation is only supported for CoreMark')
    if args.iterations <= 0 or args.clock_hz <= 0:
        ap.error('iterations and clock must be positive')
    name = f'{args.benchmark}_hw_{args.iterations}' + ('_validation' if args.validation else '')
    out = ROOT / 'tests/build' / name
    out.mkdir(parents=True, exist_ok=True)
    elf = out / f'{name}.elf'
    flags = ['-march=rv32im_zicsr', '-mabi=ilp32', '-O2', '-ffreestanding',
             '-fno-stack-protector', '-fno-builtin', '-static', '-mcmodel=medany',
             '-fvisibility=hidden', '-nostdlib', '-nostartfiles', '-DDHRUTV_UART=1',
             f'-DITERATIONS={args.iterations}', f'-DCLOCKS_PER_SEC={args.clock_hz}',
             f'-DDHRUTV_CLOCK_HZ={args.clock_hz}', f'-DDHRUTV_ASSUMED_MHZ={args.clock_hz // 1000000}']
    if args.benchmark == 'dhrystone':
        flags += ['-DDHRUTV_RTLSIM=1']  # selects mcycle timer, not a simulation memory map
    else:
        flags += ['-DVALIDATION_RUN=1' if args.validation else '-DPERFORMANCE_RUN=1']
    flags_string = ' '.join(flags)
    sources = sorted((ROOT / 'tests/bench' / args.benchmark).glob('*.c'))
    cmd = ['riscv-none-elf-gcc', *flags, f'-DFLAGS_STR="{flags_string}"',
           '-T', str(ROOT / 'tests/linker_c.ld'), str(ROOT / 'tests/crt0.S'),
           *map(str, sources), '-lgcc', '-o', str(elf)]
    subprocess.run(cmd, check=True)
    hexf = elf.with_suffix('.hex')
    subprocess.run(['riscv-none-elf-objcopy', '-O', 'verilog', str(elf), str(hexf)], check=True)
    validate_layout(load_verilog_hex(hexf), 4096, 8192, symbols_from_elf(elf))
    metadata = dict(benchmark=args.benchmark, iterations=args.iterations, clock_hz=args.clock_hz,
                    validation=args.validation, command=cmd,
                    compiler=subprocess.check_output(['riscv-none-elf-gcc', '--version'], text=True).splitlines()[0],
                    elf_sha256=hashlib.sha256(elf.read_bytes()).hexdigest())
    elf.with_suffix('.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(elf)
    if args.benchmark == 'coremark':
        print('Hardware clock enforced: runs below 10 seconds report failure. Increase iterations as needed.')

if __name__ == '__main__':
    main()
