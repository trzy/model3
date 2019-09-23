//
// patch_pingpong:
//
// Attempts to measure frame timing by looking for the pingpong bit flip.
// Performs two sets of measurements:
//
// 1. Does not write to 0x88000000.
// 2. Writes 0x88000000 = 0xdeaddead, as many games do, using SCSI DMA. 
//    Apparently using DMA is important.
//
// Various values are recorded for each frame, namely when the pingpong bit
// flip occurred (if it happened at all), timestamps for IRQ04 and IRQ08 during
// the frame, and status register values before and after writing to the
// Real3D.
//
// Unfortunately, this test does not appear to have been successful. No bit
// flip was detected in either frame.
//

//
// TODO:
// -----
// - Designate a single register to hold a base address for our variables
//   and then simply use offsets to access variables (e.g., VF3's r13).
//

  .section ".text"
  
  // VF3 offsets relative to r13
  .set OFFSET_IRQ02_COUNT,              -0x7fcc

  // Values obtained during measurement frame 1
  .set ADDRESS_BASE,                    0x001fff00
  .set ADDRESS_FRAME_MEASURED,          ADDRESS_BASE
  .set ADDRESS_FRAME_BEGIN_TIMESTAMP_1, 0x001fff04
  .set ADDRESS_PINGPONG_TIMESTAMP_1,    0x001fff08
  .set ADDRESS_FRAME_END_TIMESTAMP_1,   0x001fff0c
  .set ADDRESS_IRQ04_TIMESTAMP_1,       0x001fff10
  .set ADDRESS_IRQ08_TIMESTAMP_1,       0x001fff14
  
  // Values obtained during measurement frame 2
  .set ADDRESS_FRAME_BEGIN_TIMESTAMP_2, 0x001fff18
  .set ADDRESS_PINGPONG_TIMESTAMP_2,    0x001fff1c
  .set ADDRESS_FRAME_END_TIMESTAMP_2,   0x001fff20
  .set ADDRESS_IRQ04_TIMESTAMP_2,       0x001fff24
  .set ADDRESS_IRQ08_TIMESTAMP_2,       0x001fff28
  .set ADDRESS_STATUS_FRAME_BEGIN_2,    0x001fff34
  .set ADDRESS_STATUS_AFTER_FLUSH_2,    0x001fff3c
  .set ADDRESS_STATUS_BEFORE_FLIP_2,    0x001fff50
  .set ADDRESS_STATUS_AFTER_FLIP_2,     0x001fff54
  .set ADDRESS_STATUS_IRQ04_2,          0x001fff40
  .set ADDRESS_STATUS_IRQ08_2,          0x001fff44
  
  // Continuously sampled values
  .set ADDRESS_IRQ04_TIMESTAMP,         0x001fff2c  // last IRQ04 timestamp
  .set ADDRESS_IRQ08_TIMESTAMP,         0x001fff30  // last IRQ08 timestamp
  .set ADDRESS_STATUS_IRQ04,            0x001fff48  // Real3D status register at last IRQ04
  .set ADDRESS_STATUS_IRQ08,            0x001fff4c  // Real3D status register at last IRQ08
  
  // Real3D
  .set ADDRESS_REAL3D_REGS,             0x84000000
  .set ADDRESS_REAL3D_FLUSH,            0x88000000

  // Tile generator
  .set ADDRESS_LAYER_A,                 0xf10f8000
  .set ADDRESS_LAYER_A_ALT,             0xf10fa000
  .set ADDRESS_LAYER_B,                 0xf10fc000
  .set ADDRESS_LAYER_B_ALT,             0xf10fe000

  #define NAMETABLE_OFFSET(x, y)  ((y * 64 + x) * 2)

//
// Entry points to injected code
//
  .global _patch_entry
_patch_entry:
  b     hook_print_frame_timing // _patch_entry + 0: Measure frame timing once and print results
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
  bne   .skip_measure_frame
  bl    measure_frame
.skip_measure_frame:
  
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

  // Print results -- frame 1
  
  li    %r3,NAMETABLE_OFFSET(8,8)
  lis   %r4,ADDRESS_FRAME_BEGIN_TIMESTAMP_1@h
  ori   %r4,%r4,ADDRESS_FRAME_BEGIN_TIMESTAMP_1@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(8,9)
  lis   %r4,ADDRESS_PINGPONG_TIMESTAMP_1@h
  ori   %r4,%r4,ADDRESS_PINGPONG_TIMESTAMP_1@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(8,10)
  lis   %r4,ADDRESS_FRAME_END_TIMESTAMP_1@h
  ori   %r4,%r4,ADDRESS_FRAME_END_TIMESTAMP_1@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,9)
  lis   %r4,ADDRESS_IRQ04_TIMESTAMP_1@h
  ori   %r4,%r4,ADDRESS_IRQ04_TIMESTAMP_1@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(18,10)
  lis   %r4,ADDRESS_IRQ08_TIMESTAMP_1@h
  ori   %r4,%r4,ADDRESS_IRQ08_TIMESTAMP_1@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  // Print results -- frame 2
  //
  //  time_frame_begin
  //  time_pingpong_flipped   time_irq04    status_at_irq04
  //  time_frame_end          time_irq08    status_at_irq08
  //  
  //                          status_at_frame_begin
  //                          status_after_flush
  //                          status_before_flip
  //                          status_after_flip
  
  li    %r3,NAMETABLE_OFFSET(28,8)
  lis   %r4,ADDRESS_FRAME_BEGIN_TIMESTAMP_2@h
  ori   %r4,%r4,ADDRESS_FRAME_BEGIN_TIMESTAMP_2@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,9)
  lis   %r4,ADDRESS_PINGPONG_TIMESTAMP_2@h
  ori   %r4,%r4,ADDRESS_PINGPONG_TIMESTAMP_2@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(28,10)
  lis   %r4,ADDRESS_FRAME_END_TIMESTAMP_2@h
  ori   %r4,%r4,ADDRESS_FRAME_END_TIMESTAMP_2@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(38,9)
  lis   %r4,ADDRESS_IRQ04_TIMESTAMP_2@h
  ori   %r4,%r4,ADDRESS_IRQ04_TIMESTAMP_2@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(38,10)
  lis   %r4,ADDRESS_IRQ08_TIMESTAMP_2@h
  ori   %r4,%r4,ADDRESS_IRQ08_TIMESTAMP_2@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(48,9)
  lis   %r4,ADDRESS_STATUS_IRQ04_2@h
  ori   %r4,%r4,ADDRESS_STATUS_IRQ04_2@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(48,10)
  lis   %r4,ADDRESS_STATUS_IRQ08_2@h
  ori   %r4,%r4,ADDRESS_STATUS_IRQ08_2@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(38,12)
  lis   %r4,ADDRESS_STATUS_FRAME_BEGIN_2@h
  ori   %r4,%r4,ADDRESS_STATUS_FRAME_BEGIN_2@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(38,13)
  lis   %r4,ADDRESS_STATUS_AFTER_FLUSH_2@h
  ori   %r4,%r4,ADDRESS_STATUS_AFTER_FLUSH_2@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(38,14)
  lis   %r4,ADDRESS_STATUS_BEFORE_FLIP_2@h
  ori   %r4,%r4,ADDRESS_STATUS_BEFORE_FLIP_2@l
  lwz   %r4,0(%r4)
  bl    print_hex
  
  li    %r3,NAMETABLE_OFFSET(38,15)
  lis   %r4,ADDRESS_STATUS_AFTER_FLIP_2@h
  ori   %r4,%r4,ADDRESS_STATUS_AFTER_FLIP_2@l
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
  stw   %r31,48(%r1)
  
  // Wait several frames
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  
  //
  // Frame 1: Do not flush. Measure time within frame at which ping pong flips.
  //
  // Outputs:
  //  r10 = Start of frame timestamp.
  //  r11 = Timestamp of ping pong bit flip (or 0).
  //  r12 = Timestamp of end of frame.
  //
  
  // Record start time and initial ping pong bit
  mftbl %r10
  bl    read_pingpong_and_status_r3_r5
  mr    %r2,%r3                       // r2 = initial ping pong bit (1 or 0)
  lbz   %r4,OFFSET_IRQ02_COUNT(%r13)  // r4 = initial VBL count
  li    %r11,0
  li    %r12,0
  
  // Wait until bit flips or frame ends
  li    %r31,5                        // frame count = 5 (wait up to 5 frames)
.frame1_loop:
  bl    read_pingpong_and_status_r3_r5
  cmp   0,%r3,%r2
  bne   .pingpong_flipped1
  lbz   %r5,OFFSET_IRQ02_COUNT(%r13)
  cmp   0,%r4,%r5
  bne   .frame_ended_without_flip1
  b     .frame1_loop
    
.frame_ended_without_flip1:
  addic.  %r31,%r31,-1              // frame count -= 1
  beq   .finish_frame1              // we've waited enough frames
  lbz   %r4,OFFSET_IRQ02_COUNT(%r13)  // try again
  b     .frame1_loop
  
.pingpong_flipped1:
  mftbl %r11                        // record ping pong flip time
.finish_frame1:
  lbz   %r5,OFFSET_IRQ02_COUNT(%r13)
  cmp   0,%r4,%r5
  beq   .finish_frame1

.frame1_ended:
  mftbl %r12                        // record end of frame
  
  // Sample and store IRQ timestamps
  lis   %r4,ADDRESS_IRQ04_TIMESTAMP@h
  ori   %r4,%r4,ADDRESS_IRQ04_TIMESTAMP@l
  lis   %r3,ADDRESS_IRQ04_TIMESTAMP_1@h
  ori   %r3,%r3,ADDRESS_IRQ04_TIMESTAMP_1@l
  lwz   %r4,0(%r4) 
  stw   %r4,0(%r3)
  lis   %r4,ADDRESS_IRQ08_TIMESTAMP@h
  ori   %r4,%r4,ADDRESS_IRQ08_TIMESTAMP@l
  lis   %r3,ADDRESS_IRQ08_TIMESTAMP_1@h
  ori   %r3,%r3,ADDRESS_IRQ08_TIMESTAMP_1@l
  lwz   %r4,0(%r4) 
  stw   %r4,0(%r3)
  
  // Store results
  lis   %r3,ADDRESS_FRAME_BEGIN_TIMESTAMP_1@h
  ori   %r3,%r3,ADDRESS_FRAME_BEGIN_TIMESTAMP_1@l
  stw   %r10,0(%r3)
  lis   %r3,ADDRESS_PINGPONG_TIMESTAMP_1@h
  ori   %r3,%r3,ADDRESS_PINGPONG_TIMESTAMP_1@l
  stw   %r11,0(%r3)
  lis   %r3,ADDRESS_FRAME_END_TIMESTAMP_1@h
  ori   %r3,%r3,ADDRESS_FRAME_END_TIMESTAMP_1@l
  stw   %r12,0(%r3)
  
  // Wait several frames
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  bl    wait_for_vbl
  
  //
  // Frame 2: Flush, then measure time within frame at which ping pong flips.
  //
  // Outputs:
  //  r10 = Start of frame timestamp.
  //  r11 = Timestamp of ping pong bit flip (or 0).
  //  r12 = Timestamp of end of frame.
  //  r14 = Real3D status at start of frame 
  //  r15 = Real3D status just before ping pong flipped
  //  r16 = Real3D status short time after ping pong flipped
  //  r17 = Real3D status short time after flush
  //
  
  // Record start time and initial ping pong bit
  mftbl %r10
  bl    read_pingpong_and_status_r3_r5
  mr    %r2,%r3                       // r2 = initial ping pong bit (1 or 0)
  lbz   %r4,OFFSET_IRQ02_COUNT(%r13)  // r4 = initial VBL count
  li    %r11,0
  li    %r12,0
  mr    %r14,%r5                      // r14 = initial Real3D status
  li    %r15,0
  li    %r16,0
  
  // Do flush
  bl    real3d_flush
  bl    short_delay
  bl    read_pingpong_and_status_r3_r5
  mr    %r17,%r5                      // r17 = Real3D status after flush

  // Wait until bit flips or frame ends
  li    %r31,5                        // frame count = 5 (wait up to 5 frames)
.frame2_loop:
  bl    read_pingpong_and_status_r3_r5
  cmp   0,%r3,%r2
  bne   .pingpong_flipped2
  mr    %r15,%r5                      // ping pong did not flip, update pre-flip status value
  lbz   %r5,OFFSET_IRQ02_COUNT(%r13)
  cmp   0,%r4,%r5
  bne   .frame_ended_without_flip2
  b     .frame2_loop
    
.frame_ended_without_flip2:
  addic.  %r31,%r31,-1              // frame count -= 1
  beq   .finish_frame2              // we've waited enough frames
  lbz   %r4,OFFSET_IRQ02_COUNT(%r13)  // try again
  b     .frame2_loop
  
.pingpong_flipped2:
  mftbl %r11                        // record ping pong flip time
  bl    short_delay
  bl    read_pingpong_and_status_r3_r5
  mr    %r16,%r5                    // record status short duration after ping pong flip
.finish_frame2:
  lbz   %r5,OFFSET_IRQ02_COUNT(%r13)
  cmp   0,%r4,%r5
  beq   .finish_frame2

.frame2_ended:
  mftbl %r12                        // record end of frame

  // Sample and store IRQ timestamps
  lis   %r4,ADDRESS_IRQ04_TIMESTAMP@h
  ori   %r4,%r4,ADDRESS_IRQ04_TIMESTAMP@l
  lis   %r3,ADDRESS_IRQ04_TIMESTAMP_2@h
  ori   %r3,%r3,ADDRESS_IRQ04_TIMESTAMP_2@l
  lwz   %r4,0(%r4) 
  stw   %r4,0(%r3)
  lis   %r4,ADDRESS_IRQ08_TIMESTAMP@h
  ori   %r4,%r4,ADDRESS_IRQ08_TIMESTAMP@l
  lis   %r3,ADDRESS_IRQ08_TIMESTAMP_2@h
  ori   %r3,%r3,ADDRESS_IRQ08_TIMESTAMP_2@l
  lwz   %r4,0(%r4) 
  stw   %r4,0(%r3)
  
  lis   %r4,ADDRESS_STATUS_IRQ04@h
  ori   %r4,%r4,ADDRESS_STATUS_IRQ04@l
  lis   %r3,ADDRESS_STATUS_IRQ04_2@h
  ori   %r3,%r3,ADDRESS_STATUS_IRQ04_2@l
  lwz   %r4,0(%r4) 
  stw   %r4,0(%r3)
  
  lis   %r4,ADDRESS_STATUS_IRQ08@h
  ori   %r4,%r4,ADDRESS_STATUS_IRQ08@l
  lis   %r3,ADDRESS_STATUS_IRQ08_2@h
  ori   %r3,%r3,ADDRESS_STATUS_IRQ08_2@l
  lwz   %r4,0(%r4) 
  stw   %r4,0(%r3)

  // Store results
  lis   %r3,ADDRESS_FRAME_BEGIN_TIMESTAMP_2@h
  ori   %r3,%r3,ADDRESS_FRAME_BEGIN_TIMESTAMP_2@l
  stw   %r10,0(%r3)
  lis   %r3,ADDRESS_PINGPONG_TIMESTAMP_2@h
  ori   %r3,%r3,ADDRESS_PINGPONG_TIMESTAMP_2@l
  stw   %r11,0(%r3)
  lis   %r3,ADDRESS_FRAME_END_TIMESTAMP_2@h
  ori   %r3,%r3,ADDRESS_FRAME_END_TIMESTAMP_2@l
  stw   %r12,0(%r3)
  
  lis   %r3,ADDRESS_STATUS_FRAME_BEGIN_2@h
  ori   %r3,%r3,ADDRESS_STATUS_FRAME_BEGIN_2@l
  stw   %r14,0(%r3)
  lis   %r3,ADDRESS_STATUS_AFTER_FLUSH_2@h
  ori   %r3,%r3,ADDRESS_STATUS_AFTER_FLUSH_2@l
  stw   %r17,0(%r3)
  lis   %r3,ADDRESS_STATUS_BEFORE_FLIP_2@h
  ori   %r3,%r3,ADDRESS_STATUS_BEFORE_FLIP_2@l
  stw   %r15,0(%r3)
  lis   %r3,ADDRESS_STATUS_AFTER_FLIP_2@h
  ori   %r3,%r3,ADDRESS_STATUS_AFTER_FLIP_2@l
  stw   %r16,0(%r3)
  
  // Mark frame as measured so we don't do this again
  lis   %r4,ADDRESS_FRAME_MEASURED@h
  ori   %r4,%r4,ADDRESS_FRAME_MEASURED@l
  li    %r3,1
  stb   %r3,0(%r4)  

  lwz   %r31,48(%r1)
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
// Write to tilgen register 0x0c, which games seem to do immediately after
// detecting an IRQ02 event (but never in the IRQ handler, indicating this may
// be some sort of frame trigger).
//
// Clobbers:
//  r0
//  
write_mystery_tilegen_register:
  addi  %r1,%r1,-16
  mflr  %r0
  stw   %r0,0(%r1)
  stw   %r2,4(%r1)
  
  lis   %r2,0xf118000c@h
  ori   %r2,%r2,0xf118000c@l
  li    %r0,3
  stwbrx  %r0,0,%r2
  
  lwz   %r2,4(%r1)
  lwz   %r0,0(%r1)
  mtlr  %r0
  addi  %r1,%r1,16
  blr

//
// Perform a Real3D flush (or what we believe to be a flush :)).
//
// Clobbers:
//  r0
//
real3d_flush:
  addi  %r1,%r1,-(4*32)
  mflr  %r0
  stw   %r0,0(%r1)
  stmw  %r2,4(%r1)
  
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
//
// Clobbers:
//  r0, cr0
//
read_pingpong_and_status_r3_r5:
  addi  %r1,%r1,-16
  mflr  %r0
  stw   %r0,0(%r1)
  stw   %r4,4(%r1)
  stw   %r6,8(%r1)

  addi  %r1,%r1,-(4*9)  // make room for 9 registers
  mr    %r6,%r1         // address of register 0
  li    %r4,9
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

  lwz   %r6,8(%r1)
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
// Waits for less than a single scanline (one scanline is ~648 cycles).
//
// Clobbers:
//  cr0
//
short_delay:
  addi  %r1,%r1,-16
  mflr  %r0
  stw   %r0,0(%r1)
  stw   %r2,4(%r1)
  
  // Wait a quarter of a scanline
  mftbl %r2
  addi  %r2,%r2,162
.delay_loop:
  mftbl %r0
  cmp   0,%r0,%r2
  blt   .delay_loop
  
  lwz   %r2,4(%r1)
  lwz   %r0,0(%r1)
  addi  %r1,%r1,16
  mtlr  %r0
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
  addi  %r1,%r1,-32
  mflr  %r0
  stw   %r0,0(%r1)
  stw   %r3,4(%r1)    // push r3
  stw   %r4,8(%r1)    // push r4
  stw   %r5,12(%r1)   // push r5
  stw   %r6,16(%r1)   // push r6
  
  mtcrf 3,%r3         // IRQs pending -> cr6,cr7
  mftbl %r6           // timestamp
  bl    read_pingpong_and_status_r3_r5
  
  bf	  29,.no_irq04
  lis   %r4,ADDRESS_IRQ04_TIMESTAMP@h
  ori   %r4,%r4,ADDRESS_IRQ04_TIMESTAMP@l
  stw   %r6,0(%r4)    // record IRQ04 timestamp
  lis   %r4,ADDRESS_STATUS_IRQ04@h
  ori   %r4,%r4,ADDRESS_STATUS_IRQ04@l
  stw   %r5,0(%r4)    // record Real3D status
.no_irq04:
  bf	  28,.no_irq08
  lis   %r4,ADDRESS_IRQ08_TIMESTAMP@h
  ori   %r4,%r4,ADDRESS_IRQ08_TIMESTAMP@l
  stw   %r6,0(%r4)    // record IRQ08 timestamp
  lis   %r4,ADDRESS_STATUS_IRQ08@h
  ori   %r4,%r4,ADDRESS_STATUS_IRQ08@l
  stw   %r5,0(%r4)    // record Real3D status
.no_irq08:

  lwz   %r6,16(%r1)   // pop r6
  lwz   %r5,12(%r1)   // pop r5
  lwz   %r4,8(%r1)    // pop r4
  lwz   %r3,4(%r1)    // pop r3
  lwz   %r0,0(%r1)
  addi  %r1,%r1,32
  mtlr  %r0
  
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