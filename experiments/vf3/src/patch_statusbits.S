  .section ".text"

  // VF3 offsets relative to r13
  .set OFFSET_IRQ02_COUNT,        -0x7fcc

  // Our local memory tables
  .set ADDRESS_LIST_END,          0x00200000
  .set ADDRESS_LIST_BEGIN,        (ADDRESS_LIST_END - 8 * 40) // status bit list: 8 bytes per entry (timestamp, status register 0 value)
                                                              // only up to 40 entries allowed
  .set ADDRESS_SLOT_PTR,          (ADDRESS_LIST_BEGIN - 4)    // pointer to next writeable element in IRQ list
  .set ADDRESS_FRAME_MEASURED,    (ADDRESS_SLOT_PTR - 4)      // flag that indicates whether measurement has been performed
  
  // Real3D
  .set ADDRESS_REAL3D_REGS,       0x84000000

  // Tile generator
  .set ADDRESS_LAYER_A,           0xf10f8000
  .set ADDRESS_LAYER_A_ALT,       0xf10fa000
  .set ADDRESS_LAYER_B,           0xf10fc000
  .set ADDRESS_LAYER_B_ALT,       0xf10fe000

  #define NAMETABLE_OFFSET(x, y)  ((y * 64 + x) * 2)

//
// Entry points to injected code
//
  .global _patch_entry
_patch_entry:
  b     hook_print_timings      // _patch_entry + 0: Print once per frame
  b     hook_capture_timestamps // _patch_entry + 4: IRQ handler hook
  b     hook_reset              // _patch_entry + 8: Reset
  
//
// Prints timing data to tile layer. Replaces an existing routine that is
// called at most once per frame.
//
// Inputs:
//  None
//
// Clobbered:
//  cr0
//
hook_print_timings:
  addi  %r1,%r1,-16
  mfspr %r0,%lr
  stw   %r0,0(%r1)

  // First, call the orginal subroutine
  bl    __patch_replaced_subroutine
  
  // If this is the first time we've been called, perform measurement
  lis   %r4,ADDRESS_FRAME_MEASURED@h
  ori   %r4,%r4,ADDRESS_FRAME_MEASURED@l
  lbz   %r4,0(%r4)
  cmpi  0,%r4,0
  bne   .skip_measurement
  bl    perform_measurement
.skip_measurement

  // Next, call ours
  bl    print_list

  lwz   %r0,0(%r1)
  mtlr  %r0
  addi  %r1,%r1,16
  blr
  
//
// Measures frame/ping pong timing. Measures two frames:
//
//  1. Without flush (nothing written to 0x88000000).
//  2. With flush (with a write to 0x88000000 at start).
//
measure_frame:
  mflr  %r0
  addi  %r1,%r1,-64
  stw   %r0,0(%r1)
  stw   %r2,4(%r1)
  stw   %r3,8(%r1)
  stw   %r4,12(%r1)
  stw   %r5,16(%r1)
  stw   %r10,20(%r1)
  stw   %r11,24(%r1)
  stw   %r12,28(%r1)
  stw   %r14,32(%r1)
  stw   %r15,36(%r1)
  stw   %r16,40(%r1)
  stw   %r17,44(%r1)
  
  // Wait several frames
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  
  
  
  // Mark frame as measured so we don't do this again
  lis   %r4,ADDRESS_FRAME_MEASURED@h
  ori   %r4,%r4,ADDRESS_FRAME_MEASURED@l
  li    %r3,1
  stb   %r3,0(%r4)  

  lwz   %r17,44(%r1)
  lwz   %r16,40(%r1)
  lwz   %r15,36(%r1)
  lwz   %r14,32(%r1)
  lwz   %r12,28(%r1)
  lwz   %r11,24(%r1)
  lwz   %r10,20(%r1)
  lwz   %r5,16(%r1)
  lwz   %r4,12(%r1)
  lwz   %r3,8(%r1)
  lwz   %r2,4(%r1)
  lwz   %r0,0(%r1)
  addi  %r1,%r1,64
  mtlr  %r0
  blr

//
// Prints list (once it has filled up) to layer A.
//
// Clobbered:
//  cr0
//
print_list:
  addi  %r1,%r1,-32
  mflr  %r0
  stw   %r0,0(%r1)
  stw   %r2,4(%r1)
  stw   %r3,8(%r1)
  stw   %r4,12(%r1)
  stw   %r5,16(%r1)
  stw   %r6,20(%r1)
  stw   %r7,24(%r1)
  stw   %r8,28(%r1)
  
  // Get list end (current slot pointer)
  lis   %r5,ADDRESS_SLOT_PTR@h
  ori   %r5,%r5,ADDRESS_SLOT_PTR@l
  lwz   %r6,0(%r5)  // r6 = pointer to next slot

  // Print to layer A. Start at (x=4,y=0) and move downwards.
  lis   %r2,ADDRESS_LAYER_A@h
  ori   %r2,%r2,ADDRESS_LAYER_A@l
  li    %r3,NAMETABLE_OFFSET(4,0)
  
  // Iterate list (r5 = list pointer, r6 = list end)
  lis   %r5,ADDRESS_LIST_BEGIN@h
  ori   %r5,%r5,ADDRESS_LIST_BEGIN@l
  
.print_list_loop:
  cmp   0,%r5,%r6   // reached the end?
  beq   .print_list_finished
  
  // Print timestamp in first column
  lwz   %r4,0(%r5)
  bl    print_hex
  
  // Print status register in second column
  lwz   %r4,4(%r5)
  addi  %r3,%r3,(10*2)
  bl    print_hex
  
  // Advance to next row
  addi  %r5,%r5,8
  addi  %r3,%r3,((64-10)*2)
  b     .print_list_loop
  
.print_list_finished:  
.do_not_print:
  lwz   %r8,28(%r1)
  lwz   %r7,24(%r1)
  lwz   %r6,20(%r1)
  lwz   %r5,16(%r1)
  lwz   %r4,12(%r1)
  lwz   %r3,8(%r1)
  lwz   %r2,4(%r1)
  lwz   %r0,0(%r1)
  mtlr  %r0
  addi  %r1,%r1,32
  blr

//
// Prints a 32-bit number as hexadecimal.
//
// Inputs:
//  r2 = Layer base address
//  r3 = Offset in layer of tile (must be 32-bit word aligned)
//  r4 = Value to print
//
// Clobbered:
//  r4
//
print_hex:
  addi  %r1,%r1,-16
  stw   %r2,0(%r1)
  stw   %r3,4(%r1)
  stw   %r5,8(%r1)
  stw   %r6,12(%r1)

  clrrwi  %r3,%r3,2         // enforce alignment by clearing bottom two bits
  add   %r2,%r2,%r3         // r2 = address in tile RAM to write to
  lis   %r6,hex2tile@h      // r6 = hex digit to tile LUT address
  ori   %r6,%r6,hex2tile@l
  li    %r3,8               // r3 = digit counter

.digit_2x_loop:
  // First digit
  rotlwi  %r4,%r4,4         // isolate next digit
  mr    %r5,%r4
  andi. %r5,%r5,0xf         // r5 = digit 0..15
  slwi  %r5,%r5,1
  lhzx  %r5,%r6,%r5         // r5 = tile
  mr    %r0,%r5             // r0 = (0, tile #1)
  slwi  %r0,%r0,16          // r0 = (tile #1, 0)

  // Second digit
  rotlwi  %r4,%r4,4         // isolate next digit
  mr    %r5,%r4
  andi. %r5,%r5,0xf         // r5 = digit 0..15
  slwi  %r5,%r5,1
  lhzx  %r5,%r6,%r5         // r5 = tile
  or    %r0,%r0,%r5         // r0 = (tile #1, tile #2)

  // Store 32-bits (2 tiles) simultaneously
  stwbrx  %r0,0,%r2         // store tiles to RAM (byte swapped) and increment address
  addi  %r2,%r2,4
  addic.  %r3,%r3,-2
  bne   .digit_2x_loop

  lwz   %r6,12(%r1)
  lwz   %r5,8(%r1)
  lwz   %r3,4(%r1)
  lwz   %r2,0(%r1)
  addi  %r1,%r1,16
  blr

//
// The IRQ hook is unused here.
//
// Inputs:
//  r3 = IRQs pending
//  r4 = VF3 program's IRQ mask
//
// Output:
//  r3 = (IRQs pending) & (IRQ mask)
//
//
hook_capture_timestamps:
  and   %r3,%r3,%r4   // we overwrote this instruction with call here
  blr
  
//
// Reads the Real3D status register into r5. All 9 registers are read in
// sequence because all Model 3 games do it this way (it may be required by the
// hardware).
//
// Output:
//  r5 = Real3D status register (register 0 at 0x84000000).
//
// Clobbers:
//  r0, cr0
//
read_real3d_status_into_r5:
  addi  %r1,%r1,-16
  mflr  %r0
  stw   %r0,0(%r1)
  stw   %r4,4(%r1)
  stw   %r6,8(%r1)

  addi  %r1,%r1,-(4*9)  // make room for 9 registers
  mr    %r6,%r1         // address of register 0
  li    %r4,9
  lis   %r5,ADDRESS_REAL3D_REGS@h
  ori   %r5,%r5,ADDRESS_REAL3D_REGS@l
.read_real3d_loop:
  lwbrx %r0,0,%r5       // read register (little endian)
  stw   %r0,0(%r1)      // store
  addi  %r5,%r5,4
  addi  %r1,%r1,4
  addic.  %r4,%r4,-1
  bne   .read_real3d_loop
  
  // Read back register 0 to r5
  lwz   %r5,0(%r6)

  lwz   %r6,8(%r1)
  lwz   %r4,4(%r1)
  lwz   %r0,0(%r1)
  addi  %r1,%r1,16
  mtlr  %r0
  blr

//
// Waits for VBL by spinning on IRQ02 count.
//
// Clobbers:
//  r0, cr0
//
wait_for_vbl:
  addi  %r1,%r1,-16
  mflr  %r0
  stw   %r0,0(%r1)
  stw   %r2,4(%r1)
  
  lbz   %r2,OFFSET_IRQ02_COUNT(%r13)
.vbl_loop:
  lbz   %r0,OFFSET_IRQ02_COUNT(%r13)
  cmp   0,%r0,%r2
  beq   .vbl_loop
  
  lwz   %r2,4(%r1)
  lwz   %r0,0(%r1)
  addi  %r1,%r1,16
  mtlr  %r0
  blr

//
// Inputs:
//  r3 = Timestamp to record
//  r5 = Real3D status register
//
// Clobbered:
//  r0
//
append_list:
  addi  %r1,%r1,-16
  mflr  %r0
  stw   %r0,0(%r1)
  stw   %r5,4(%r1)  // push r5
  stw   %r6,8(%r1)  // push r6
  stw   %r7,12(%r1) // push r7
  
  mr    %r0,%r5     // r0 = Real3D status register
  
  lis   %r6,ADDRESS_LIST_END@h
  ori   %r6,%r6,ADDRESS_LIST_END@l
  
  lis   %r5,ADDRESS_SLOT_PTR@h
  ori   %r5,%r5,ADDRESS_SLOT_PTR@l
  lwz   %r7,0(%r5)  // r7 = pointer to next slot
  
  cmp   0,%r7,%r6
  bgt   .list_full
  beq   .list_full
  
  stw   %r3,0(%r7)  // store timestamp first
  stw   %r0,4(%r7)  // store Real3D status second
  addi  %r7,%r7,8   // advance pointer
  stw   %r7,0(%r5)  // store updated pointer

.list_full:
  lwz   %r7,12(%r1) // pop r7
  lwz   %r6,8(%r1)  // pop r6
  lwz   %r5,4(%r1)  // pop r5
  lwz   %r0,0(%r1)
  addi  %r1,%r1,16
  mtlr  %r0
  blr

//
// Resets the list pointer back to the beginning.
//
// Clobbered:
//  r0
//
reset_list:
  addi  %r1,%r1,-16
  mflr  %r0
  stw   %r0,0(%r1)
  stw   %r3,4(%r1)
  stw   %r4,8(%r1)

  // Reset list pointer
  lis   %r3,ADDRESS_SLOT_PTR@h
  ori   %r3,%r3,ADDRESS_SLOT_PTR@l
  lis   %r4,ADDRESS_LIST_BEGIN@h
  ori   %r4,%r4,ADDRESS_LIST_BEGIN@l
  stw   %r4,0(%r3)
  
  lwz   %r4,8(%r1)
  lwz   %r3,4(%r1)
  lwz   %r0,0(%r1)
  mtlr  %r0
  addi  %r1,%r1,16
  blr

//
// Called once at boot. Initialization can be performed here.
//
// Output:
//  r3 = 0
//
// Clobbered:
//  r0, cr0, xer
//
hook_reset:
  addi  %r1,%r1,-16
  mflr  %r0
  stw   %r0,0(%r1)
  stw   %r4,4(%r1)
  
  bl    reset_list
  
  // Reset frame measure flag
  lis   %r4,ADDRESS_FRAME_MEASURED@h
  ori   %r4,%r4,ADDRESS_FRAME_MEASURED@l
  li    %r3,0
  stb   %r3,0(%r4)  
    
  lwz   %r4,4(%r1)
  lwz   %r0,0(%r1)
  addi  %r1,%r1,16
  mtlr  %r0
  
  li    %r3,0         // we overwrote this instruction with call to here
  blr

//
// Read-Only Data
//

hex2tile:
  .word 0x0030  // 0
  .word 0x0031  // 1
  .word 0x0032  // 2
  .word 0x0033  // 3
  .word 0x0034  // 4
  .word 0x0035  // 5
  .word 0x0036  // 6
  .word 0x0037  // 7
  .word 0x0038  // 8
  .word 0x0039  // 9
  .word 0x0061  // a
  .word 0x0062  // b
  .word 0x0063  // c
  .word 0x0064  // d
  .word 0x0065  // e
  .word 0x0066  // f
  
// 
// Sanity check that we can disassemble to ensure linker script worked
// correctly. This code is unreachable.
//
  lis   %r0,(_patch_entry)@h
  ori   %r0,%r0,(_patch_entry)@l
  b     _patch_entry