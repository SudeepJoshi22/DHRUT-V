#!/usr/bin/env python3
"""Upload an ELF over the board USB serial port, then capture its UART output.
Open the port first, then press and release reset when prompted.
"""
import argparse
import errno
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


def open_uart(serial_module, device):
    """Open the BL616 bridge while ignoring its unsupported DTR/RTS ioctls."""
    class BridgeSerial(serial_module.Serial):
        def _update_dtr_state(self):
            try:
                super()._update_dtr_state()
            except OSError as error:
                if error.errno != errno.EIO:
                    raise

        def _update_rts_state(self):
            try:
                super()._update_rts_state()
            except OSError as error:
                if error.errno != errno.EIO:
                    raise

    return BridgeSerial(device, 115200, timeout=0.1, write_timeout=10,
                        rtscts=False, dsrdtr=False, xonxoff=False)


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
    # Small flushed writes avoid dropped bytes on the BL616 USB bridge.
    for offset in range(0, len(frame), 32):
        chunk = frame[offset:offset + 32]
        written = port.write(chunk)
        if written != len(chunk):
            raise RuntimeError(
                f'Short serial write at frame byte {offset}: '
                f'wrote {written} of {len(chunk)} bytes')
        port.flush()
        time.sleep(0.001)

    ack_started = time.monotonic()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ack = port.read(1)  # Never consume the first program-output byte.
        if ack == b'K':
            return
        if ack == b'E':
            elapsed = time.monotonic() - ack_started
            raise RuntimeError(
                f'FPGA rejected upload {elapsed:.3f}s after transfer; reload '
                'cpu_top.fs to restore the baked image, then retry')
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
    ap.add_argument('elf', type=Path, nargs='?',
                    help='bare-metal ELF to upload (omit with --monitor)')
    ap.add_argument('--port', required=True, help='/dev/serial/by-id/... or COM port')
    ap.add_argument('--log', type=Path, default=Path('benchmark-uart.log'))
    ap.add_argument('--timeout', type=float, default=120)
    ap.add_argument('--interactive', action='store_true',
                    help='after upload, connect stdin/stdout instead of waiting for DHRUTV_RESULT')
    ap.add_argument('--monitor', action='store_true',
                    help='open an interactive UART terminal; do not upload an ELF')
    args = ap.parse_args()
    if args.timeout <= 0:
        ap.error('--timeout must be positive')
    if args.monitor and args.elf:
        ap.error('--monitor does not take an ELF')
    if not args.monitor and not args.elf:
        ap.error('an ELF is required unless --monitor is used')

    frame = elf_hash = build_metadata = None
    if not args.monitor:
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
    try:
        with open_uart(serial, args.port) as port:
            port.reset_input_buffer()
            if args.monitor:
                interactive_console(port)
                return
            print('Press and release FPGA reset now; waiting for loader ready...', flush=True)
            upload(port, frame)
            if args.interactive:
                interactive_console(port)
                return
            with args.log.open('wb') as log:
                result = capture(port, log, args.timeout)
    except (serial.SerialException, OSError) as error:
        if getattr(error, 'errno', None) == 13:
            raise RuntimeError(
                f'Permission denied opening {args.port}. Add your user to the '
                'dialout group with `sudo usermod -aG dialout "$USER"`, then '
                'log out and back in (or run `newgrp dialout` for a new shell).'
            ) from error
        if getattr(error, 'errno', None) == errno.EIO:
            raise RuntimeError(
                f'The USB bridge rejected serial control on {args.port}. '
                'Close any terminal using the port, unplug and reconnect the '
                'board, then retry with the FPGA UART interface (normally if01).'
            ) from error
        raise RuntimeError(f'Cannot open serial port {args.port}: {error}') from error
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
