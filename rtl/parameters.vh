`define N 32
`define NOP 32'h00000013 // addi x0,x0,0
`define SIM 

// Stage Packet Widths
`define IF_PKT_WIDTH 64

`define ADDR_WIDTH 32
`define INST_WIDTH 32

// Instruction Memory
`define INSTR_MEM_SIZE 20'h1000 //in bytes
`define PC_RESET 32'h80002000

// Data Memory
`define DATA_MEM_SIZE 20'h1000 //in bytes
`define DATA_START 32'h80000000

// Opcodes
`define R  7'b0110011
`define I 7'b0010011
`define LD 7'b0000011
`define S  7'b0100011
`define B 7'b1100011
`define J  7'b1101111
`define JR 7'b1100111
`define U  7'b0110111
`define UPC 7'b0010111
`define CSR 7'b1110011
`define FENCE 7'b0001111

// ALU Control Signals
`define ADD 4'b0000
`define SUB 4'b0001
`define AND 4'b0010
`define OR  4'b0011
`define XOR 4'b0100
`define SRL 4'b0101
`define SLL 4'b0110
`define SRA 4'b0111
`define BUF 4'b1000
`define SLT 4'b1001
`define SLTU 4'b1010
`define EQ 4'b1011
`define GE 4'b1100
`define GEU 4'b1101

//func3 for Load Instructions
`define B 3'b000
`define H 3'b001
`define W 3'b010
`define LBU 3'b100
`define LHU 3'b101

//func3 for Branch Instructions
`define BEQ 3'b000
`define BNE 3'b001
`define BLT 3'b100
`define BGE 3'b101
`define BLTU 3'b110
`define BGEU 3'b111

//func3 for Arithmetic and Logical Instructions
`define ADDI 3'b000 
`define SUBI 3'b000 
`define SLLI 3'b001
`define SLTI 3'b010
`define SLTUI 3'b011
`define XORI 3'b100
`define SRLI 3'b101 
`define SRAI 3'b101 
`define ORI 3'b110
`define ANDI 3'b111

////  CSR-Registers ////
//func3 for CSR Instructions
`define CSRRW 3'b001
`define CSRRS 3'b010 
`define CSRRC 3'b011
`define CSRRWI 3'b101
`define CSRRSI 3'b110
`define CSRRCI 3'b111

//Machine Mode Registers
`define mvendorid 12'hf11
`define marchid 12'hf12
`define mimpid 12'hf13
`define mhartid 12'hf14

`define mstatus 12'h300
`define misa 12'h301
`define medeleg 12'h302
`define mideleg 12'h303
`define mie 12'h304
`define mtvec 12'h305
`define mscratch 12'h340
`define mepc 12'h341
`define mcause 12'h342
`define mtval 12'h343
`define mip 12'h344


////  Exception Codes ////
//// {interrupt,exception code} ////
// The Interrupt bit in the mcause register is set if the trap was caused by an interrupt. The Exception
// Code field contains a code identifying the last exception. riscv-priv-spec(pg no.34) 

// Non-Interrupt Exceptions
`define INSTR_ADDR_MISALIGNED    0   // Instruction address misaligned
`define INSTR_ACCESS_FAULT       1   // Instruction access fault
`define ILLEGAL_INSTR            2   // Illegal instruction
`define BREAKPOINT               3   // Breakpoint
`define LOAD_ADDR_MISALIGNED     4   // Load address misaligned
`define LOAD_ACCESS_FAULT        5   // Load access fault
`define STORE_AMO_ADDR_MISALIGNED 6  // Store/AMO address misaligned
`define STORE_AMO_ACCESS_FAULT   7   // Store/AMO access fault
`define ECALL_FROM_U_MODE        8   // Environment call from U-mode
`define ECALL_FROM_S_MODE        9   // Environment call from S-mode
`define RESERVED_10              10  // Reserved
`define ECALL_FROM_M_MODE        11  // Environment call from M-mode
`define INSTR_PAGE_FAULT         12  // Instruction page fault
`define LOAD_PAGE_FAULT          13  // Load page fault
`define RESERVED_14              14  // Reserved
`define STORE_AMO_PAGE_FAULT     15  // Store/AMO page fault
`define RESERVED_16_OR_HIGHER    16  // Reserved for future use and higher

// Interrupt Exceptions
`define USER_SW_INTR        0  // User software interrupt
`define SUPERVISOR_SW_INTR  1  // Supervisor software interrupt
`define RESERVED_2          2  // Reserved
`define MACHINE_SW_INTR     3  // Machine software interrupt
`define USER_TIMER_INTR     4  // User timer interrupt
`define SUPERVISOR_TIMER_INTR 5 // Supervisor timer interrupt
`define RESERVED_6          6  // Reserved
`define MACHINE_TIMER_INTR  7  // Machine timer interrupt
`define USER_EXT_INTR       8  // User external interrupt
`define SUPERVISOR_EXT_INTR 9  // Supervisor external interrupt
`define RESERVED_10         10 // Reserved
`define MACHINE_EXT_INTR    11 // Machine external interrupt


