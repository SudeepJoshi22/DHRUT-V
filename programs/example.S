# example.S
.text
.globl _start

_start:
    li a0, 1         # File descriptor: STDOUT (stdout)
    la a1, message   # Load the address of the message
    li a2, 13        # Message length
    li a7, 64        # System call number for write
    ecall            # Make the system call

    li a7, 93        # System call number for exit
    li a0, 0         # Exit code
    ecall            # Make the system call

.data
message:
    .asciz "Hello, RV32I!\n"

