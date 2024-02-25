reset:
   ORI t2, zero, 0          #     store_addr = 0
   ORI t0, zero, 1          #     cnt = 1
   ORI a2, zero, 10         #     ten = 10
   ORI a0, zero, 0          #     out = 0
loop:
   ADD a0, t0, a0           #  -> out += cnt
   SW a0, 0(t2)             #     store out at store_addr
   ADDI t0, t0, 1           #     cnt++
   ADDI t2, t2, 4           #     store_addr++
   BLT t0, a2, loop         #  ^- branch back if cnt < 10
# Result should be 0x2d.
   LW t1, -4(t2)            #     load the final value
   ADDI a1, zero, 0x2d      #     expected result (0x2d)
   BEQ t1, a1, pass         #     pass if as expected

   # Branch to one of these to report pass/fail to the default testbench.
fail:
   ADD a1, a1, zero         #     nop fail
pass:
   ADD t1, t1, zero         #     nop pass
