"""Reporter must not turn an incomplete run or a stale ELF into a score."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("bench_report", Path(__file__).parents[1] / "bench_report.py")
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


class ReportChecks(unittest.TestCase):
    def invoke(self, *, complete=True, cycles=100, errors=0, mismatch=False):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            build = root / "tests/build/sample"
            build.mkdir(parents=True)
            (build / "sample.elf").write_bytes(b"test ELF")
            symbols = {"dhrutv_final_total_cycles": 0x1000,
                       "dhrutv_final_iterations": 0x1004,
                       "dhrutv_final_errors": 0x1008,
                       "dhrutv_final_mhz": 0x100c}
            lines = [f"DMEM WRITE addr=0x{addr:x} wdata=0x{value:x} wstrb=0xf\n"
                     for addr, value in [(0x1000, cycles), (0x1004, 1),
                                         (0x1008, errors), (0x100c, 100)]]
            if complete:
                lines.append("PASS: tohost=0x00000001\n")
            (build / "simulation.log").write_text("".join(lines))
            (build / "build.json").write_text(json.dumps({
                "elf_sha256": "stale" if mismatch else hashlib.sha256(b"test ELF").hexdigest()}))
            with patch.object(report, "ROOT", root), \
                    patch.object(report, "elf_symbol_addr", side_effect=lambda elf, name: symbols.get(name)), \
                    patch("sys.argv", ["bench_report", "sample", "--kind", "coremark", "--json"]), \
                    contextlib.redirect_stdout(io.StringIO()) as out, \
                    contextlib.redirect_stderr(io.StringIO()):
                report.main()
                return json.loads(out.getvalue())

    def test_success(self):
        self.assertEqual(self.invoke()["cycles"], 100)

    def test_reject_incomplete_zero_error_and_stale_elf(self):
        for case in [{"complete": False}, {"cycles": 0}, {"errors": 1}, {"mismatch": True}]:
            with self.subTest(case=case), self.assertRaises(SystemExit) as error:
                self.invoke(**case)
            self.assertEqual(error.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
