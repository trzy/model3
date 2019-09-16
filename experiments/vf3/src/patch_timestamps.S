//
// patch_timestamps:
//
// This patch prints out internal VF3 memory locations that record the
// decrementer reload value (related to frame timing and the pingpong bit),
// as well as IRQ04 and IRQ08 timestamps, and the timing delta between them.
//
// We also hook the IRQ handler itself and print most recent IRQ timestamps
// directly.
//
// See patch_script.txt for information on where the patch hooks are inserted
// as well as the VF3 memory map.
//
// Board LED error codes:
//
// If an unrecoverable exception occurs (such as macahine check, etc.), VF3's
// exception handling code jumps back to ROM and repeatedly flashes a code on
// the board LEDs that corresponds to the digit identifying the exception
// vector.
//
  
  .section ".text"

  // VF3 memory locations
  .set OFFSET_DEC_RELOAD,         -0x7fd0     // value used to reload DEC
  .set OFFSET_DELTA_IRQ08_DEC,    -0x7fd8     // time from last IRQ08 to last DEC exception
  .set OFFSET_DELTA_IRQ04_IRQ02,  -0x7fd4     // time from last IRQ04 to last IRQ02
  .set OFFSET_IRQ04_TIMESTAMP,    -0x7fdc     // timestamp of last IRQ04
  .set OFFSET_IRQ04_COUNT,        -0x7fca     // IRQ04 count
  .set OFFSET_IRQ08_TIMESTAMP,    -0x7fe0     // timestamp of last IRQ08
  .set OFFSET_IRQ08_COUNT,        -0x7fcb     // IRQ08 count

  // Our local memory tables
  .set ADDRESS_IRQ_TIMESTAMPS,    0x001fff00  // 8 IRQ timestamps (IRQ01, IRQ02, ..., IRQ80)
  
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

  // Next, call ours
  bl    print_timings

  lwz   %r0,0(%r1)
  mtlr  %r0
  addi  %r1,%r1,16
  blr

//
// Prints timing data to fixed locations on layer A.
//
// Clobbered:
//  cr0
//
print_timings:
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

  lis   %r2,ADDRESS_LAYER_A@h
  ori   %r2,%r2,ADDRESS_LAYER_A@l

  // Print timestamps captured by VF3
  
  li    %r3,NAMETABLE_OFFSET(8,8)
  lwz   %r4,OFFSET_DEC_RELOAD(%r13)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(32,8)
  lwz   %r4,OFFSET_DELTA_IRQ08_DEC(%r13)
  bl    print_hex

  li    %r3,NAMETABLE_OFFSET(8,9)
  lwz   %r4,OFFSET_IRQ04_TIMESTAMP(%r13)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(20,9)
  lbz   %r4,OFFSET_IRQ04_COUNT(%r13)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(32,9)
  lwz   %r4,OFFSET_DELTA_IRQ04_IRQ02(%r13)
  bl    print_hex

  li    %r3,NAMETABLE_OFFSET(8,10)
  lwz   %r4,OFFSET_IRQ08_TIMESTAMP(%r13)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(20,10)
  lbz   %r4,OFFSET_IRQ08_COUNT(%r13)
  bl    print_hex
  
  // Print timestamps we captured directly from IRQ handler

  lis   %r7,ADDRESS_IRQ_TIMESTAMPS@h
  ori   %r7,%r7,ADDRESS_IRQ_TIMESTAMPS@l

  li    %r3,NAMETABLE_OFFSET(8,12)
  lwz   %r4,0(%r7)  // IRQ01
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(8,13)
  lwz   %r4,4(%r7)  // IRQ02
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(8,14)
  lwz   %r4,8(%r7)  // IRQ04
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(8,15)
  lwz   %r4,12(%r7) // IRQ08
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(8,16)
  lwz   %r4,16(%r7) // IRQ10
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(8,17)
  lwz   %r4,20(%r7) // IRQ20
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(8,18)
  lwz   %r4,24(%r7) // IRQ40
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(8,19)
  lwz   %r4,28(%r7) // IRQ80
  bl    print_hex
  
  // Print timestamps relative to IRQ02
  
  lwz   %r8,4(%r7)  // IRQ02
  
  li    %r3,NAMETABLE_OFFSET(20,12)
  lwz   %r4,0(%r7)  // IRQ01
  sub   %r4,%r4,%r8 // IRQ01 - IRQ02
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(20,13)
  lwz   %r4,4(%r7)  // IRQ02
  sub   %r4,%r4,%r8 // IRQ02 - IRQ02
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(20,14)
  lwz   %r4,8(%r7)  // IRQ04
  sub   %r4,%r4,%r8 // IRQ04 - IRQ02
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(20,15)
  lwz   %r4,12(%r7) // IRQ08
  sub   %r4,%r4,%r8 // IRQ08 - IRQ02
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(20,16)
  lwz   %r4,16(%r7) // IRQ10
  sub   %r4,%r4,%r8 // IRQ10 - IRQ02
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(20,17)
  lwz   %r4,20(%r7) // IRQ20
  sub   %r4,%r4,%r8 // IRQ20 - IRQ02
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(20,18)
  lwz   %r4,24(%r7) // IRQ40
  sub   %r4,%r4,%r8 // IRQ40 - IRQ02
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(20,19)
  lwz   %r4,28(%r7) // IRQ80
  sub   %r4,%r4,%r8 // IRQ80 - IRQ02
  bl    print_hex

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
//  r3, r4, r5, r6
//
print_hex:
  addi  %r1,%r1,-16
  stw   %r2,0(%r1)

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

  lwz   %r2,0(%r1)
  addi  %r1,%r1,16
  blr

//
// Captures timestamps for each IRQ. This routine is injected into the external
// interrupt exception handler. The overwritten instruction is replicated at
// the end of this routine.
//
// Inputs:
//  r3 = IRQs pending
//  r4 = VF3 program's IRQ mask
//
// Output:
//  r3 = (IRQs pending) & (IRQ mask)
//
// Clobbered:
//  cr6, cr7
//
hook_capture_timestamps:
  addi  %r1,%r1,-16
  stw   %r3,0(%r1)  // push r3
  stw   %r4,4(%r1)  // push r4
  
  mtcrf 3,%r3       // IRQs pending -> cr6,cr7
  mftbl %r3         // timestamp
  
  lis   %r4,ADDRESS_IRQ_TIMESTAMPS@h
  ori   %r4,%r4,ADDRESS_IRQ_TIMESTAMPS@l
  
  bf	  31,.no_irq01
  stw   %r3,0(%r4)
.no_irq01:
  bf	  30,.no_irq02
  stw   %r3,4(%r4)
.no_irq02:
  bf	  29,.no_irq04
  stw   %r3,8(%r4)
.no_irq04:
  bf	  28,.no_irq08
  stw   %r3,12(%r4)
.no_irq08:
  bf	  27,.no_irq10
  stw   %r3,16(%r4)
.no_irq10:
  bf	  26,.no_irq20
  stw   %r3,20(%r4)
.no_irq20:
  bf	  25,.no_irq40
  stw   %r3,24(%r4)
.no_irq40:
  bf	  24,.no_irq80
  stw   %r3,28(%r4)
.no_irq80:

  lwz   %r4,4(%r1)    // pop r4
  lwz   %r3,0(%r1)    // pop r3
  addi  %r1,%r1,16
  
  and   %r3,%r3,%r4   // we overwrote this instruction with call here
  blr
  
//
// Called once at boot. Initialization can be performed here.
//
// Output:
//  r3 = 0
//
// Clobbered:
//  cr0, xer
//
hook_reset:
  addi  %r1,%r1,-16
  stw   %r4,0(%r1)  // push r4
  stw   %r0,4(%r1)  // push r0
  
  // Clear timestamp table
  lis   %r3,(ADDRESS_IRQ_TIMESTAMPS-4)@h
  ori   %r3,%r3,(ADDRESS_IRQ_TIMESTAMPS-4)@l
  li    %r4,8
  li    %r0,0
.loop:
  stwu  %r0,4(%r3)
  addic.  %r4,%r4,-1
  bne   .loop
  
  lwz   %r0,4(%r1)    // pop r0
  lwz   %r4,0(%r1)    // pop r4
  addi  %r1,%r1,16
  
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