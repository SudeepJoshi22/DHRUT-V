# Simple RV32I Assembly Program
# Store values in data memory, load into registers, and perform arithmetic operations

.text
    # Text section

    # Store values in data memory
    la      a0, 8   # Load address of data_memory into a0

    li      t1, 10            # Load immediate value 10 into t1
    sw      t1, 0(a0)         # Store value 10 at the beginning of data_memory

    li      t2, 7             # Load immediate value 7 into t2
    sw      t2, 4(a0)         # Store value 7 at offset 4 in data_memory

    # Load values from data memory into registers
    lw      a1, 0(a0)         # Load the value at the beginning of data_memory into a1
    lw      a2, 4(a0)         # Load the value at offset 4 in data_memory into a2

    # Perform arithmetic operations
    add     a3, a1, a2        # Add the values in a1 and a2, result in a3
    sub     a4, a1, a2        # Subtract the value in a2 from a1, result in a4
    # Halt the program or perform further operations

.data
    # Data section
    data_memory: .space 8      # Allocate 8 bytes for data_memory

