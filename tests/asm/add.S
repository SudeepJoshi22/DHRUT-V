    .section .text
    .globl _start

_start:
    addi x1, x0, 5      
    addi x2, x1, 3      
    add  x3, x1, x2     
    addi x1, x0, 5      
    addi x2, x11, 3      
    add  x3, x14, x2     
    addi x1, x0, 5      
    addi x2, x1, 3      
    add  x3, x1, x2     
    addi x1, x10, 5      
    addi x2, x1, 3      
    add  x3, x1, x2     
    addi x1, x11, 5      
    addi x2, x1, 3      
    add  x3, x1, x2     
1:  j 1b               # infinite loop (keep CPU alive)
