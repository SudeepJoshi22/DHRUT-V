start:
    li x1, -10
    li x2, 30
    
    beq x1, x2, start
    li x2, -10
    bne x1, x2, start
    li x2, 30
    blt x2, x1, start
    bltu x1, x2, start
    bge x1, x2, start
    bgeu x2, x1, start
