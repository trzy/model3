/*
 * To build CROM image
 *
 *  1. Produce ELF binary: gcc -T m3.ld test.c
 *  2. Convert to ROM image: objcopy a.out crom.bin -O binary --pad-to=0x100000000
 */
 
/*
 * .text sections in RAM:
 *
 * By default, gcc will link in libgcc and various crt objects from 
 * lib/gcc/powerpc-603e-eabi/5.1.0/. libgcc provides __eabi(), which is always
 * called at the beginning of main(), and the crt files provide __init()
 * (called from __eabi()) and various other symbols needed by libgcc.
 *
 * The board support package (BSP) must be provided by us and should perform
 * some basic initialization (clearing all memory, which in turn will ensure 
 * bss is 0, set up the stack pointer, etc.) and then transfer control to
 * main().
 */

OUTPUT_FORMAT("elf32-powerpc")
OUTPUT_ARCH(powerpc)
ENTRY(_reset)
PROVIDE (_stack = 0x200000);
MEMORY
{
  CROM  (rxa) : ORIGIN = 0xFFE00000, LENGTH = 2M
  RAM   (wx)  : ORIGIN = 0x00000000, LENGTH = 2M
}
SECTIONS
{
  .text.crom 0xFFF00100 :
    AT (0xFFF00100)
  {
    *(.text.crom)
  } > CROM
  
  .data.crom :
  {
    *(.data.crom)
  } > CROM
  
  /* NOTE: RAM starts at 0 and _start must be defined to be entry point */
  .text.startup.model3 0x00000000 :
    AT (0xFFE00000)
  {
    __ram_start = .;  /* must be 0x0 */
    *(.text.startup.model3)
  } > RAM
  
  .text ALIGN(8) :
  {
    *(.text.startup)
    *(.text)
  } > RAM
  _etext = .;
  PROVIDE (etext = .);
  
  .sdata2 ALIGN(8) :
  {
    *(.sdata2)
  } > RAM
  
  .sbss2 ALIGN(8) :
  {
    PROVIDE (__sbss2_start = .);
    *(.sbss2)
    PROVIDE (__sbss2_end = .);
  } > RAM
  
  /* Adjust the address for the data segment.  We want to adjust up to
     the same address within the page on the next page up.  It would
     be more correct to do this:
       . = ALIGN(0x50000) + (ALIGN(8) & (0x50000 - 1));
     The current expression does not correctly handle the case of a
     text segment ending precisely at the end of a page; it causes the
     data segment to skip a page.  The above expression does not have
     this problem, but it will currently (2/95) cause BFD to allocate
     a single segment, combining both text and data, for this case.
     This will prevent the text segment from being shared among
     multiple executions of the program; I think that is more
     important than losing a page of the virtual address space (note
     that no actual memory is lost; the page which is skipped can not
     be referenced).  */
  /*. =  ALIGN(8) + 0x50000;*/
  .data ALIGN(8) :
  {
    *(.data)
  } > RAM
  
  .data1   ALIGN(8) : { *(.data1) } > RAM
  .got1		  ALIGN(8) : { *(.got1) } > RAM
  .dynamic	  ALIGN(8) : { *(.dynamic) } > RAM
  /* Put .ctors and .dtors next to the .got2 section, so that the pointers
     get relocated with -mrelocatable. Also put in the .fixup pointers.
     The current compiler no longer needs this, but keep it around for 2.7.2  */
		PROVIDE (_GOT2_START_ = .);
  .got2		  ALIGN(8) :  { *(.got2) } > RAM
		PROVIDE (__CTOR_LIST__ = .);
  .ctors	  ALIGN(8) : { *(.ctors) } > RAM
		PROVIDE (__CTOR_END__ = .);
		PROVIDE (__DTOR_LIST__ = .);
  .dtors	  ALIGN(8) : { *(.dtors) } > RAM
		PROVIDE (__DTOR_END__ = .);
		PROVIDE (_FIXUP_START_ = .);
  .fixup	  ALIGN(8) : { *(.fixup) } > RAM
		PROVIDE (_FIXUP_END_ = .);
		PROVIDE (_GOT2_END_ = .);
		PROVIDE (_GOT_START_ = .);
  .got		  ALIGN(8) : { *(.got) } > RAM
  .got.plt	  ALIGN(8) : { *(.got.plt) } > RAM
		PROVIDE (_GOT_END_ = .);
  
  /* We want the small data sections together, so single-instruction offsets
     can access them all, and initialized data all before uninitialized, so
     we can shorten the on-disk segment size.  */
  .sdata	  ALIGN(8) : { *(.sdata) } > RAM
  _edata  =  .;
  /*PROVIDE (edata = .);*/
  .sbss      ALIGN(8) :
  {
    PROVIDE (__sbss_start = .);
    *(.sbss)
    *(.scommon)
    PROVIDE (__sbss_end = .);
  } > RAM
  .bss       ALIGN(8) :
  {
   PROVIDE (__bss_start = .);
   *(.dynbss)
   *(.bss)
   /**(COMMON)*/
  } > RAM
  _end = . ;
/*  PROVIDE (end = .);*/

  
  /* Compute addresses in ROM of program to be copied */
  __rom_copy_start = LOADADDR(.text.startup.model3);
  __rom_copy_end = __rom_copy_start + (_end - __ram_start);
}
