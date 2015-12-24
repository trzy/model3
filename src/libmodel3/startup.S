  .section ".text.startup.model3"
  
  .extern _stack
  .extern __sbss2_start
  .extern __sbss2_end
  .extern __sbss_start
  .extern __sbss_end
  .extern __bss_start
  .extern _end
  .extern main

  .set ADDR_MPC105, 0xf8fff000
  .set ADDR_SYSREGS, 0xf0100000
  .set ADDR_CTRLREGS, 0xf0040000

  .org 0x100
  .global _reset_vector
_reset_vector:
  mfspr   %r3,1008        // hid0
  ori     %r3,%r3,1       // NOOPTI bit -- because why not?
  mtspr   1008,%r3
  isync 
  lis     %r3,0xff440018@h
  addi    %r3,%r3,0xff440018@l
  lis     %r4,(ADDR_MPC105+0xa8)@h
  ori     %r4,%r4,(ADDR_MPC105+0xa8)@l
  stwbrx  %r3,0,%r4
  li      %r3,0x00003002  // msr: fp enable, machine check enable, vector table prefix 0, recoverable interrupt
  mtsrr1  %r3
  lis     %r3,_start@h
  addi    %r3,%r3,_start@l
  mtsrr0  %r3
  rfi

  .org 0x200
machine_check_exception_vector:
  ba      0xfff00200

  .org 0x300
data_storage_interrupt_vector:
  ba      0xfff00300

  .org 0x400
instruction_storage_interrupt_vector:
  ba      0xfff00400
  
  .org 0x500
external_interrupt_vector:
  ba      0xfff00500

  .org 0x600
alignment_exception_vector:
  ba      0xfff00600

  .org 0x700
program_exception_vector:
  ba      0xfff00700

  .org 0x800
floating_point_unavailable_exception_vector:
  ba      0xfff00800

  .org 0x900
decrementer_exception_vector:
  ba     0xfff00900

  .org 0xa00
reserved_vector_0a00:
  ba      0xfff00a00

  .org 0xb00
reserved_vector_0b00:
  ba      0xfff00b00

  .org 0xc00
system_call_exception_vector:
  ba      0xfff00c00

  .org 0xd00
trace_exception_vector:
  ba      0xfff00d00

  .org 0xe00
reserved_vector_0e00:
  ba      0xfff00e00

  .org 0xf00
reserved_vector_0f00:
  ba      0xfff00f00

  .org 0x1000
instruction_translation_miss_exception_vector:
  mfspr   %r3,980         // imiss
  mfsrin  %r2,%r3
  rlwinm  %r1,%r2,8,0,19
  ori     %r1,%r1,0x0112  // set R, M, PP=RW
  mtspr   982,%r1
  mfsrr1  %r2             // rpa
  mtcrf   0x80,%r2
  tlbld   %r3
  rfi

  .org 0x1100
// Simulate a page table search and map physical page 1:1 with effective
// address that caused the miss. RAM and ROM are mapped through BAT registers,
// so we assume this is some sort of non-cached hardware address and set WIMG.
data_load_translation_miss_exception_vector:
  mfspr   %r3,976         // dmiss
  mfsrin  %r2,%r3
  rlwinm  %r1,%r2,8,0,19
  ori     %r1,%r1,0x017a  // set R, WIMG, PP=RW
  mtspr   982,%r1         // rpa
  mfsrr1  %r2
  mtcrf   0x80,%r2
  tlbld   %r3
  rfi

  .org 0x1200
data_store_translation_miss_exception_vector:
  mfspr   %r3,976         // dmiss
  mfsrin  %r2,%r3
  rlwinm  %r1,%r2,8,0,19
  ori     %r1,%r1,0x01fa  // set R, C, WIMG, PP=RW
  mtspr   982,%r1         // rpa
  mfsrr1  %r2
  mtcrf   0x80,%r2
  tlbld   %r3
  rfi

  .org 0x1300
instruction_address_breakpoint_exception_vector:
  ba      0xfff01300

  .org 0x1400
system_management_interrupt_vector:
  ba      0xfff01400

  .type _start,@function
  .global _start
_start:
  lis     %r31,ADDR_SYSREGS@h
  ori     %r31,%r31,ADDR_SYSREGS@l
  li      %r4,0x03
  stb     %r4,0x1c(%r31)  // 0x03 to LED
  xor     %r0,%r0,%r0
  lis     %r1,_stack@h    // stack pointer with dummy frame for _start()
  ori     %r1,%r1,_stack@l
  mr      %r3,%r1
  stwu    %r0,-4(%r1)
  stwu    %r3,-4(%r1)
  bl      setup_mmu
  bl      clear_fpscr
  bl      setup_model3_system_registers
  bl      setup_model3_control_registers
  bl      setup_cache
  lis     %r3,__sbss2_start@h
  ori     %r3,%r3,__sbss2_start@l
  lis     %r4,__sbss2_end@h
  ori     %r4,%r4,__sbss2_end@l
  bl      clear_memory
  lis     %r3,__sbss_start@h
  ori     %r3,%r3,__sbss_start@l
  lis     %r4,__sbss_end@h
  ori     %r4,%r4,__sbss_end@l
  bl      clear_memory
  lis     %r3,__bss_start@h
  ori     %r3,%r3,__bss_start@l
  lis     %r4,_end@h
  ori     %r4,%r4,_end@l
  bl      clear_memory
  li      %r4,0x04
  stb     %r4,0x1c(%r31)  // 0x04 to LED
  bl      main
  // Flash 0xAA/0x55 repeatedly on LED
  lis     %r31,ADDR_SYSREGS@h
  ori     %r31,%r31,ADDR_SYSREGS@l
  li      %r3,0xac          // ?
  stb     %r3,0x3c(%r31)    // ?
  li      %r3,0xaa          // r3 = 0xaa
  li      %r0,0x55          // r0 = 0x55
.infinite_loop:
  stb     %r3,0x1c(%r31)    // LED = 0xaa
.delay_aa:
  mftbl   %r4
  andis.  %r4,%r4,0x00800000@h
  bne     .delay_aa
  stb     %r0,0x1c(%r31)    // LED = 0x55
.delay_55:
  mftbl   %r4
  andis.  %r4,%r4,0x00800000@h
  beq     .delay_55
  b       .infinite_loop
.size _start,.-_start

setup_cache:
  mfspr	  %r3,1008        // hid0
	ori	    %r3,%r3,0x0800  // icfi: instruction cache flash invalidate 
	mtspr	  1008,%r3
	xori	  %r3,%r3,0x0800
	mtspr	  1008,%r3
	ori	    %r3,%r3,0x8000  // ice: instruction cache enable
	isync	
	mtspr	  1008,%r3
	isync	
	mfspr	  %r3,1008
	ori	    %r3,%r3,0x0400  // dcfi: data cache flash invalidate
	mtspr	  1008,%r3
	xori	  %r3,%r3,0x0400
	mtspr	  1008,%r3
	ori	    %r3,%r3,0x4000  // dce: data cache enable
	sync
	mtspr	  1008,%r3
	sync	
	blr

setup_model3_control_registers:
  li      %r3,0x4e
  lis     %r2,ADDR_CTRLREGS@h
  ori     %r2,%r2,ADDR_CTRLREGS@l
  stb     %r3,0x20(%r2)
  li      %r3,0x00000000
  stb     %r3,0x38(%r2)
  blr

setup_model3_system_registers:
  lis     %r2,ADDR_SYSREGS@h
  ori     %r2,%r2,ADDR_SYSREGS@l
  li      %r3,0xff
  stb     %r3,0x1c(%r2)
  stb     %r3,0x0c(%r2)
  li      %r3,0
  stb     %r3,0x04(%r2)
  stb     %r3,0x00(%r2)
  li      %r3,0xff
  stb     %r3,0x08(%r2)
  li      %r3,0xaf
  stb     %r3,0x3c(%r2)
  blr

clear_fpscr:
  li      %r3,0
  stw     %r3,-4(%r1)
  lfs     %f1,-4(%r1)
  mtfsf   0xff,%f1
  blr

setup_mmu:
  addi    %r1,%r1,-16
  mflr    %r0
  stw     %r0,0(%r1)
  isync
  mfmsr   %r3
  ori     %r3,%r3,0x30
  xori    %r3,%r3,0x30  // disable address translation
  mtmsr   %r3
  isync
  bl      setup_bat_regs
  bl      setup_page_translation
  isync
  mfmsr   %r3
  ori     %r3,%r3,0x30  // enable address translation
  mtmsr   %r3
  isync
  lwz     %r0,0(%r1)
  mtlr    %r0
  addi    %r1,%r1,16
  blr

setup_bat_regs:
  isync
  li      %r3,0
  mtspr   528,%r3 // ibat0u
  mtspr   529,%r3 // ibat0l
  mtspr   530,%r3 // ibat1u
  mtspr   531,%r3 // ibat1l
  mtspr   532,%r3 // ibat2u
  mtspr   533,%r3 // ibat2l
  mtspr   534,%r3 // ibat3u
  mtspr   535,%r3 // ibat3l
  mtspr   536,%r3 // dbat0u
  mtspr   537,%r3 // dbat0l
  mtspr   538,%r3 // dbat1u
  mtspr   539,%r3 // dbat1l
  mtspr   540,%r3 // dbat2u
  mtspr   541,%r3 // dbat2l
  mtspr   542,%r3 // dbat3u
  mtspr   543,%r3 // dbat3l
  // ibat0: 00000000-001fffff --M- RO VpVs=11
  // ibat1: ff800000-ffffffff --M- RO VpVs=11
  // ibat2: not set
  // ibat3: not set
  // dbat0: 00000000-001fffff --MG RW VpVs=11
  // dbat1: ff800000-ffffffff --MG RO VpVs=11
  // dbat2: f0000000-f1ffffff -IMG RW VpVs=11
  // dbat3: c0000000-cfffffff -IMG RW VpVs=11
  // Note: VF3 performs some adjustments on WIMG depending on pvr
  lis     %r3,0x00000000
  ori     %r3,%r3,0x0000003f
  mtspr   528,%r3
  lis     %r3,0x00000000
  ori     %r3,%r3,0x00000011
  mtspr   529,%r3
  lis     %r3,0xff800000@h
  ori     %r3,%r3,0x000000ff
  mtspr   530,%r3
  lis     %r3,0xff800000@h
  ori     %r3,%r3,0x00000011
  mtspr   531,%r3
  lis     %r3,0x00000000
  ori     %r3,%r3,0x0000003f
  mtspr   536,%r3
  lis     %r3,0x00000000
  ori     %r3,%r3,0x0000001a
  mtspr   537,%r3
  lis     %r3,0xff800000@h
  ori     %r3,%r3,0x000000ff
  mtspr   538,%r3
  lis     %r3,0xff800000@h
  ori     %r3,%r3,0x00000019
  mtspr   539,%r3
  lis     %r3,0xf0000000@h
  ori     %r3,%r3,0x000003ff
  mtspr   540,%r3
  lis     %r3,0xf0000000@h
  ori     %r3,%r3,0x0000003a
  mtspr   541,%r3

  // 0x90000000-0x9fffffff
  lis     %r3,0x90000000@h
  ori     %r3,%r3,0x00001fff
  mtspr   542,%r3
  lis     %r3,0x90000000@h
  ori     %r3,%r3,0x0000003a
  mtspr   543,%r3
/*
  lis     %r3,0xc0000000@h
  ori     %r3,%r3,0x00001fff
  mtspr   542,%r3
  lis     %r3,0xc0000000@h
  ori     %r3,%r3,0x0000003a
  mtspr   543,%r3
*/
  isync
  blr

// Set up a dummy paging system where no page table actually exists and TLB is
// loaded by exception handlers with pages that map 1:1 back to physical memory
setup_page_translation:
  lis     %r3,0x20ff8000@h  // N=0 (execution allowed)
  ori     %r3,%r3,0x20ff8000@l
  li      %r4,0             // sr0
  mtsrin  %r3,%r4
  lis     %r4,0xf0000000@h  // sr15
  mtsrin  %r3,%r4
  lis     %r3,0x30ff8000@h  // N=1 (no execution)
  ori     %r3,%r3,0x30ff8000@l
  lis     %r4,0x10000000@h  // sr1
  lis     %r5,0xf0000000@h  // sr15
.sr_loop:                   // load sr1..sr14
  mtsrin  %r3,%r4
  addis   %r4,%r4,0x10000000@h
  cmp     cr0,%r4,%r5
  bne     .sr_loop
  lis     %r3,0xff800000@h  // no page table actually exists here
  sync
  mtsdr1  %r3
  isync
  // Invalidate entire TLB using method described in "PowerPC 603e and EM603e
  // RISC Microprocessor Family User's Manual", Sec. 2.3.6.3.3 (pg. 2-44)
  xor     %r3,%r3,%r3
  li      %r4,32
.tlb_loop:  
  tlbie   %r3
  tlbsync
  addi    %r3,%r3,0x1000
  addic.  %r4,%r4,-1
  bne     .tlb_loop
  isync
  blr

// r3: Start address
// r4: End address
clear_memory:
  sub     %r4,%r4,%r3 // number of bytes to clear
  mr      %r5,%r4
  andi.   %r5,%r5,3   // r5: number of bytes
  li      %r6,2
  srw     %r4,%r4,%r6 // r4: number of words
  subi    %r3,%r3,4   // adjust for pre-increment
  xor     %r0,%r0,%r0
.loop32:
  cmpi    cr0,%r4,0
  beq     .do_bytes
  stwu    %r0,4(%r3)
  subi    %r4,%r4,1
  b       .loop32
.do_bytes:
  addi    %r3,%r3,3   // adjust for pre-increment
.loop8:
  cmpi    cr0,%r5,0
  beq     .finished
  stbu    %r0,1(%r3)
  subi    %r5,%r5,1
  b       .loop8
.finished:
  blr
  
