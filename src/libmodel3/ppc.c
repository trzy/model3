#include <stdint.h>

uint32_t ppc_get_pvr(void)
{
  uint32_t val;
  asm ("mfpvr %0" : "=r" (val) ::);
  return val;
}

uint32_t ppc_get_hid0(void)
{
  uint32_t val;
  asm ("mfspr %0,1008" : "=r" (val) ::);
  return val;
}

uint32_t ppc_get_hid1(void)
{
  uint32_t val;
  asm ("mfspr %0,1009" : "=r" (val) ::);
  return val;
}

uint32_t ppc_get_msr(void)
{
  uint32_t val;
  asm
  (
    "mfmsr %0;"
    "isync"
    : "=r" (val) 
    :
    :
  );
  return val;
}

void ppc_set_msr(uint32_t msr)
{
  asm
  (
    "mtmsr %0;"
    "isync"
    :
    : "r" (msr)
    :
  );
}

uint32_t ppc_get_dbatu(int n)
{
  uint32_t val;
  switch ((n & 3))
  {
  case 0: asm ("mfspr %0,536" : "=r" (val) ::); break;
  case 1: asm ("mfspr %0,538" : "=r" (val) ::); break;
  case 2: asm ("mfspr %0,540" : "=r" (val) ::); break;
  case 3: asm ("mfspr %0,542" : "=r" (val) ::); break;
  }
  return val;
}
  
uint32_t ppc_get_dbatl(int n)
{
  uint32_t val;
  switch ((n & 3))
  {
  case 0: asm ("mfspr %0,537" : "=r" (val) ::); break;
  case 1: asm ("mfspr %0,539" : "=r" (val) ::); break;
  case 2: asm ("mfspr %0,541" : "=r" (val) ::); break;
  case 3: asm ("mfspr %0,543" : "=r" (val) ::); break;
  }
  return val;
}
  
uint32_t ppc_get_ibatu(int n)
{
  uint32_t val;
  switch ((n & 3))
  {
  case 0: asm ("mfspr %0,528" : "=r" (val) ::); break;
  case 1: asm ("mfspr %0,530" : "=r" (val) ::); break;
  case 2: asm ("mfspr %0,532" : "=r" (val) ::); break;
  case 3: asm ("mfspr %0,534" : "=r" (val) ::); break;
  }
  return val;
}

uint32_t ppc_get_ibatl(int n)
{
  uint32_t val;
  switch ((n & 3))
  {
  case 0: asm ("mfspr %0,529" : "=r" (val) ::); break;
  case 1: asm ("mfspr %0,531" : "=r" (val) ::); break;
  case 2: asm ("mfspr %0,533" : "=r" (val) ::); break;
  case 3: asm ("mfspr %0,535" : "=r" (val) ::); break;
  }
  return val;
}

uint32_t ppc_get_sdr1(void)
{
  uint32_t val;
  asm ("mfsdr1 %0" : "=r" (val) ::);
  return val;
}

uint32_t ppc_get_sr(int n)
{
  uint32_t val;
  asm ("mfsrin %0,%1" : "=r" (val) : "r" (((uint32_t) n) << 28) :);
  return val;
}

void ppc_set_external_interrupt_enable(int on)
{
  uint32_t msr = ppc_get_msr();
  if (on)
    msr |= 0x8000;
  else
    msr &= 0x8000;
  ppc_set_msr(msr);
}
