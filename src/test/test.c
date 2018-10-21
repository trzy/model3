/*
 * Simple test program. Displays values of some processor-specific registers
 * and MMU registers to verify that the startup code set them up correctly.
 * Enables IRQ 0x02 (which appears to be vblank) and attempts to measure the
 * refresh rate and CPU clock speed.
 */

#include "model3/jtag.h"
#include "model3/tilegen.h"
#include "model3/ppc.h"
#include "model3/irq.h"
#include "model3/rtc.h"
#include "model3/led.h"
#include "model3/timer.h"
#include <string.h>

//TODO: convert this to use write_pci_config and if confirmed to be real3d,
// move into a real3d_init() function
static void setup_pci_devices()
{
  uint32_t pci_config = 0xf0800cf8;
  uint32_t pci_data = 0xf0c00cfc;
  // Real3D
  ppc_stwbrx(pci_config, 0x80006804);
  ppc_stwbrx(pci_data, 0xffff0042);
  ppc_stwbrx(pci_config, 0x80006810);
  ppc_stwbrx(pci_data, 0x80000000);
}

static void setup_unknown_regs()
{
  // Real3D? This is done once by VF3.
  volatile uint32_t *regs_9c = (uint32_t *) 0x9c000000;
  regs_9c[0] = 0xfc7f0000;
  regs_9c[1] = 0x04000000;
  regs_9c[2] = 0x00000200;
}

static uint32_t s_real3d_stat_packet[9];

static uint32_t read_real3d_reg(uint32_t reg_num)
{
  uint32_t addr = 0x84000000 + (reg_num & 0xf) * 4;
  return ppc_lwbrx(addr);
}

static uint32_t read_real3d_status()
{
  for (int i = 0; i < 9; i++)
  {
    s_real3d_stat_packet[i] = read_real3d_reg(i);
  }
  return s_real3d_stat_packet[0];
}

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

static void scsi_init()
{
  const uint32_t lsi53c810a_id = 0x00011000;        // device in high 16 bits, vendor in low 16 bits
  uint32_t device_and_vendor_id = read_pci_config(0, 0xe, 0, 0);
  if (device_and_vendor_id == lsi53c810a_id)
  {
    write_pci_config(0x14, 0xe, 0, 0, s_scsi_base); // set device base address
    write_pci_config(0x0c, 0xe, 0, 0, 0xff00);      // cache line size and latency timer
    write_pci_config(4, 0xe, 0, 0, 6);              // enable bus mastering and memory space
    s_scsi_byte[0x38] = 0xc1;                       // DMODE (DMA Mode) = 0xc1 (16-transfer burst, manual start mode)
    s_scsi_byte[0x39] = s_scsi_byte[0x39] | 0x08;   // DIEN (DMA Interrupt Enable) |= 0x08 (enable single-step interrupt)
  }
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

static void scsi_dma_copy(uint32_t dest_addr, uint32_t *src, uint32_t num_words)
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

static void scsi_blocking_dma_copy(uint32_t dest_addr, uint32_t *src, uint32_t num_words, bool byte_reverse)
{
  if (byte_reverse)
    byte_reverse_words(src, num_words);
  scsi_dma_copy(dest_addr, src, num_words);
  while (s_transfer_pending != 0)
    ;
  if (byte_reverse)
    byte_reverse_words(src, num_words);
}

static int scsi_irq_handler()
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

static void trigger_real3d()
{
  //static uint32_t data = 0x12345678;
  //scsi_blocking_dma_copy(0x88000000, &data, 1, true);
  ppc_stwbrx(0x88000000, 0xdeaddead);
}

static void print_bat(uint32_t batu, uint32_t batl)
{
  uint32_t bepi = batu >> (31 - 14);
  uint32_t bl = (batu >> (31 - 29)) & 0x7ff;
  int vs = !!(batu & 2);
  int vp = !!(batu & 1);
  uint32_t brpn = batl >> (31 - 14);
  uint32_t wimg = (batl >> (31 - 28)) & 0xf;
  uint32_t pp = batl & 3;
  uint32_t size = (bl + 1) * 128 * 1024;
  uint32_t ea_base = bepi << (31 - 14);
  uint32_t ea_limit = ea_base + size - 1;
  uint32_t pa_base = brpn << (31 - 14);
  uint32_t pa_limit = pa_base + size - 1;
  tilegen_printf("%08X-%08X %08X-%08X ", ea_base, ea_limit, pa_base, pa_limit);
  tilegen_printf("%c%c%c%c ", (wimg&8)?'W':'-', (wimg&4)?'I':'-', (wimg&2)?'M':'-', (wimg&1)?'G':'-');
  tilegen_printf("PP=");
  if (pp == 0)
    tilegen_printf("NA");
  else if (pp == 2)
    tilegen_printf("RW");
  else
    tilegen_printf("RO");
  tilegen_printf(" Vs=%d Vp=%d\n", vs, vp);
}

static const char *s_current_test_name = 0;
static const char *s_next_test_name = 0;

static bool poll_timer(struct timer *t)
{
  tilegen_clear_line(45);
  tilegen_clear_line(46);
  tilegen_printf_at(2, 44, "TB: %08x %08x", (uint32_t) (ppc_get_tb() >> 32), (uint32_t) ppc_get_tb() & 0xffffffff);
  if (s_next_test_name != 0)
  {
    tilegen_printf_at(2, 45, "Current: %s, Next: %s", s_current_test_name, s_next_test_name);
    tilegen_printf_at(2, 46, "Next test in %1.1f seconds...", timer_seconds_remaining(t));
  }
  else
  {
    tilegen_printf_at(2, 45, "Current: %s", s_current_test_name);
    tilegen_printf_at(2, 46, "Test ends in %1.1f seconds...", timer_seconds_remaining(t));
  }
  return timer_expired(t);
}

static volatile int s_irq_count[8];
static volatile uint32_t s_irq_time[8];
static volatile int32_t s_irq2_delta[8];

void irq_callback(uint8_t pending)
{
  uint32_t tb = ppc_get_tbl();

  // Record times
  for (int i = 0; i < 8; i++)
  {
    if (pending & (1 << i))
      s_irq_time[i] = tb;
  }

  // Update time delta of all IRQs relative to IRQ2, if IRQ2 happened
  if (pending & 0x2)
  {
    for (int i = 0; i < 8; i++)
    {
      s_irq2_delta[i] = s_irq_time[i] - s_irq_time[1];
    }
  }
  
  // Now safe to update IRQ count (which main loop monitors)
  for (int i = 0; i < 8; i++)
  {
    if (pending & (1 << i))
      ++s_irq_count[i];
  }
  
  // Handle SCSI interrupt
  scsi_irq_handler();

  // Tilegen IRQs must be acked until they clear
  if (pending & 0x0f)
  {
    for (int i = 0; i < 4; i++)
    {
      while (irq_get_pending() & (1 << i))
      {
        tilegen_write_reg(0x10, (1 << i));
      }
    }
  }

  // These clear on their own
  if (pending & 0xb0)
  {
    while (irq_get_pending() & 0xb0)
      ;
  }
}

static void wait_for_vbl()
{
  int old_count = s_irq_count[1]; // IRQ 0x02
  while (s_irq_count[1] == old_count)
    ;
}

static void test_refresh_rate(struct timer *test_timer)
{
  bool quit = false;

  double avg_delta[8];
  memset(avg_delta, 0, sizeof(avg_delta));

  // Wait for second to roll over to begin test
  int prev_second = rtc_get_time().second;
  while (rtc_get_time().second == prev_second)
    ;

  uint32_t tb0 = ppc_get_tbl();
  prev_second = rtc_get_time().second;
  int n0 = s_irq_count[1];
  int n = n0;
  int seconds = 0;
  while (!quit)
  {
    // Whenever the second rolls over, compute refresh rate and CPU frequency
    struct RTCTime t = rtc_get_time();
    if (t.second != prev_second)
    {
      uint32_t tb = ppc_get_tbl();
      led_step();
      ++seconds;
      prev_second = t.second;
      double fps = (float) (n - n0) / seconds;
      
      // Compute CPU clock speed assuming a 1:1 processor/bus clock multiplier.
      // Time base registers tick every 4 bus cycles.
      double mhz = 4.0 * (tb - tb0) / 1e6;
      tilegen_printf_at(2, 5, "VBL: %1.3f Hz", fps);
      tilegen_printf_at(2, 6, "CPU: %1.3f MHz", mhz);
      tilegen_printf_at(2, 7, "%d/%02d/%02d %02d:%02d:%02d", t.month, t.day, t.year, t.hour, t.minute, t.second);
      tb0 = tb;
      
      // Update timer
      quit = poll_timer(test_timer);
    }
    
    // After each occurrance of IRQ 2, refresh IRQ stats
    if (n != s_irq_count[1])
    {
      n = s_irq_count[1];
      for (int i = 0; i < 8; i++)
      {
        // Compute running average of time delta relative to IRQ2:
        // avg' = ((n-1) * avg + sample) / n
        avg_delta[i] = ((n - 1) * avg_delta[i] + s_irq2_delta[i]) / (double) n;
        
        // Refresh
        tilegen_clear_line_from(2, 7 + 2 + i);
        tilegen_printf_at(2, 7 + 2 + i, "IRQ%02x: %04d  %08x %g", 1 << i, s_irq_count[i], s_irq2_delta[i], avg_delta[i]);
      }
    }
  }
}

static void test_real3d_status_bit(struct timer *test_timer)
{
  // Print an example of a stat packet
  read_real3d_status();
  tilegen_printf_at(2, 5, "Stat Packet\n");
  tilegen_printf("  -----------\n");
  for (int i = 0; i < 9; i++)
  {
    tilegen_printf("  %d=%08x\n", i, s_real3d_stat_packet[i]);
  }
  tilegen_printf("\n");
  
  // Conduct frame timing test
  tilegen_printf("  Frame Timing Test\n");
  tilegen_printf("  -----------------\n\n");
  
  struct timer timeout;
  timer_start(&timeout, 1);
  
  //while (!poll_timer(test_timer))
  {
    timer_wait_seconds(0.5);
    tilegen_printf("  Beginning test. Hold on to your butts!\n\n");
    
    // Try writing something to culling RAM
    for (int i = 0; i < 2; i++)
    {
      tilegen_printf("  Writing culling RAM #%d...\n", i + 1);
      ppc_stwbrx(0x8c000000, 0);
      ppc_stwbrx(0x8e000000, 0);
      tilegen_printf("  Flushing...\n");
      trigger_real3d();
      tilegen_printf("  Waiting one frame...\n");
      wait_for_vbl();
    }
    
    tilegen_printf("\n  Beginning frame measurement.\n\n");
    
    // Measure the duration of one whole frame
    wait_for_vbl();
    uint32_t start_of_frame = ppc_get_tbl();
    wait_for_vbl();
    uint32_t end_of_frame = ppc_get_tbl();
    uint32_t frame_duration = end_of_frame - start_of_frame;

    // Issue a flush command
    trigger_real3d();

    // Wait for status bit to flip
    uint32_t old_status_bit = read_real3d_status() & 0x02000000;
    uint32_t status_bit;
    do
    {
      status_bit = read_real3d_status() & 0x02000000;
    } while (status_bit == old_status_bit && !timer_expired(&timeout));

    // Measure duration until next VBL
    uint32_t start = ppc_get_tbl();
    wait_for_vbl();
    read_real3d_status();
    uint32_t end = ppc_get_tbl();
    uint32_t duration = end - start;
    if (duration < 0x20)
      duration = 0x20;

    // Compute the time that the flush and subsequent status bit flip took.
    // Model 3 games use this value to load the DEC register and perform
    // frame timing.
    uint32_t dec_reload_value = frame_duration - duration;
    
    if (timer_expired(&timeout))
    {
      tilegen_printf("  TEST FAILED\n");
      tilegen_printf("    real3d_status = %08x\n", read_real3d_status());
    }
    else
    {
      tilegen_printf("  Test Results:\n");
      tilegen_printf("    duration         = %d\n", duration);
      tilegen_printf("    frame_duration   = %d\n", frame_duration);
      tilegen_printf("    dec_reload_value = %d\n", dec_reload_value);
    }
  }
  
  while (!poll_timer(test_timer))
  {
    timer_wait_seconds(1);
  }
}

static void test_scsi_dma(struct timer *test_timer)
{
  scsi_init();
  
  s_scsi_enable = true;
  
  uint32_t src1[16] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
  uint32_t src2[24] = { 11, 12, 13, 14, 15, 16, 17, 18, 19, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124 };
  uint32_t dest[24];
  memset(dest, 0, sizeof(dest));
  
  int result1 = memcmp(src1, dest, sizeof(src1));
  tilegen_printf_at(2, 5, "sanity test = %s\n", result1 == 0 ? "FAILED" : "OK");
  scsi_blocking_dma_copy((uint32_t) dest, src1, 16, false);
  int result2 = memcmp(src1, dest, sizeof(src1));
  tilegen_printf("  copy #1     = %s\n", result2 == 0 ? "OK" : "FAILED");
  memset(dest, 0, sizeof(dest));
  scsi_blocking_dma_copy((uint32_t) dest, src2, 24, false);
  int result3 = memcmp(src2, dest, sizeof(src2));
  tilegen_printf("  copy #2     = %s\n", result3 == 0 ? "OK" : "FAILED");
  
  s_scsi_enable = false;
  
  while (!poll_timer(test_timer))
  {
    timer_wait_seconds(1);
  }
}

int main(void)
{
  jtag_init();
  tilegen_init();
  irq_set_callback(irq_callback);
  irq_enable(0x02);
  ppc_set_external_interrupt_enable(1);
  rtc_init();
  led_set_default_sequence();
  timer_init();
  
  struct test_function
  {
    const char *name;
    void (*fn)(struct timer *t);
    float duration;
  };

  struct test_function tests[] =
  {
    //{ "test_refresh_rate",      test_refresh_rate,      10 },
    { "test_scsi_dma",          test_scsi_dma,          10 },
    { "test_real3d_status_bit", test_real3d_status_bit, 10 },
    { 0, 0, 0 }
  };
  
  struct timer test_timer;
  for (int i = 0; tests[i].fn != 0; i++)
  {
    tilegen_clrscr();
    tilegen_printf_at(1, 1, "*** MODEL 3 TEST PROGRAM ***");
    tilegen_printf_at(1, 2, "  by Bart Trzynadlowski");
    
    timer_start(&test_timer, tests[i].duration);
    s_current_test_name = tests[i].name;
    s_next_test_name = tests[i+1].name;
    tests[i].fn(&test_timer);
  }
  
  tilegen_clear_line(45);
  tilegen_clear_line(46);
  tilegen_printf_at(2, 46, "All tests completed");

  return 0;
}
