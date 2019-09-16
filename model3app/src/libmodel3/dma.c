#include "model3/dma.h"
#include "model3/ppc.h"
#include "model3/timer.h"

static const uint32_t s_scsi_base = 0xc0000000; // Step 1.0
static volatile uint8_t * const s_scsi_byte = (uint8_t *) 0xc0000000;
static const uint32_t s_scripts_int_instruction = 0x98080000;
static uint32_t *s_scripts_ptr = 0;
static uint32_t s_scripts_buffer[5];
static int s_num_partial_transfers = 0;
static volatile uint8_t s_transfer_pending = 0;
static volatile uint8_t s_scsi_state = 0;
static bool s_scsi_enable = false;

static uint32_t read_pci_config(uint32_t pci_reg, uint32_t pci_device, uint32_t pci_bus, uint32_t pci_function)
{
  uint32_t cmd = 0x80000000;
  cmd |= (pci_reg & 0xfc);
  cmd |= ((pci_device << 11) & 0xf800);
  cmd |= ((pci_bus << 16) & 0x00ff0000);
  cmd |= ((pci_function << 8) & 0x700);
  ppc_stwbrx(0xf0800cf8, cmd);
  return ppc_lwbrx(0xf0c00cfc);
}

static void write_pci_config(uint32_t pci_reg, uint32_t pci_device, uint32_t pci_bus, uint32_t pci_function, uint32_t data)
{
  uint32_t cmd = 0x80000000;
  cmd |= (pci_reg & 0xfc);
  cmd |= ((pci_device << 11) & 0xf800);
  cmd |= ((pci_bus << 16) & 0xff0000);
  cmd |= ((pci_function << 8) & 0x700);
  ppc_stwbrx(0xf0800cf8, cmd);
  ppc_stwbrx(0xf0c00cfc, data);
}

// If interrupt occurred due to INT/INTFLY, handle it and return 0, otherwise
// return DSTAT
static uint8_t get_interrupt_reason()
{
  // This logic is straight from Fighting Vipers 2 and I don't think it's 100%
  // correct...
  uint8_t istat = s_scsi_byte[0x14];  // ISTAT
  if (istat & 0x4)  // INTFLY occurred, SCRIPTS still executing...
  {
    // This logic is suspicious. 53C810 says that the INTFLY bit should be
    // *set* in order to clear it. I don't think the game ever uses INTFLY, and
    // this code was probably never executed.
    istat &= 0xfb;
    s_scsi_byte[0x14] = istat;
  }
  if ((istat & 0x01) == 0)  // DIP (DMA interrupt pending)
    return 0;
  return s_scsi_byte[0x0c]; // return DSTAT (DMA status)
}

static void byte_reverse_words(uint32_t *src, uint32_t num_words)
{
  for (uint32_t i = 0; i < num_words; i++)
  {
    ppc_stwbrx((uint32_t) &src[i], src[i]);
  }
}

int dma_irq_handler()
{
  if (!s_scsi_enable)
    return 0;

  uint8_t istat = s_scsi_byte[0x14];
  
  if (istat & 0x4)
  {
    istat &= 0xfb;
    s_scsi_byte[0x14] = istat;
  }
  
  if ((istat & 1) == 0)
    return 0x200;
    
  uint8_t dstat = s_scsi_byte[0x0c];  // reading this should clear IRQ
  if ((dstat & 0x08) == 0)            // single step interrupt?
    return 0x200;                     // no...
    
  uint32_t dsp = ppc_lwbrx(s_scsi_base + 0x2c);
  s_scripts_ptr += 3;

  if ((uint32_t) s_scripts_ptr != dsp)
    s_num_partial_transfers += 1; // byte
  
  if (ppc_lwbrx((uint32_t) s_scripts_ptr) == s_scripts_int_instruction)
  {
    s_transfer_pending = 0;
    return 0x400;
  }
  
  uint8_t dcntl = s_scsi_byte[0x3b];
  dcntl |= 0x14;
  s_scsi_byte[0x3b] = dcntl;
  
  timer_wait_ticks(0x21);  
  return 0x400;
}

void dma_copy(uint32_t dest_addr, uint32_t *src, uint32_t num_words)
{
  if (!s_scsi_enable)
    return;

  // Wait until pending transfer is complete
  if (s_scsi_state & 0x80)
  {
    while (s_transfer_pending != 0)
      ;
    s_scsi_state &= 0x7f;
  }

  // New transfer started
  s_scsi_state |= 0x80;
 
  // Ack INT instruction
  get_interrupt_reason();
    
  // Assemble SCRIPTS instructions
  s_scripts_buffer[0] = 0xc0000000 + ((num_words * 4) & 0x00fffffc);  // move memory instruction
  s_scripts_buffer[1] = (uint32_t) src;
  s_scripts_buffer[2] = dest_addr;
  s_scripts_buffer[3] = s_scripts_int_instruction;
  s_scripts_buffer[4] = 1;
  byte_reverse_words(s_scripts_buffer, sizeof(s_scripts_buffer) / sizeof(s_scripts_buffer[0]));
  
  // Kick off the transfer
  s_scripts_ptr = s_scripts_buffer;
  ppc_stwbrx(s_scsi_base + 0x2c, (uint32_t) s_scripts_buffer);  // DSP
  s_scsi_state |= 0x40;
  s_transfer_pending = 0xff;
  s_scsi_byte[0x3b] = s_scsi_byte[0x3b] | 0x14; // DCNTL: single step mode
  s_scsi_state &= 0xbf;
}

void dma_blocking_copy(uint32_t dest_addr, uint32_t *src, uint32_t num_words, bool byte_reverse)
{
  if (byte_reverse)
    byte_reverse_words(src, num_words);
  dma_copy(dest_addr, src, num_words);
  while (s_transfer_pending != 0)
    ;
  if (byte_reverse)
    byte_reverse_words(src, num_words);
}

bool dma_init()
{
  if (s_scsi_enable)
    return false; // already enabled
  const uint32_t lsi53c810a_id = 0x00011000;      // device in high 16 bits, vendor in low 16 bits
  uint32_t device_and_vendor_id = read_pci_config(0, 0xe, 0, 0);
  if (device_and_vendor_id != lsi53c810a_id)
    return true;  // error
  write_pci_config(0x14, 0xe, 0, 0, s_scsi_base); // set device base address
  write_pci_config(0x0c, 0xe, 0, 0, 0xff00);      // cache line size and latency timer
  write_pci_config(4, 0xe, 0, 0, 6);              // enable bus mastering and memory space
  s_scsi_byte[0x38] = 0xc1;                       // DMODE (DMA Mode) = 0xc1 (16-transfer burst, manual start mode)
  s_scsi_byte[0x39] = s_scsi_byte[0x39] | 0x08;   // DIEN (DMA Interrupt Enable) |= 0x08 (enable single-step interrupt)
  s_scsi_enable = true;
  return false;   // success
}
