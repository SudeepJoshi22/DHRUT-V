#!/usr/bin/env python3
"""Fast Spike checks of CoreMark's port, including a corrupted CRC ELF.

Uses the usual freestanding flags. Never changes protected benchmark sources;
the corruption and invalid-seed cases patch copies of an ELF in tests/build.
"""
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

from elftools.elf.elffile import ELFFile

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "tests/bench/coremark"
BUILD = ROOT / "tests/build/coremark_checks"


def symbols(elf):
    with elf.open("rb") as stream:
        image = ELFFile(stream)
        return {s.name: int(s["st_value"])
                for s in image.get_section_by_name(".symtab").iter_symbols()}


def patch_symbol(elf, name, value, size):
    with elf.open("rb") as stream:
        image = ELFFile(stream)
        sym = image.get_section_by_name(".symtab").get_symbol_by_name(name)[0]
        section = image.get_section(sym["st_shndx"])
        offset = section["sh_offset"] + sym["st_value"] - section["sh_addr"]
    with elf.open("r+b") as stream:
        stream.seek(offset)
        stream.write(value.to_bytes(size, "little"))


def build(name, *defines):
    elf = BUILD / f"{name}.elf"
    subprocess.run([
        "riscv-none-elf-gcc", "-march=rv32im_zicsr", "-mabi=ilp32", "-O2",
        "-ffreestanding", "-fno-stack-protector", "-fno-builtin", "-static",
        "-mcmodel=medany", "-fvisibility=hidden", "-nostdlib", "-nostartfiles",
        "-DITERATIONS=1", *defines, "-T", str(ROOT / "tests/linker_c.ld"),
        str(ROOT / "tests/crt0.S"), *map(str, sorted(SOURCE.glob("*.c"))),
        "-lgcc", "-o", str(elf)], check=True)
    return elf


def check(elf, expected):
    log = elf.with_suffix(".spike.log")
    with log.open("w") as stream:
        result = subprocess.run([
            "spike", "-l", "--log-commits", "--isa=rv32im_zicsr",
            "-m0x80000000:0x10000", str(elf)], stdout=stream,
            stderr=subprocess.STDOUT, timeout=30)
    addresses = symbols(elf)
    memory = {}
    verdicts = []
    for line in log.open():
        match = re.search(r"mem 0x([0-9a-f]+) 0x([0-9a-f]+)", line)
        if not match:
            continue
        addr, value = (int(v, 16) for v in match.groups())
        memory[addr] = value
        if addr == addresses["tohost"]:
            verdicts.append(value)
            # Stashes must be observable BEFORE completion, even with -O2.
            assert memory.get(addresses["dhrutv_final_iterations"]) == 1
            assert memory.get(addresses["dhrutv_final_total_cycles"], 0) > 0
    assert verdicts and all(v == expected for v in verdicts), (elf.name, verdicts)
    assert result.returncode == (expected >> 1), (elf.name, result.returncode)
    assert memory.get(addresses["dhrutv_final_errors"], 0) == (expected >> 1)
    print(f"PASS {elf.stem}: tohost={expected}, results stored before completion")
    return {"case": elf.stem, "tohost": expected,
            "elf_sha256": hashlib.sha256(elf.read_bytes()).hexdigest()}


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    for line in (SOURCE / "UPSTREAM.sha256").read_text().splitlines():
        digest, name = line.split()
        assert hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() == digest, name
    print("PASS all six protected sources match pinned EEMBC hashes")
    perf = build("performance", "-DPERFORMANCE_RUN=1", "-DCLOCKS_PER_SEC=1")
    validation = build("validation", "-DVALIDATION_RUN=1", "-DCLOCKS_PER_SEC=1")
    short = build("too_short", "-DPERFORMANCE_RUN=1", "-DCLOCKS_PER_SEC=27000000")
    corrupted = BUILD / "corrupt_crc.elf"
    shutil.copyfile(perf, corrupted)
    # For 2 KB performance seeds known_id=3. Flip that table entry only.
    with corrupted.open("rb") as stream:
        image = ELFFile(stream)
        sym = image.get_section_by_name(".symtab").get_symbol_by_name("list_known_crc")[0]
        section = image.get_section(sym["st_shndx"])
        offset = section["sh_offset"] + sym["st_value"] - section["sh_addr"] + 6
    with corrupted.open("r+b") as stream:
        stream.seek(offset)
        original = int.from_bytes(stream.read(2), "little")
        stream.seek(offset)
        stream.write((original ^ 1).to_bytes(2, "little"))
    unknown = BUILD / "unknown_seeds.elf"
    shutil.copyfile(perf, unknown)
    patch_symbol(unknown, "seed3_volatile", 0x67, 4)
    results = [check(elf, expected) for elf, expected in
               [(perf, 1), (validation, 1), (corrupted, 3), (unknown, 3), (short, 3)]]
    (BUILD / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
