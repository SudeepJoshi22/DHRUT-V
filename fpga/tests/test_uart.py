import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, ReadOnly, Timer


@cocotb.test()
async def uart_contract(dut):
    dut.rst_n.value = 0
    dut.rx.value = 1
    dut.loopback.value = 1
    dut.loader_active.value = 0
    dut.ld_tx_valid.value = 0
    dut.ld_tx_data.value = 0
    dut.ld_rx_ready.value = 0
    dut.bus.m_valid.value = 0
    dut.bus.m_addr.value = 0
    dut.bus.m_wdata.value = 0
    dut.bus.m_wstrb.value = 0
    dut.bus.m_flush.value = 0
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await Timer(35, unit="ns")
    dut.rst_n.value = 1

    async def cycles(count):
        for _ in range(count):
            await FallingEdge(dut.clk)

    async def access(offset, value=None, strobes=15):
        await FallingEdge(dut.clk)
        dut.bus.m_valid.value = 1
        dut.bus.m_addr.value = 0x10000000 + offset
        dut.bus.m_wdata.value = value or 0
        dut.bus.m_wstrb.value = strobes if value is not None else 0
        for _ in range(200):
            await RisingEdge(dut.clk)
            await ReadOnly()
            if dut.bus.s_ready.value:
                result = int(dut.bus.s_rdata.value)
                break
        else:
            raise AssertionError("UART MMIO transaction timed out")
        await RisingEdge(dut.clk)  # consume the registered response
        await FallingEdge(dut.clk)
        dut.bus.m_valid.value = 0
        return result

    assert await access(4) == 0x80000000
    assert await access(12) == 0
    await access(16, 0xA5)  # unmapped addresses must not alias TXDATA
    await cycles(100)
    assert await access(4) == 0x80000000
    # A store without byte lane zero must not start TX.
    await access(0, 0xA5, strobes=2)
    assert await access(8) == 0
    for byte in [0, 255, 0xA5, 0x5A]:
        await access(0, byte)  # consecutive writes exercise busy backpressure
    await cycles(100)
    assert [await access(4) for _ in range(4)] == [0, 255, 0xA5, 0x5A]
    assert await access(4) == 0x80000000

    for byte in range(9):
        await access(0, byte)
    await cycles(100)
    assert (await access(8)) & 4
    assert [await access(4) for _ in range(8)] == list(range(8))
    await access(8, 4)
    assert await access(8) == 0

    # Loader owns TX/RX without using the CPU bus.
    dut.loader_active.value = 1
    await FallingEdge(dut.clk)
    assert dut.ld_tx_ready.value
    dut.ld_tx_data.value = 0xC3
    dut.ld_tx_valid.value = 1
    await FallingEdge(dut.clk)
    dut.ld_tx_valid.value = 0
    await cycles(100)
    assert dut.ld_rx_valid.value and int(dut.ld_rx_data.value) == 0xC3
    dut.ld_rx_ready.value = 1
    await FallingEdge(dut.clk)
    dut.ld_rx_ready.value = 0
    assert not dut.ld_rx_valid.value

    # Bad framing drops the byte, and a short start glitch produces no byte.
    dut.loader_active.value = 0
    dut.loopback.value = 0
    dut.rx.value = 0
    await cycles(1)
    dut.rx.value = 1
    await cycles(100)
    assert await access(4) == 0x80000000
    dut.rx.value = 0
    await cycles(80)  # start + all-zero data + invalid low stop
    dut.rx.value = 1
    await cycles(100)
    assert await access(4) == 0x80000000
