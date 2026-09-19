#!/usr/bin/env python3
"""Upload an ELF over the board USB serial port, then capture its UART output.
Open the port first, then press and release reset when prompted.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import time
from mkmem import BASE, load_verilog_hex, symbols_from_elf, validate_layout


def frame_from_elf(elf):
    symbols = symbols_from_elf(elf)
    if symbols.get('_start') != BASE:
        raise ValueError('ELF entry symbol _start must be 0x80000000')
    with tempfile.TemporaryDirectory() as temp:
        hexf = Path(temp) / 'image.hex'
        subprocess.run(['riscv-none-elf-objcopy', '-O', 'verilog', str(elf), str(hexf)], check=True)
        mem = load_verilog_hex(hexf)
    validate_layout(mem, 4096, 8192, symbols)
    payload = bytes(mem.get(a, 0) for a in range(BASE, max(mem) + 1))
    return b'DHRV' + struct.pack('<I', len(payload)) + payload + struct.pack('<I', sum(payload) & 0xffffffff)


def upload(port, frame, timeout=15):
    # The reset greeting removes human timing from the 500 ms boot window.
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if port.read(1) == b'R':
            break
    else:
        raise TimeoutError('No loader ready greeting; press reset and check the serial port')
    port.write(frame)
    port.flush()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ack = port.read(1)  # Never consume the first program-output byte.
        if ack == b'K':
            return
        if ack == b'E':
            raise RuntimeError('FPGA rejected upload; hold reset and retry')
    raise TimeoutError('No loader acknowledgment; check port, reset timing and bridge UART mode')


def capture(port, log, timeout):
    deadline = time.monotonic() + timeout
    line = bytearray()
    while time.monotonic() < deadline:
        data = port.read(1)
        if not data:
            continue
        log.write(data); log.flush()
        sys.stdout.write(data.decode('ascii', errors='replace')); sys.stdout.flush()
        line.extend(data)
        if data == b'\n':
            match = re.fullmatch(rb'DHRUTV_RESULT (dhrystone|coremark) iterations=(\d+) cycles=(\d+) clock_hz=(\d+) errors=(\d+)\r?\n', bytes(line))
            line.clear()
            if match:
                kind = match[1].decode()
                runs, cycles, hz, errors = map(int, match.groups()[1:])
                if not runs or not cycles or not hz:
                    raise RuntimeError('Invalid zero measurement')
                normalized = runs * 1_000_000 / cycles / (1757 if kind == 'dhrystone' else 1)
                result = dict(benchmark=kind, iterations=runs, cycles=cycles, clock_hz=hz,
                              errors=errors, seconds=cycles / hz, normalized=normalized,
                              units='DMIPS/MHz' if kind == 'dhrystone' else 'CoreMark/MHz')
                print(f"Measured: {normalized:.6f} {result['units']}; {result['seconds']:.3f}s; errors={errors}")
                return result
    raise TimeoutError('No complete benchmark result before capture timeout')


def interactive_console(port):
    from serial.tools.miniterm import Miniterm, key_description
    terminal = Miniterm(port, echo=False, eol='crlf', filters=())
    terminal.raw = True
    terminal.set_rx_encoding('UTF-8')
    terminal.set_tx_encoding('UTF-8')
    print(f'Interactive UART started; quit with {key_description(terminal.exit_character)}',
          file=sys.stderr)
    terminal.start()
    try:
        terminal.join(True)
    except KeyboardInterrupt:
        pass
    terminal.join()
    terminal.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('elf', type=Path)
    ap.add_argument('--port', required=True, help='/dev/serial/by-id/... or COM port')
    ap.add_argument('--log', type=Path, default=Path('benchmark-uart.log'))
    ap.add_argument('--timeout', type=float, default=120)
    ap.add_argument('--interactive', action='store_true',
                    help='after upload, connect stdin/stdout instead of waiting for DHRUTV_RESULT')
    args = ap.parse_args()
    if args.timeout <= 0:
        ap.error('--timeout must be positive')
    frame = frame_from_elf(args.elf)
    elf_hash = hashlib.sha256(args.elf.read_bytes()).hexdigest()
    metadata = args.elf.with_suffix('.json')
    build_metadata = json.loads(metadata.read_text()) if metadata.exists() else None
    if build_metadata and build_metadata.get('elf_sha256') != elf_hash:
        raise RuntimeError('Build metadata does not match uploaded ELF')
    try:
        import serial
    except ImportError as error:
        raise RuntimeError('pyserial is required: install it with python3 -m pip install pyserial') from error
    with serial.Serial(args.port, 115200, timeout=0.1, write_timeout=10,
                       rtscts=False, dsrdtr=False, xonxoff=False) as port:
        port.reset_input_buffer()
        print('Press and release FPGA reset now; waiting for loader ready...', flush=True)
        upload(port, frame)
        if args.interactive:
            interactive_console(port)
            return
        with args.log.open('wb') as log:
            result = capture(port, log, args.timeout)
    result['elf_sha256'] = elf_hash
    if build_metadata:
        result['build'] = build_metadata
    args.log.with_suffix('.json').write_text(json.dumps(result, indent=2) + '\n')
    if result['errors']:
        sys.exit(1)

if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, TimeoutError) as error:
        sys.exit(str(error))
