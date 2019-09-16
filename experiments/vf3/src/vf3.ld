OUTPUT_FORMAT("elf32-powerpc")
OUTPUT_ARCH(powerpc)
ENTRY(_patch_entry)
MEMORY
{
  CROM  (rxa) : ORIGIN = 0xFFE00000, LENGTH = 2M
  RAM   (wx)  : ORIGIN = 0x00000000, LENGTH = 2M
}
SECTIONS
{
  /*.text 0x90000 :*/
  .text 0x60000 :
    AT (0xFFE00000 + 0x110000)
  {
    *(.text)
  } > RAM
  
  _end = . ;

  /* Patch location in CROM */
  __patch_crom_start = LOADADDR(.text);
  __patch_crom_end = __patch_crom_start + (_end - __patch_crom_start);
  
  /* Subroutine that the patch has intercepted and which must be called */
  __patch_replaced_subroutine = 0x3EF0;
}
