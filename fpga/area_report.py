#!/usr/bin/env python3
"""Report FPGA resource totals and module costs using complete Gowin synthesis.

Flat synthesis estimates device use; hierarchy-preserving synthesis attributes
cost to modules. LUT4, ALU, flip-flop, block-RAM and LUT-RAM budgets are separate.
Use --save/--compare for measurements and --flat-only for a single synthesis pass."""

import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent

# Device budgets; LUT4 and ALU cells occupy separate resource pools.
BUDGET = {"lut": 20736, "alu": 15552, "ff": 15552, "bsram": 46, "lutram": 648}

# Keep synthesis options consistent with fpga/Makefile.
SYNTH_OPTS = os.environ.get("SYNTH_OPTS", "-nowidelut")

LUT_CELLS = re.compile(r"^LUT[1-4]$")
ALU_CELLS = re.compile(r"^ALU$")
FF_CELLS = re.compile(r"^DFF[NSRPCE]*$")
BSRAM_CELLS = re.compile(r"^(SP|SPX9|SDP|SDPX9|DP|DPX9)$")
LUTRAM_CELLS = re.compile(r"^RAM16")
MUX_CELLS = re.compile(r"^MUX2_LUT[5-8]$")


def find_yosys():
    """yosys is vendored in tools/oss-cad-suite and is not on PATH by default."""
    if shutil.which("yosys"):
        return "yosys"
    vendored = REPO / "tools" / "oss-cad-suite" / "bin"
    if (vendored / "yosys").exists():
        os.environ["PATH"] = f"{vendored}:{os.environ.get('PATH', '')}"
        return "yosys"
    sys.exit("yosys not found: put it on PATH or source tools/oss-cad-suite/environment")


def read_filelist(path):
    """A .f filelist: one source per line, whole-line '#' comments only."""
    files = []
    for line in path.read_text().splitlines():
        s = line.strip()
        if s and not s.startswith("#"):
            files.append(s)
    return files


def module_to_file(files):
    """Map each SystemVerilog module name to the source file declaring it."""
    mapping = {}
    for f in files:
        p = (HERE / f).resolve()
        if not p.exists():
            continue
        try:
            text = p.read_text(errors="replace")
        except OSError:
            continue
        for m in re.finditer(r"^\s*module\s+([A-Za-z_]\w*)", text, re.M):
            try:
                rel = p.relative_to(REPO)
            except ValueError:
                rel = p
            mapping[m.group(1)] = str(rel)
    return mapping


def run_yosys(files, keep_hierarchy):
    """Run synth_gowin to completion and return its log."""
    joined = " ".join(files)
    if keep_hierarchy:
        # read_slang flattens at parse time unless told otherwise, which is why
        # `synth_gowin -noflatten` ALONE reports everything under cpu_top. Both
        # flags are required to get per-module numbers.
        script = (
            f"read_slang {joined} --top cpu_top --keep-hierarchy; "
            f"synth_gowin -top cpu_top {SYNTH_OPTS} -noflatten; stat"
        )
    else:
        script = (f"read_slang {joined} --top cpu_top; "
                  f"synth_gowin -top cpu_top {SYNTH_OPTS}; stat")

    proc = subprocess.run(
        [find_yosys(), "-m", "slang", "-p", script],
        cwd=HERE, capture_output=True, text=True,
    )
    log = proc.stdout + proc.stderr
    if "Printing statistics" not in log:
        sys.stderr.write(log[-3000:])
        sys.exit(f"synthesis failed (keep_hierarchy={keep_hierarchy})")
    return log


def parse_stat(log):
    """Pull per-module cell histograms out of the final `stat` output.

    Only the last `stat` block is considered, and only its "Local Count,
    excluding submodules" sections -- the "design hierarchy" summary double
    counts by design.
    """
    tail = log[log.rfind("Printing statistics"):]
    out = {}
    for name, body in re.findall(r"=== (\S+) ===\n(.*?)(?=\n=== |\Z)", tail, re.S):
        if name.startswith("$") or "hierarchy" in name:
            continue
        if "excluding submodules" not in body:
            continue
        counts = {}
        for cnt, cell in re.findall(r"^\s+(\d+)\s+(\S+)\s*$", body, re.M):
            counts[cell] = counts.get(cell, 0) + int(cnt)
        # read_slang names kept-hierarchy modules "<module>$<instance path>"
        mod, _, inst = name.partition("$")
        out.setdefault(mod, []).append((inst, counts))
    return out


def tally(counts):
    t = {"lut": 0, "alu": 0, "ff": 0, "bsram": 0, "lutram": 0, "mux": 0}
    for cell, n in counts.items():
        if LUT_CELLS.match(cell):
            t["lut"] += n
        elif ALU_CELLS.match(cell):
            t["alu"] += n
        elif FF_CELLS.match(cell):
            t["ff"] += n
        elif BSRAM_CELLS.match(cell):
            t["bsram"] += n
        elif LUTRAM_CELLS.match(cell):
            t["lutram"] += n
        elif MUX_CELLS.match(cell):
            t["mux"] += n
    return t


def collect(files):
    flat = tally(next(iter(parse_stat(run_yosys(files, False)).values()))[0][1])
    per_mod = {}
    for mod, insts in parse_stat(run_yosys(files, True)).items():
        if mod == "cpu_top" and len(insts) == 1 and not insts[0][0]:
            pass  # top-level glue; keep it, it is real area
        agg = {"lut": 0, "alu": 0, "ff": 0, "bsram": 0, "lutram": 0, "mux": 0,
               "instances": len(insts)}
        for _, counts in insts:
            t = tally(counts)
            for k in ("lut", "alu", "ff", "bsram", "lutram", "mux"):
                agg[k] += t[k]
        per_mod[mod] = agg
    return {"flat": flat, "modules": per_mod}


def bar(frac, width=18):
    filled = min(width, int(round(frac * width)))
    return "#" * filled + "." * (width - filled)


def print_report(data, mod2file, baseline=None):
    flat, mods = data["flat"], data["modules"]

    print()
    print("=" * 78)
    print("  VERDICT  (flat synthesis -- the number that must fit)")
    print("=" * 78)
    print(f"  {'resource':<10}{'used':>9}{'budget':>9}{'margin':>9}   utilisation")
    for key, label in (("lut", "LUT4"), ("alu", "ALU"), ("ff", "FF"),
                       ("bsram", "BSRAM"), ("lutram", "LUT-RAM")):
        used, cap = flat[key], BUDGET[key]
        frac = used / cap
        flag = "OVER" if used > cap else "ok"
        print(f"  {label:<10}{used:>9,}{cap:>9,}{cap - used:>+9,}   "
              f"[{bar(frac)}] {frac * 100:5.1f}% {flag}")
    if baseline:
        print()
        print("  vs baseline:", end="")
        for key, label in (("lut", "LUT4"), ("ff", "FF"), ("bsram", "BSRAM")):
            d = flat[key] - baseline["flat"][key]
            print(f"   {label} {d:+,}", end="")
        print()

    print()
    print("=" * 78)
    print("  PER-MODULE  (hierarchy kept -- for TARGETING, see caveat below)")
    print("=" * 78)

    base_mods = baseline["modules"] if baseline else {}
    rows = sorted(mods.items(), key=lambda kv: -kv[1]["lut"])
    total_lut = sum(m["lut"] for m in mods.values()) or 1

    hdr = f"  {'module':<17}{'LUT4':>9}{'FF':>7}{'mux':>7}{'x':>3}  {'%':>5}  file"
    if baseline:
        hdr = (f"  {'module':<17}{'LUT4':>9}{'delta':>8}{'FF':>7}{'x':>3}"
               f"  {'%':>5}  file")
    print(hdr)
    print("  " + "-" * 74)

    for mod, m in rows:
        if m["lut"] == 0 and m["ff"] == 0 and m["bsram"] == 0:
            continue
        src = mod2file.get(mod, "?")
        pct = m["lut"] / total_lut * 100
        if baseline:
            d = m["lut"] - base_mods.get(mod, {}).get("lut", 0)
            mark = " " if d == 0 else ("+" if d > 0 else "-")
            print(f"  {mod:<17}{m['lut']:>9,}{d:>+8,}{m['ff']:>7,}"
                  f"{m['instances']:>3}  {pct:>4.1f}% {mark} {src}")
        else:
            print(f"  {mod:<17}{m['lut']:>9,}{m['ff']:>7,}{m['mux']:>7,}"
                  f"{m['instances']:>3}  {pct:>4.1f}%  {src}")

    print("  " + "-" * 74)
    print(f"  {'SUM':<17}{total_lut:>9,}"
          f"{sum(m['ff'] for m in mods.values()):>7,}")
    print()
    print("  nextpnr is the final authority and runs ~1,100 LUT4 above this")
    print("  estimate (packing overhead). Use `make bitstream` for the real number.")
    print()
    print("  NOTE: the per-module sum exceeds the flat total on purpose. Keeping")
    print("  hierarchy disables cross-module optimisation, so these numbers are")
    print("  inflated and are only meaningful RELATIVE to each other. Rank with")
    print("  this table; judge fit with the VERDICT above.")
    print()
    if baseline:
        print("  'x' = number of instances; LUT+ALU is the total across all of them.")
    else:
        print("  'x' = instances.  'mux' = MUX2_LUT5..8, which use dedicated slice")
        print("  hardware and are NOT counted in LUT+ALU (their LUT4s already are).")
        print("  A high mux count with few FFs means the cost is multiplexing, not")
        print("  storage -- shrink what is being selected, not what is being stored.")
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--filelist", default="cpu_top_filelist.f")
    ap.add_argument("--save", metavar="FILE", help="write these numbers as a baseline")
    ap.add_argument("--compare", metavar="FILE", help="show per-module delta vs a baseline")
    ap.add_argument("--flat-only", action="store_true",
                    help="skip the hierarchical pass (verdict only, ~2x faster)")
    args = ap.parse_args()

    flpath = HERE / args.filelist
    if not flpath.exists():
        sys.exit(f"no such filelist: {flpath}")
    files = read_filelist(flpath)
    mod2file = module_to_file(files)

    print(f"synthesising {len(files)} sources from {args.filelist} ...",
          file=sys.stderr)
    if args.flat_only:
        data = {"flat": tally(next(iter(parse_stat(run_yosys(files, False)).values()))[0][1]),
                "modules": {}}
    else:
        data = collect(files)

    baseline = None
    if args.compare:
        baseline = json.loads(pathlib.Path(args.compare).read_text())

    print_report(data, mod2file, baseline)

    if args.save:
        pathlib.Path(args.save).write_text(json.dumps(data, indent=2))
        print(f"  baseline written to {args.save}")
        print()


if __name__ == "__main__":
    main()
