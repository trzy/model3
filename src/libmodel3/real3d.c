#include "model3/dma.h"
#include "model3/ppc.h"

static void setup_pci_regs()
{
  // VF3 performs the following sequence 3 times...
  //TODO: convert to use dma.c's write_pci_config()
  uint32_t pci_config = 0xf0800cf8;
  uint32_t pci_data = 0xf0c00cfc;
  ppc_stwbrx(pci_config, 0x80006804);
  ppc_stwbrx(pci_data, 0xffff0042);
  ppc_stwbrx(pci_config, 0x80006810);
  ppc_stwbrx(pci_data, 0x80000000);
}

static void setup_9c_regs()
{
  // Purpose unknown
  uint32_t unknown_regs[3] = { 0xfc7f0000, 0x04000000, 0x00000200 };
  dma_blocking_copy(0x9c000000, unknown_regs, 3, false);
}

void real3d_flush()
{
  static const uint32_t flush = 0xdeaddead;
  dma_blocking_copy(0x88000000, &flush, 1, false);
}

void real3d_init()
{
  dma_init();
  setup_pci_regs();
  setup_9c_regs();  
}