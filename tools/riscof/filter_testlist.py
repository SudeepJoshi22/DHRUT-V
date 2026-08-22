#!/usr/bin/env python3
"""Filter a riscof test_list.yaml down to tests DHRUT-V can actually pass.

Excludes:
  - rv32i_m/pmp/*        - no PMP CSRs implemented (only gated on Zicsr in
                            the arch-test suite's RVTEST_ISA tags, not a
                            real PMP capability marker - see rtl/csr/README.md
                            / the M7 CSR plan for why Zicsr is declared)
  - misalign*.S          - misaligned-access trapping (branch/jal/jalr/
                            load/store) isn't implemented

Usage:
    python3 tools/riscof/filter_testlist.py <in_test_list.yaml> <out_test_list.yaml>
"""
import sys
import yaml


def is_excluded(test_path: str) -> bool:
    if "/pmp/" in test_path:
        return True
    filename = test_path.rsplit("/", 1)[-1]
    if filename.startswith("misalign"):
        return True
    return False


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)

    in_path, out_path = sys.argv[1], sys.argv[2]

    with open(in_path) as f:
        full = yaml.safe_load(f)

    filtered = {path: meta for path, meta in full.items() if not is_excluded(path)}

    excluded_count = len(full) - len(filtered)
    print(f"{len(full)} tests -> {len(filtered)} tests ({excluded_count} excluded)")

    with open(out_path, "w") as f:
        yaml.dump(filtered, f, default_flow_style=False)


if __name__ == "__main__":
    main()
