#!/usr/bin/env python3
"""Native end-to-end UART/loader/CPU check, including corrupt-image recovery."""
from pathlib import Path
import argparse
import subprocess
import sys
from loadprog import frame_from_elf
from mkmem import symbols_from_elf

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('test', nargs='?', default='dhrystone_hw_1')
    parser.add_argument('--expected-errors', type=int, default=0)
    args = parser.parse_args()
    if args.expected_errors < 0:
        parser.error('--expected-errors cannot be negative')
    name = args.test
    expected_errors = args.expected_errors
    source = ROOT / 'tests/build' / name
    elf = source / f'{name}.elf'
    build = ROOT / 'tests/build' / f'loader_{name}'
    build.mkdir(parents=True, exist_ok=True)
    frame = frame_from_elf(elf)
    (build / 'frame.hex').write_text(''.join(f'{b:02x}\n' for b in frame))
    subprocess.run([sys.executable, str(ROOT / 'fpga/mkmem.py'), str(elf.with_suffix('.hex')),
                    '--elf', str(elf), '--outdir', str(build)], check=True)
    tohost = symbols_from_elf(elf)['tohost']
    text = (ROOT / 'fpga/tests/loader_check.sv').read_text()
    text = (text.replace('@FRAME_SIZE@', str(len(frame)))
                .replace('@TOHOST@', f'{tohost:08x}')
                .replace('@EXPECTED_ERRORS@', str(expected_errors)))
    (build / 'loader_check.sv').write_text(text)
    files = [(ROOT / 'fpga' / line.strip()).resolve()
             for line in (ROOT / 'fpga/cpu_top_filelist.f').read_text().splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    with (build / 'build.log').open('w') as log:
        subprocess.run(['verilator', '--binary', '--timing', '--assert', '-Wno-fatal',
                        '-Wno-MULTIDRIVEN', '+define+SIMULATION', '--top-module', 'loader_check',
                        '--Mdir', str(build / 'obj'), '-j', '2', *map(str, files),
                        str(build / 'loader_check.sv')], cwd=build, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    with (build / 'simulation.log').open('w') as log:
        subprocess.run(['stdbuf', '-oL', str(build / 'obj/Vloader_check')], cwd=build, stdout=log,
                       stderr=subprocess.STDOUT, timeout=60, check=True)
    print((build / 'simulation.log').read_text())

if __name__ == '__main__':
    main()
