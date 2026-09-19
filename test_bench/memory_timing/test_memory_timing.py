"""Compare the real fixed-mode drivers against FPGA BRAM at both clock phases."""
import logging
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ReadOnly, Timer

from tb_pyuvm.imem_agent.imem_driver import IMemDriver
from tb_pyuvm.dmem_agent.dmem_driver import DMemDriver


@cocotb.test()
async def bram_contract(dut):
    pairs = [(dut.imem_if, dut.ref_i), (dut.dmem_if, dut.ref_d)]
    for bus, _ in pairs:
        bus.m_valid.value = 0
        bus.m_addr.value = 0x80000000
        bus.m_flush.value = 0
        bus.m_wdata.value = 0
        bus.m_wstrb.value = 0
    dut.rst_n.value = 0
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    for cls, bus, attr in [(IMemDriver, dut.imem_if, "imem_if"),
                           (DMemDriver, dut.dmem_if, "dmem_if"),
                           (IMemDriver, dut.edge_i, "imem_if"),
                           (DMemDriver, dut.edge_d, "dmem_if")]:
        # Only the responder is under test; the UVM environment is unnecessary.
        driver = object.__new__(cls)
        driver.logger = logging.getLogger(cls.__name__)
        driver.mem = {0x80000000 + i * 4: i + 1 for i in range(32)}
        setattr(driver, attr, bus)
        cocotb.start_soon(driver.run_phase())

    def compare():
        for model, reference in [*pairs, (dut.edge_i, dut.edge_ref_i),
                                 (dut.edge_d, dut.edge_ref_d)]:
            assert int(model.s_ready.value) == int(reference.s_ready.value)
            if reference.s_ready.value:
                assert int(model.s_rdata.value) == int(reference.s_rdata.value)

    async def step(valid=1, offset=0, flush=0, strobes=0, data=0, reset=1):
        await FallingEdge(dut.clk)
        dut.rst_n.value = reset
        for bus, _ in pairs:
            bus.m_valid.value = valid
            bus.m_addr.value = 0x80000000 + offset
            bus.m_flush.value = flush
        dut.dmem_if.m_wdata.value = data
        dut.dmem_if.m_wstrb.value = strobes
        # Address withdrawal/flush must gate an existing response immediately.
        await Timer(1, unit="ns")
        await ReadOnly()
        compare()
        await RisingEdge(dut.clk)
        await ReadOnly()
        compare()

    await step(valid=0, reset=0)
    await step(valid=0)
    for _ in range(6):
        await step()  # Held request: capture/response cadence, including repeats.
    await step(offset=8)
    await step(offset=16, flush=1)
    await step(valid=0)
    for mask in [15, 1, 2, 4, 8, 5, 10]:
        await step(offset=24, strobes=mask, data=0xA1B2C3D4)
        await step(offset=24, strobes=mask, data=0xA1B2C3D4)
        await step(offset=24)
        await step(offset=24)
    rng = random.Random(20260918)
    for _ in range(100):
        await step(valid=rng.randrange(2), offset=rng.randrange(16) * 8,
                   flush=rng.randrange(2), strobes=rng.randrange(16),
                   data=rng.getrandbits(32))
    await step(reset=0)
    await step(reset=0)
    await step()
    # An asynchronous reset pulse between clock edges must discard RESP.
    await Timer(1, unit="ns")
    dut.rst_n.value = 0
    await Timer(1, unit="ns")
    await ReadOnly()
    compare()
    await Timer(1, unit="ns")
    dut.rst_n.value = 1
    await Timer(1, unit="ns")
    await ReadOnly()
    compare()
    await step()
