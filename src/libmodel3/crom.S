  // Linker script locates this section at 0xfff00100
  .section ".text.crom"
  
  .extern __rom_copy_start
  .extern __rom_copy_end
  .extern _start

  .set ADDR_MPC105, 0xf8fff000
  .set ADDR_SYSREGS, 0xf0100000
  
  .org 0x100-0x100
  .global _reset
_reset:
  lis     %r10,ADDR_MPC105@h
  ori     %r10,%r10,ADDR_MPC105@l
  li      %r3,0x146
  li      %r4,0x04
  sthbrx  %r3,%r4,%r10
  li      %r3,0x00000000
  stb     %r3,0x70(%r10)
  li      %r3,0x00000001
  stb     %r3,0xa0(%r10)
  li      %r3,0x00000027
  stb     %r3,0xba(%r10)
  li      %r3,0x00000000
  stb     %r3,0xbb(%r10)
  li      %r3,0x000000D2
  stb     %r3,0xc0(%r10)
  li      %r3,0x00000000
  stb     %r3,0xc4(%r10)   
  lis     %r3,(mpc105_configuration-4)@h
  ori     %r3,%r3,(mpc105_configuration-4)@l
.init_mpc105:
  lwzu    %r4,0x04(%r3) // fetch register address
  cmpi    cr0,%r4,0
  beq     cr0,.finished_mpc105
  cmpi    cr0,%r4,1
  beq     cr0,.delay
  lwzu    %r5,0x04(%r3) // fetch value
  stwbrx  %r5,0,%r4     // write to MPC105
  b       .init_mpc105   
.delay:
  addi    %r3,%r3,0x04  // no value, skip
  li      %r4,0x00000672
  mftb    %r5           // tbl
  add     %r4,%r4,%r5
.delay_loop:   
  mftb    %r5
  cmp     cr0,%r5,%r4
  blt     cr0,.delay_loop
  b       .init_mpc105
.finished_mpc105:
  mftb    %r3
  andis.  %r3,%r3,0x01000000@h
  beq     cr0,.finished_mpc105
  // Write 0x01 to LED
  lis     %r31,ADDR_SYSREGS@h
  ori     %r31,%r31,ADDR_SYSREGS@l
  li      %r4,0x01
  stb     %r4,0x1c(%r31)
  // Copy program to RAM and jump to start
  lis     %r3,__rom_copy_start@h
  ori     %r3,%r3,__rom_copy_start@l
  lis     %r4,__rom_copy_end@h
  ori     %r4,%r4,__rom_copy_end@l
  xor     %r5,%r5,%r5 // copy to address 0
  subi    %r3,%r3,4   // adjust for pre-increment
  subi    %r5,%r5,4   // adjust for pre-increment
.copy_loop:
  lwzu    %r0,4(%r3)
  stwu    %r0,4(%r5)
  cmp     cr0,%r3,%r4
  blt     .copy_loop
  // Write 0x02 to LED
  li      %r4,0x02
  stb     %r4,0x1c(%r31)
  // Jump to RAM
  lis     %r5,_reset_vector@h
  ori     %r5,%r5,_reset_vector@l
  mtlr    %r5
  blr
  
  .org 0x200-0x100
machine_check_exception_vector:
  b       unrecoverable

  .org 0x300-0x100
data_storage_interrupt_vector:
  b       unrecoverable

  .org 0x400-0x100
instruction_storage_interrupt_vector:
  b       unrecoverable
  
  .org 0x500-0x100
external_interrupt_vector:
  b       unrecoverable

  .org 0x600-0x100
alignment_exception_vector:
  b       unrecoverable

  .org 0x700-0x100
program_exception_vector:
  b       unrecoverable

  .org 0x800-0x100
floating_point_unavailable_exception_vector:
  b       unrecoverable

  .org 0x900-0x100
decrementer_exception_vector:
  b       unrecoverable

  .org 0xa00-0x100
reserved_vector_0a00:
  b       unrecoverable

  .org 0xb00-0x100
reserved_vector_0b00:
  b       unrecoverable

  .org 0xc00-0x100
system_call_exception_vector:
  b       unrecoverable

  .org 0xd00-0x100
trace_exception_vector:
  b       unrecoverable

  .org 0xe00-0x100
reserved_vector_0e00:
  b       unrecoverable

  .org 0xf00-0x100
reserved_vector_0f00:
  b       unrecoverable

  .org 0x1000-0x100
instruction_translation_miss_exception_vector:
  b       unrecoverable

  .org 0x1100-0x100
data_load_translation_miss_exception_vector:
  b       unrecoverable

  .org 0x1200-0x100
data_store_translation_miss_exception_vector:
  b       unrecoverable

  .org 0x1300-0x100
instruction_address_breakpoint_exception_vector:
  b       unrecoverable

  .org 0x1400-0x100
system_management_interrupt_vector:
  b       unrecoverable
  
// Blinks the LEDs indefinitely
unrecoverable:
  mfspr   %r3,1008          // hid0
  andi.   %r3,%r3,0x3fff    // disable instruction and data caching
  isync
  sync
  mtspr   1008,%r3
  isync
  sync
  lis     %r2,ADDR_SYSREGS@h
  ori     %r2,%r2,ADDR_SYSREGS@l
  li      %r3,0xac          // ?
  stb     %r3,0x3c(%r2)     // ?
  li      %r3,0xff          // r3 = 0xff
  xor     %r0,%r0,%r0       // r0 = 0x00
.top:
  stb     %r3,0x1c(%r2)     // LED?
.delay_set:  
  mftbl   %r4
  andis.  %r4,%r4,0x00400000@h
  bne     .delay_set
  stb     %r0,0x1c(%r2)
.delay_clear:
  mftbl   %r4
  andis.  %r4,%r4,0x00400000@h
  beq     .delay_clear
  b       .top

  .section ".data.crom"
mpc105_configuration:
  .long 0xF8FFF080, 0x00000000
  .long 0xF8FFF084, 0x00000000 
  .long 0xF8FFF088, 0x00000000 
  .long 0xF8FFF08C, 0x00000000
  .long 0xF8FFF090, 0x00000001 
  .long 0xF8FFF094, 0x00000000 
  .long 0xF8FFF098, 0x00000000
  .long 0xF8FFF09C, 0x00000000 
  .long 0xF8FFF0A8, 0xFF440C58 
  .long 0xF8FFF0AC, 0x000C060C
  .long 0xF8FFF0F0, 0xF4800000 
  .long 0xF8FFF0F4, 0x00000F82 
  .long 0xF8FFF0F8, 0x88300000
  .long 0xF8FFF0FC, 0x36003228 
  .long 0x00000001, 0x00000000 
  .long 0xF8FFF0F0, 0xF4880000
  .long 0x00000000, 0x00000000
   