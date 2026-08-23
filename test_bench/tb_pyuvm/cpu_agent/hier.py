"""
hier.py - DUT hierarchy resolution for testbench components.

The CPU pipeline signals used to live directly under `tb_top` (tb_top.ALU,
tb_top.if_id_valid, ...). They now live inside a `cpu_core` instance
(tb_top.CORE.ALU, ...), and superscalar work will likely relocate them
again. Rather than hardcoding a path in every component, signal lookups go
through here: they are tried against the core scope first, then the top
level, so genuinely top-level signals (clk, imem_if, dmem_if) keep working
unchanged.

Override the core instance name with the DUT_CORE_HIER environment
variable; set it to an empty string for a flat (pre-cpu_core) hierarchy.
"""

import os

DEFAULT_CORE_HIER = "CORE"


def get_core(dut):
    """
    Return the handle the pipeline signals live under.

    Falls back to `dut` itself if the configured core instance doesn't
    exist, so a flattened hierarchy still resolves.
    """
    if dut is None:
        return None

    hier = os.environ.get("DUT_CORE_HIER", DEFAULT_CORE_HIER)
    if not hier:
        return dut

    obj = dut
    for part in hier.split("."):
        try:
            obj = getattr(obj, part)
        except AttributeError:
            return dut
    return obj


def resolve(dut, path):
    """
    Resolve a dotted signal path, trying the core scope before the top
    level. Returns the handle, or None if the path exists in neither.

    e.g. resolve(dut, "ALU.uop_q")  -> tb_top.CORE.ALU.uop_q
         resolve(dut, "dmem_if.clk") -> tb_top.dmem_if.clk
    """
    if dut is None:
        return None

    parts = path.split(".")
    for base in (get_core(dut), dut):
        if base is None:
            continue
        obj = base
        ok = True
        for part in parts:
            try:
                obj = getattr(obj, part)
            except AttributeError:
                ok = False
                break
        if ok:
            return obj
    return None
