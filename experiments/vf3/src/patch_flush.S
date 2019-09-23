//
// patch_flush:
//
// Investigation of Real3D frame timing. Three flushes and measurements of the
// time at which the ping pong bit flips occur are performed, one after
// another.
//
//  1. Wait until VBL (IRQ02), flush, then measure ping pong flip time.
//  2. Wait until VBL, wait additional 8ms, flush, then measure flip time.
//  3. Flush immediately after (2). Measure.
//
// The results indicate that a write to the tile generator (0xf118000c=3) and a
// flush are both required to initiate a ping pong bit flip, which seems to
// occur at a fixed point in the frame: ~11ms after VBL.
//
// Conversion from cycles to milliseconds:
//
//  def ms(cycles):
//    return (cycles/(66e6/4))/(1e-3)
//
// The output of each frame measurement to the screen is:
//
//  timestamp_at_flush  status_reg_before_flush lscycle_reg_before_flush
//                      status_reg_after_flush  lscycle_reg_after_flush
//
//  timestamp_at_flip   status_reg_before_flip  lscycle_reg_before_flip
//                      status_reg_after_flip   lscycle_reg_after_flip
//
// At each timestamp event, the status register and "LS cycle" register (the
// Pro-1000 SDK suggested this counts frames) just prior to and just after the
// event are recorded.
//
// Notes:
//  - If 0xF118000C is not written before flush, ping pong will not occur.
//    Removing the write to this register from real3d_flush will cause
//    the third pingpong flip to fail. The other two are preceded by 
//    wait_for_vbl calls, which include this write.
//

  .section ".text"
  
  // VF3 offsets relative to r13
  .set OFFSET_IRQ02_COUNT,              -0x7fcc

  // Our memory region
  .set ADDRESS_BASE,                    0x001fff00
  .set ADDRESS_FRAME_MEASURED,          ADDRESS_BASE
       
  // Result packet layout
  .set OFFSET_STATUS_FLUSH_PRE,         0
  .set OFFSET_LSCYCLE_FLUSH_PRE,        4
  .set OFFSET_TIMESTAMP_FLUSH,          8
  .set OFFSET_STATUS_FLUSH_POST,        12
  .set OFFSET_LSCYCLE_FLUSH_POST,       16
  .set OFFSET_STATUS_PINGPONG_PRE,      20
  .set OFFSET_LSCYCLE_PINGPONG_PRE,     24
  .set OFFSET_TIMESTAMP_PINGPONG,       28
  .set OFFSET_STATUS_PINGPONG_POST,     32
  .set OFFSET_LSCYCLE_PINGPONG_POST,    36
  .set RESULT_PACKET_SIZE,              40
  
  // Results for each frame
  .set ADDRESS_RESULT_1,                ADDRESS_BASE+4
  .set ADDRESS_RESULT_2,                ADDRESS_RESULT_1+RESULT_PACKET_SIZE
  .set ADDRESS_RESULT_3,                ADDRESS_RESULT_2+RESULT_PACKET_SIZE
  
  // Real3D
  .set ADDRESS_REAL3D_REGS,             0x84000000
  .set ADDRESS_REAL3D_FLUSH,            0x88000000
  
  // Delay in cycles
  .set DELAY_8MS,                       132000  // 8e-3/(1/(66e6/4))

  // Tile generator
  .set ADDRESS_LAYER_A,                 0xf10f8000
  .set ADDRESS_LAYER_A_ALT,             0xf10fa000
  .set ADDRESS_LAYER_B,                 0xf10fc000
  .set ADDRESS_LAYER_B_ALT,             0xf10fe000

  #define NAMETABLE_OFFSET(x, y)        (((y) * 64 + x) * 2)

//
// Entry points to injected code
//
  .global _patch_entry
_patch_entry:
  b     hook_print_frame_timing // _patch_entry + 0: Measure frame timing once and print results
  b     hook_irq_handler        // _patch_entry + 4: IRQ handler hook
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
hook_print_frame_timing:
  addi  %r1,%r1,-16
  mfspr %r0,%lr
  stw   %r0,0(%r1)
  stw   %r4,4(%r1)

  // First, call the orginal subroutine
  bl    __patch_replaced_subroutine
  
  // If this is the first time we've been called, measure frame timing
  lis   %r4,ADDRESS_FRAME_MEASURED@h
  ori   %r4,%r4,ADDRESS_FRAME_MEASURED@l
  lbz   %r4,0(%r4)
  cmpi  0,%r4,0
  bne   .skip_measurement
  bl    perform_measurement
.skip_measurement:
  
  // Print results
  bl    print_results    

  lwz   %r4,4(%r1)
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
print_results:
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

  // Print results -- measurement 1
  
  li    %r3,NAMETABLE_OFFSET(8,8)
  lis   %r4,(ADDRESS_RESULT_1+OFFSET_TIMESTAMP_FLUSH)@h
  ori   %r4,%r4,(ADDRESS_RESULT_1+OFFSET_TIMESTAMP_FLUSH)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,8)
  lis   %r4,(ADDRESS_RESULT_1+OFFSET_STATUS_FLUSH_PRE)@h
  ori   %r4,%r4,(ADDRESS_RESULT_1+OFFSET_STATUS_FLUSH_PRE)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,9)
  lis   %r4,(ADDRESS_RESULT_1+OFFSET_STATUS_FLUSH_POST)@h
  ori   %r4,%r4,(ADDRESS_RESULT_1+OFFSET_STATUS_FLUSH_POST)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,8)
  lis   %r4,(ADDRESS_RESULT_1+OFFSET_LSCYCLE_FLUSH_PRE)@h
  ori   %r4,%r4,(ADDRESS_RESULT_1+OFFSET_LSCYCLE_FLUSH_PRE)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,9)
  lis   %r4,(ADDRESS_RESULT_1+OFFSET_LSCYCLE_FLUSH_POST)@h
  ori   %r4,%r4,(ADDRESS_RESULT_1+OFFSET_LSCYCLE_FLUSH_POST)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(8,11)
  lis   %r4,(ADDRESS_RESULT_1+OFFSET_TIMESTAMP_PINGPONG)@h
  ori   %r4,%r4,(ADDRESS_RESULT_1+OFFSET_TIMESTAMP_PINGPONG)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,11)
  lis   %r4,(ADDRESS_RESULT_1+OFFSET_STATUS_PINGPONG_PRE)@h
  ori   %r4,%r4,(ADDRESS_RESULT_1+OFFSET_STATUS_PINGPONG_PRE)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,12)
  lis   %r4,(ADDRESS_RESULT_1+OFFSET_STATUS_PINGPONG_POST)@h
  ori   %r4,%r4,(ADDRESS_RESULT_1+OFFSET_STATUS_PINGPONG_POST)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,11)
  lis   %r4,(ADDRESS_RESULT_1+OFFSET_LSCYCLE_PINGPONG_PRE)@h
  ori   %r4,%r4,(ADDRESS_RESULT_1+OFFSET_LSCYCLE_PINGPONG_PRE)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,12)
  lis   %r4,(ADDRESS_RESULT_1+OFFSET_LSCYCLE_PINGPONG_POST)@h
  ori   %r4,%r4,(ADDRESS_RESULT_1+OFFSET_LSCYCLE_PINGPONG_POST)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  // Print results -- measurement 2
  
  li    %r3,NAMETABLE_OFFSET(8,8+6)
  lis   %r4,(ADDRESS_RESULT_2+OFFSET_TIMESTAMP_FLUSH)@h
  ori   %r4,%r4,(ADDRESS_RESULT_2+OFFSET_TIMESTAMP_FLUSH)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,8+6)
  lis   %r4,(ADDRESS_RESULT_2+OFFSET_STATUS_FLUSH_PRE)@h
  ori   %r4,%r4,(ADDRESS_RESULT_2+OFFSET_STATUS_FLUSH_PRE)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,9+6)
  lis   %r4,(ADDRESS_RESULT_2+OFFSET_STATUS_FLUSH_POST)@h
  ori   %r4,%r4,(ADDRESS_RESULT_2+OFFSET_STATUS_FLUSH_POST)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,8+6)
  lis   %r4,(ADDRESS_RESULT_2+OFFSET_LSCYCLE_FLUSH_PRE)@h
  ori   %r4,%r4,(ADDRESS_RESULT_2+OFFSET_LSCYCLE_FLUSH_PRE)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,9+6)
  lis   %r4,(ADDRESS_RESULT_2+OFFSET_LSCYCLE_FLUSH_POST)@h
  ori   %r4,%r4,(ADDRESS_RESULT_2+OFFSET_LSCYCLE_FLUSH_POST)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(8,11+6)
  lis   %r4,(ADDRESS_RESULT_2+OFFSET_TIMESTAMP_PINGPONG)@h
  ori   %r4,%r4,(ADDRESS_RESULT_2+OFFSET_TIMESTAMP_PINGPONG)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,11+6)
  lis   %r4,(ADDRESS_RESULT_2+OFFSET_STATUS_PINGPONG_PRE)@h
  ori   %r4,%r4,(ADDRESS_RESULT_2+OFFSET_STATUS_PINGPONG_PRE)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,12+6)
  lis   %r4,(ADDRESS_RESULT_2+OFFSET_STATUS_PINGPONG_POST)@h
  ori   %r4,%r4,(ADDRESS_RESULT_2+OFFSET_STATUS_PINGPONG_POST)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,11+6)
  lis   %r4,(ADDRESS_RESULT_2+OFFSET_LSCYCLE_PINGPONG_PRE)@h
  ori   %r4,%r4,(ADDRESS_RESULT_2+OFFSET_LSCYCLE_PINGPONG_PRE)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,12+6)
  lis   %r4,(ADDRESS_RESULT_2+OFFSET_LSCYCLE_PINGPONG_POST)@h
  ori   %r4,%r4,(ADDRESS_RESULT_2+OFFSET_LSCYCLE_PINGPONG_POST)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  // Print results -- measurement 3
  
  li    %r3,NAMETABLE_OFFSET(8,8+12)
  lis   %r4,(ADDRESS_RESULT_3+OFFSET_TIMESTAMP_FLUSH)@h
  ori   %r4,%r4,(ADDRESS_RESULT_3+OFFSET_TIMESTAMP_FLUSH)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,8+12)
  lis   %r4,(ADDRESS_RESULT_3+OFFSET_STATUS_FLUSH_PRE)@h
  ori   %r4,%r4,(ADDRESS_RESULT_3+OFFSET_STATUS_FLUSH_PRE)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,9+12)
  lis   %r4,(ADDRESS_RESULT_3+OFFSET_STATUS_FLUSH_POST)@h
  ori   %r4,%r4,(ADDRESS_RESULT_3+OFFSET_STATUS_FLUSH_POST)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,8+12)
  lis   %r4,(ADDRESS_RESULT_3+OFFSET_LSCYCLE_FLUSH_PRE)@h
  ori   %r4,%r4,(ADDRESS_RESULT_3+OFFSET_LSCYCLE_FLUSH_PRE)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,9+12)
  lis   %r4,(ADDRESS_RESULT_3+OFFSET_LSCYCLE_FLUSH_POST)@h
  ori   %r4,%r4,(ADDRESS_RESULT_3+OFFSET_LSCYCLE_FLUSH_POST)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(8,11+12)
  lis   %r4,(ADDRESS_RESULT_3+OFFSET_TIMESTAMP_PINGPONG)@h
  ori   %r4,%r4,(ADDRESS_RESULT_3+OFFSET_TIMESTAMP_PINGPONG)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,11+12)
  lis   %r4,(ADDRESS_RESULT_3+OFFSET_STATUS_PINGPONG_PRE)@h
  ori   %r4,%r4,(ADDRESS_RESULT_3+OFFSET_STATUS_PINGPONG_PRE)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,12+12)
  lis   %r4,(ADDRESS_RESULT_3+OFFSET_STATUS_PINGPONG_POST)@h
  ori   %r4,%r4,(ADDRESS_RESULT_3+OFFSET_STATUS_PINGPONG_POST)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,11+12)
  lis   %r4,(ADDRESS_RESULT_3+OFFSET_LSCYCLE_PINGPONG_PRE)@h
  ori   %r4,%r4,(ADDRESS_RESULT_3+OFFSET_LSCYCLE_PINGPONG_PRE)@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,12+12)
  lis   %r4,(ADDRESS_RESULT_3+OFFSET_LSCYCLE_PINGPONG_POST)@h
  ori   %r4,%r4,(ADDRESS_RESULT_3+OFFSET_LSCYCLE_PINGPONG_POST)@l
  lwz   %r4,0(%r4)
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
// Performs a single frame measurement. Performs a flush and then measures the
// time taken until the ping pong bit flips.
//
// Output:
//  r22 = LS cycle register, just before flush issued
//  r23 = LS cycle register, just after flush issued
//  r24 = LS cycle register, just before pingpong flipped
//  r25 = LS cycle register, just after pingpong flipped
//  r26 = Status register, just before flush issued
//  r27 = Timestamp of flush
//  r28 = Status register, just after flush issued
//  r29 = Status register, just before pingpong flipped
//  r30 = Timestamp when pingpong flipped
//  r31 = Status register, just after pingpong flipped
//
// Clobbers:
//    r0
//
perform_single_measurement:
  mflr  %r0
  addi  %r1,%r1,-16
  stw   %r0,0(%r1)
  
  // Flush
  bl    read_pingpong_and_status_and_lscycle_r3_r5_r6
  mr    %r26,%r5  // status register, just prior to flush
  mr    %r22,%r6  // ls cycle, just prior to flush
  mr    %r4,%r3   // ping pong bit old value
  bl    real3d_flush
  mftbl %r27      // timestamp of flush
  bl    read_pingpong_and_status_and_lscycle_r3_r5_r6
  mr    %r28,%r5  // status register, just after flush
  mr    %r23,%r6  // ls cycle, just after flush
  
.wait_for_flip:
  mr    %r29,%r5  // status register, just before flip
  mr    %r24,%r6  // ls cycle, just before flip
  bl    read_pingpong_and_status_and_lscycle_r3_r5_r6
  cmp   0,%r3,%r4 // did ping pong bit change?
  beq   .wait_for_flip
  mftbl %r30      // timestamp of flip
  mr    %r31,%r5  // status register, just after flip
  mr    %r25,%r6  // ls cycle, just after flip

  lwz   %r0,0(%r1)
  addi  %r1,%r1,16
  mtlr  %r0
  blr
  
//
// Stores the results of a single frame measurement into a structure in memory.
//
// Input:
//  r3  = Result packet base address.
//  r22 = LS cycle register, just before flush issued
//  r23 = LS cycle register, just after flush issued
//  r24 = LS cycle register, just before pingpong flipped
//  r25 = LS cycle register, just after pingpong flipped
//  r26 = Status register, just before flush issued
//  r27 = Timestamp of flush
//  r28 = Status register, just after flush issued
//  r29 = Status register, just before pingpong flipped
//  r30 = Timestamp when pingpong flipped
//  r31 = Status register, just after pingpong flipped
//
// Clobbered:
//  None  
//
store_measurement:
  stw %r26,OFFSET_STATUS_FLUSH_PRE(%r3)
  stw %r22,OFFSET_LSCYCLE_FLUSH_PRE(%r3)
  stw %r27,OFFSET_TIMESTAMP_FLUSH(%r3)
  stw %r28,OFFSET_STATUS_FLUSH_POST(%r3)
  stw %r23,OFFSET_LSCYCLE_FLUSH_POST(%r3)
  stw %r29,OFFSET_STATUS_PINGPONG_PRE(%r3)
  stw %r24,OFFSET_LSCYCLE_PINGPONG_PRE(%r3)
  stw %r30,OFFSET_TIMESTAMP_PINGPONG(%r3)
  stw %r31,OFFSET_STATUS_PINGPONG_POST(%r3)
  stw %r25,OFFSET_LSCYCLE_PINGPONG_POST(%r3)
  blr

//
// Performs 3 frame measurements involving a flush at a different point in the
// frame.
//
// Clobbers:
//  cr0, r0
//
perform_measurement:
  mflr  %r0
  addi  %r1,%r1,-(4*32)
  stw   %r0,0(%r1)
  stmw  %r2,4(%r1)

  //
  // Measurement 1:
  //
  // Immediately after IRQ02, issue flush.
  //
  
  // Wait a couple frames
  bl    wait_for_vbl
  bl    wait_for_vbl

  // Measure
  li    %r3,1
  bl    set_board_leds
  bl    perform_single_measurement

  // Store results
  lis   %r3,ADDRESS_RESULT_1@h
  ori   %r3,%r3,ADDRESS_RESULT_1@l
  bl    store_measurement
  
  // Print immediate
  bl    print_results
  
  //
  // Measurement 2:
  //
  // Wait for part of a frame after IRQ02, issue flush.
  //
  
  li    %r3,3
  bl    set_board_leds
  bl    wait_for_vbl
  lis   %r3,DELAY_8MS@h
  ori   %r3,%r3,DELAY_8MS@l
  bl    delay
  bl    perform_single_measurement
  lis   %r3,ADDRESS_RESULT_2@h
  ori   %r3,%r3,ADDRESS_RESULT_2@l
  bl    store_measurement
  bl    print_results

  //
  // Measurement 3:
  //
  // Perform another measurement immediately.
  //

  li    %r3,2
  bl    set_board_leds
  bl    perform_single_measurement
  lis   %r3,ADDRESS_RESULT_3@h
  ori   %r3,%r3,ADDRESS_RESULT_3@l
  bl    store_measurement
  bl    print_results
  
  // 
  // Finished: Mark frame as measured so we don't do this again
  //
  lis   %r4,ADDRESS_FRAME_MEASURED@h
  ori   %r4,%r4,ADDRESS_FRAME_MEASURED@l
  li    %r3,1
  stb   %r3,0(%r4)  

  lmw   %r2,4(%r1)
  lwz   %r0,0(%r1)
  addi  %r1,%r1,(4*32)
  mtlr  %r0
  blr

//
// Perform a Real3D flush (or what we believe to be a flush :)). Also writes to
// the tile generator (0xF118000C=3), which is required otherwise the flush has
// no effect.
//
// Clobbers:
//  r0
//
real3d_flush:
  addi  %r1,%r1,-(4*32)
  mflr  %r0
  stw   %r0,0(%r1)
  stmw  %r2,4(%r1)
  
  // Unknown tilegen write. Not sure if this is needed... but might be required
  // before issuing a flush? Games write this in their wait_for_vbl routine.
  lis   %r2,0xf118000c@h
  ori   %r2,%r2,0xf118000c@l
  li    %r0,3
  stwbrx  %r0,0,%r2
  
  // Call into VF3's routine for writing 0x88000000 = 0xdeaddead using SCSI DMA
  li    %r3,2
  addi  %r1,%r1,-256
  bla   0x63bf8
  addi  %r1,%r1,256
  
  lmw   %r2,4(%r1)
  lwz   %r0,0(%r1)
  mtlr  %r0
  addi  %r1,%r1,(4*32)
  blr

//
// Reads the Real3D ping pong bit and status register. All 9 registers are read
// in sequence because all Model 3 games do it this way (it may be required by
// the hardware).
//
// Output:
//  r3 = Ping pong bit (1 or 0).
//  r5 = Full status register.
//  r6 = LS cycle register.
//
// Clobbers:
//  r0, cr0
//
read_pingpong_and_status_and_lscycle_r3_r5_r6:
  addi  %r1,%r1,-16
  mflr  %r0
  stw   %r0,0(%r1)
  stw   %r4,4(%r1)
  //stw   %r6,8(%r1)

  addi  %r1,%r1,-(4*10) // make room for 10 registers
  mr    %r6,%r1         // address of register 0
  li    %r4,10
  lis   %r3,ADDRESS_REAL3D_REGS@h
  ori   %r3,%r3,ADDRESS_REAL3D_REGS@l
.read_real3d_loop:
  lwbrx %r0,0,%r3       // read register (little endian)
  stw   %r0,0(%r1)      // store
  addi  %r3,%r3,4
  addi  %r1,%r1,4
  addic.  %r4,%r4,-1
  bne   .read_real3d_loop
  
  // Read back register 0 to r3 and r5
  lwz   %r3,0(%r6)
  mr    %r5,%r3
  
  // Extract ping pong bit
  srwi  %r3,%r3,25
  andi. %r3,%r3,1
  
  // Regsiter 9 (LS cycle) to r6
  lwz   %r6,36(%r6)

  //lwz   %r6,8(%r1)
  lwz   %r4,4(%r1)
  lwz   %r0,0(%r1)
  addi  %r1,%r1,16
  mtlr  %r0
  blr
  
//
// Waits for VBL by spinning on IRQ02 count. After IRQ02, writes 0xF118000C=3,
// which other games have been observed to do.
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
  
  // Unknown purpose
  lis   %r2,0xf118000c@h
  ori   %r2,%r2,0xf118000c@l
  li    %r0,3
  stwbrx  %r0,0,%r2
  
  lwz   %r2,4(%r1)
  lwz   %r0,0(%r1)
  addi  %r1,%r1,16
  mtlr  %r0
  blr

//
// Waits for specified number of cycles.
//
// Inputs:
//  r3 = Number of cycles to wait
//
// Clobbers:
//  cr0
//
delay:
  addi  %r1,%r1,-16
  mflr  %r0
  stw   %r0,0(%r1)
  stw   %r2,4(%r1)
  //stw   %r4,8(%r1)
  
  // r0 = initial time base value
  // r2 = computed expiration time
  mftbl %r0
  add   %r2,%r0,%r3
  
  // If we overflowed, first wait for timer to become less
  cmp   0,%r2,%r0
  bge   .wait_until_expiration_time_reached
.delay_overflow_loop:
  mftbl %r0
  cmp   0,%r0,%r2
  bgt   .delay_overflow_loop
  
  // Expiration time is greater than initial time
.wait_until_expiration_time_reached:
.delay_loop:
  mftbl %r0
  cmp   0,%r0,%r2
  blt   .delay_loop
  
  //lwz   %r4,8(%r1)
  lwz   %r2,4(%r1)
  lwz   %r0,0(%r1)
  addi  %r1,%r1,16
  mtlr  %r0
  blr
  
//
// Sets the board LEDs to the specified pattern.
//
// Inputs:
//  r3 = Pattern.
//
// Clobbers:
//  r0, r3
//
set_board_leds:
  addi  %r1,%r1,-16
  mflr  %r0
  stw   %r0,0(%r1)
  
  // r0 = ~r3
  li    %r0,0
  orc   %r0,%r0,%r3
  
  // Write to LEDs
  lis   %r3,0xf0100000@h
  stb   %r0,0x1c(%r3)
  
  // r3 = ~r0 (restore r3)
  li    %r3,0
  orc   %r3,%r3,%r0

  lwz   %r0,0(%r1)
  addi  %r1,%r1,16
  mtlr  %r0
  blr

//
// Unused here. Replicate instruction that was patched.
//
// Inputs:
//  r3 = IRQs pending
//  r4 = VF3 program's IRQ mask
//
// Output:
//  r3 = (IRQs pending) & (IRQ mask)
//
// Clobbered:
//  None
//
hook_irq_handler:
  and   %r3,%r3,%r4   // we overwrote this instruction with call here
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
  
  // Reset frame measure flag
  lis   %r4,ADDRESS_FRAME_MEASURED@h
  ori   %r4,%r4,ADDRESS_FRAME_MEASURED@l
  li    %r3,0
  stb   %r3,0(%r4)  
  
  // Clear our memory
  lis   %r2,0x00200000@h
  lis   %r3,ADDRESS_BASE@h
  ori   %r3,%r3,ADDRESS_BASE@l
  li    %r0,0
.clear_memory_loop:
  stw   %r0,0(%r3)
  addi  %r3,%r3,4
  cmp   0,%r3,%r2
  bne   .clear_memory_loop
    
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