"""Exercise upload and capture over pseudo-terminals and bridge-like ports."""
import errno
import io
import os
from pathlib import Path
import pty
import struct
import sys
import threading
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from loadprog import open_uart, upload, capture
import serial


class HostSerialTest(unittest.TestCase):
    def test_open_uart_ignores_only_bridge_modem_eio(self):
        class FtdiBridge:
            class Serial:
                def __init__(self, *args, **kwargs):
                    self._update_dtr_state()
                    self._update_rts_state()

                def _update_dtr_state(self):
                    raise OSError(errno.EIO, 'unsupported DTR')

                def _update_rts_state(self):
                    raise OSError(errno.EIO, 'unsupported RTS')

        self.assertIsInstance(open_uart(FtdiBridge, '/dev/ttyUSB1'), FtdiBridge.Serial)

        class BrokenBridge(FtdiBridge):
            class Serial(FtdiBridge.Serial):
                def _update_rts_state(self):
                    raise OSError(errno.EPERM, 'real serial error')

        with self.assertRaises(OSError) as caught:
            open_uart(BrokenBridge, '/dev/ttyUSB1')
        self.assertEqual(caught.exception.errno, errno.EPERM)

    def test_ack_and_first_output_share_read_buffer(self):
        master, slave = pty.openpty()
        errors = []
        frame = b'DHRV' + struct.pack('<I', 3) + b'abc' + struct.pack('<I', sum(b'abc'))
        def board():
            try:
                time.sleep(0.05)
                os.write(master, b'R')
                incoming = bytearray()
                while len(incoming) < len(frame):
                    incoming.extend(os.read(master, len(frame)-len(incoming)))
                assert incoming == frame
                os.write(master, b'KDHRUTV_RESULT dhrystone iterations=1 cycles=758 clock_hz=27000000 errors=0\r\n')
            except BaseException as error:
                errors.append(error)
        try:
            with serial.Serial(os.ttyname(slave), 115200, timeout=0.1) as port:
                worker = threading.Thread(target=board, daemon=True)
                worker.start()
                upload(port, frame, timeout=2)
                log = io.BytesIO()
                result = capture(port, log, timeout=2)
                worker.join(2)
                self.assertFalse(worker.is_alive())
                self.assertFalse(errors, errors)
                self.assertTrue(log.getvalue().startswith(b'DHRUTV_RESULT'))
                self.assertEqual(result['cycles'], 758)
        finally:
            os.close(master); os.close(slave)

    def test_rejected_and_silent_loader(self):
        class Port:
            def __init__(self, data):
                self.data = iter(data)
                self.writes = []
            def read(self, count): return next(self.data, b'')
            def write(self, data):
                self.writes.append(data)
                return len(data)
            def flush(self): pass

        rejected = Port([b'R', b'E'])
        with self.assertRaises(RuntimeError):
            upload(rejected, b'x' * 100, timeout=0.01)
        self.assertEqual([len(chunk) for chunk in rejected.writes], [32, 32, 32, 4])

        with self.assertRaises(TimeoutError):
            upload(Port([]), b'image', timeout=0.01)

if __name__ == '__main__':
    unittest.main()
