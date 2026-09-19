"""Fixed-mode handshake model of fpga/rtl/bram_slave.sv.

Capture/read/write at an IDLE rising edge, present the response during RESP,
then return to IDLE at the next edge. No extra await is a 'wait state': the
registered response is already the FPGA's one wait state. Address capacity
remains the Python backing store's responsibility.
"""
import cocotb
from cocotb.triggers import RisingEdge, ValueChange, First, Event


async def run_bram_responder(bus, mem, *, data_w=32, writable=True, fill=0):
    response = False
    req_addr = 0
    rdata = 0
    changed = Event()

    async def drive_response():
        nonlocal response
        while True:
            changed.clear()
            if not bus.rst_n.value:
                response = False
            bus.s_rdata.value = rdata
            bus.s_ready.value = int(
                response and bool(bus.rst_n.value) and bool(bus.m_valid.value)
                and not bool(bus.m_flush.value)
                and int(bus.m_addr.value) == req_addr
            )
            await First(changed.wait(), ValueChange(bus.m_valid),
                        ValueChange(bus.m_addr), ValueChange(bus.m_flush),
                        ValueChange(bus.rst_n))

    gate = cocotb.start_soon(drive_response())
    try:
        while True:
            await RisingEdge(bus.clk)
            if not bus.rst_n.value:
                response = False
            elif response:
                response = False
            elif bus.m_valid.value and not bus.m_flush.value:
                req_addr = int(bus.m_addr.value)
                base = req_addr & ~((data_w // 8) - 1)
                rdata = sum(mem.get(base + off, fill) << (off * 8)
                            for off in range(0, data_w // 8, 4))
                if writable:
                    wdata, strobes = int(bus.m_wdata.value), int(bus.m_wstrb.value)
                    for byte in range(data_w // 8):
                        if strobes & (1 << byte):
                            addr = base + (byte & ~3)
                            shift = (byte % 4) * 8
                            old = mem.get(addr, 0)
                            mem[addr] = ((old & ~(255 << shift))
                                         | (((wdata >> (byte * 8)) & 255) << shift))
                response = True
            changed.set()
    finally:
        gate.cancel()
