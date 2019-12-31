/*
 * Runs a series of test. IRQ 02 is enabled.
 */

#include "model3/jtag.h"
#include "model3/tilegen.h"
#include "model3/ppc.h"
#include "model3/irq.h"
#include "model3/rtc.h"
#include "model3/led.h"
#include "model3/dma.h"
#include "model3/timer.h"
#include "model3/utils.h"
#include "model3/real3d.h"
#include <string.h>

static uint32_t s_real3d_stat_packet[9];
static uint32_t s_real3d_stat_packet_dma[9];

// CPU reads should be possible but don't work here for some reason (paging is probably misconfigured in startup.S)
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

// DMA-based reads *do* work because they avoid using the CPU
static uint32_t read_real3d_status_dma()
{
  dma_blocking_copy((uint32_t) s_real3d_stat_packet_dma, (uint32_t *) 0x84000000, 9, false);
  byte_reverse_words(s_real3d_stat_packet_dma, 9);
  return s_real3d_stat_packet_dma[0];
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
  ppc_stwbrx(0xf118000c, 3);      // required to trigger Real3D rendering after flush (exact purpose unknown)
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

#define STR2(x) #x
#define STR(x) STR2(x)

#define INCBIN(name, file) \
    __asm__(".section .data\n" \
            ".global incbin_" STR(name) "_start\n" \
            "/*.type incbin_" STR(name) "_start, @object*/\n" \
            ".balign 8\n" \
            "incbin_" STR(name) "_start:\n" \
            ".incbin \"model3app/src/test/" file "\"\n" \
            \
            ".global incbin_" STR(name) "_end\n" \
            "/*.type incbin_" STR(name) "_end, @object*/\n" \
            ".balign 1\n" \
            "incbin_" STR(name) "_end:\n" \
            ".byte 0\n" \
    ); \
    extern const __attribute__((aligned(8))) void* incbin_ ## name ## _start; \
    extern const void* incbin_ ## name ## _end; \

INCBIN(8c100000, "data_8c100000.bin");
//INCBIN(8c140000, "data_8c140000.bin");
//INCBIN(8c180000, "data_8c180000.bin");
//INCBIN(8c1c0000, "data_8c1c0000.bin");
INCBIN(8e000000, "data_8e000000.bin");
INCBIN(8e000400, "data_8e000400.bin");
INCBIN(8e001400, "data_8e001400.bin");  // modified list to include early termination
INCBIN(94000000, "data_94000000.bin");

static void test_real3d_status_bit(struct timer *test_timer)
{
  // Initialize Real3D device
  tilegen_printf_at(2, 5, "Initializing Real3D... ");
  real3d_init();
  for (int i = 0; i < 3; i++)
  {
    wait_for_vbl();
    real3d_flush();
  }
  tilegen_printf("OK\n\n");
  
  // Print an example of a stat packet
  read_real3d_status();
  read_real3d_status_dma();
  tilegen_printf("  Stat Packet\n");
  tilegen_printf("  -----------\n");
  for (int i = 0; i < 9; i++)
  {
    tilegen_printf("  %d=%08x (CPU)  %08x (DMA)\n", i, s_real3d_stat_packet[i], s_real3d_stat_packet_dma[i]);
  }
  tilegen_printf("\n");
  
  
  // Initialize memory
  tilegen_printf("  Copying to Real3D: 8C ");
  dma_blocking_copy(0x8c100000, (uint32_t *) &incbin_8c100000_start, (uint32_t *) &incbin_8c100000_end - (uint32_t *) &incbin_8c100000_start, false);
  tilegen_printf("8E ");
  for (int i = 0; i < 2; i++)
  {
    dma_blocking_copy(0x8e000000, (uint32_t *) &incbin_8e000000_start, (uint32_t *) &incbin_8e000000_end - (uint32_t *) &incbin_8e000000_start, false);
    dma_blocking_copy(0x8e000400, (uint32_t *) &incbin_8e000400_start, (uint32_t *) &incbin_8e000400_end - (uint32_t *) &incbin_8e000400_start, false);
    dma_blocking_copy(0x8e001400, (uint32_t *) &incbin_8e001400_start, (uint32_t *) &incbin_8e001400_end - (uint32_t *) &incbin_8e001400_start, false);
  }
  tilegen_printf("94");
  dma_blocking_copy(0x94000000, (uint32_t *) &incbin_94000000_start, (uint32_t *) &incbin_94000000_end - (uint32_t *) &incbin_94000000_start, false);
  real3d_flush();
  wait_for_vbl();
  wait_for_vbl();
  wait_for_vbl();
  
  // Conduct frame timing test
  struct timer timeout;
  timer_start(&timeout, 1);
  
  tilegen_printf("\n\n");
  tilegen_printf("  Frame Timing Test\n");
  tilegen_printf("  -----------------\n\n");

  timer_wait_seconds(0.5);
  tilegen_printf("  Beginning test. Hold on to your butts!\n\n");
  
  // Measure the duration of one whole frame
  tilegen_printf("\n  Beginning frame measurement.\n\n");
  wait_for_vbl();
  uint32_t start_of_frame = ppc_get_tbl();
  wait_for_vbl();
  uint32_t end_of_frame = ppc_get_tbl();
  uint32_t frame_duration = end_of_frame - start_of_frame;

  // Issue a flush command
  real3d_flush();

  // Wait for status bit to flip
  uint32_t old_status_bit = read_real3d_status_dma() & 0x02000000;
  uint32_t status_bit;
  do
  {
    status_bit = read_real3d_status_dma() & 0x02000000;
  } while (status_bit == old_status_bit && !timer_expired(&timeout));

  // Measure duration until next VBL
  uint32_t start = ppc_get_tbl();
  wait_for_vbl();
  read_real3d_status_dma();
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
    tilegen_printf("    real3d_status = %08x\n", read_real3d_status_dma());
  }
  else
  {
    tilegen_printf("  Test Results:\n");
    tilegen_printf("    duration         = %d\n", duration);
    tilegen_printf("    frame_duration   = %d\n", frame_duration);
    tilegen_printf("    dec_reload_value = %d\n", dec_reload_value);
  }
  
  while (!poll_timer(test_timer))
  {
    timer_wait_seconds(0.1);
  }
}

static void test_double_buffer(struct timer *test_timer)
{
  const uint32_t addr_8e = 0x8e000100;
  const uint32_t addr_8c = 0x8c040000;
  const uint32_t addr_98 = 0x98000500;
  uint32_t value_8c[2] = { 0, 0 };
  uint32_t value_8e[2] = { 0, 0 };
  uint32_t value_98[2] = { 0, 0 };
  
  wait_for_vbl();
  
  // Copy initial value (0xbeefbabe) to RAM regions
  tilegen_printf_at(2, 5, "Copying initial values to Real3D... ");
  uint32_t value1 = 0xbeefbabe;
  dma_blocking_copy(addr_8c, &value1, 1, false);
  dma_blocking_copy(addr_8e, &value1, 1, false);
  dma_blocking_copy(addr_98, &value1, 1, false);
  tilegen_printf("OK\n");
  
  // Read back (sanity check)
  tilegen_printf("  Reading back values...\n");
  dma_blocking_copy((uint32_t) &value_8c[0], (uint32_t *) addr_8c, 1, false);
  dma_blocking_copy((uint32_t) &value_8e[0], (uint32_t *) addr_8e, 1, false);
  dma_blocking_copy((uint32_t) &value_98[0], (uint32_t *) addr_98, 1, false);
  tilegen_printf("    %08x = %08x\n", addr_8c, value_8c[0]);
  tilegen_printf("    %08x = %08x\n", addr_8e, value_8e[0]);
  tilegen_printf("    %08x = %08x\n", addr_98, value_98[0]);
  
  // Flush
  tilegen_printf("  Flushing... ");
  real3d_flush();
  wait_for_vbl();
  tilegen_printf("OK\n");
  
  // Read back again to see if anything changed
  tilegen_printf("  Reading back values...\n");
  dma_blocking_copy((uint32_t) &value_8c[1], (uint32_t *) addr_8c, 1, false);
  dma_blocking_copy((uint32_t) &value_8e[1], (uint32_t *) addr_8e, 1, false);
  dma_blocking_copy((uint32_t) &value_98[1], (uint32_t *) addr_98, 1, false);
  tilegen_printf("    %08x = %08x\n", addr_8c, value_8c[1]);
  tilegen_printf("    %08x = %08x\n", addr_8e, value_8e[1]);
  tilegen_printf("    %08x = %08x\n", addr_98, value_98[1]);

  while (!poll_timer(test_timer))
  {
    timer_wait_seconds(0.1);
  }
}

static void test_scsi_dma(struct timer *test_timer)
{
  dma_init();
  
  uint32_t src1[16] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
  uint32_t src2[24] = { 11, 12, 13, 14, 15, 16, 17, 18, 19, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124 };
  uint32_t dest[24];
  memset(dest, 0, sizeof(dest));
  
  int result1 = memcmp(src1, dest, sizeof(src1));
  tilegen_printf_at(2, 5, "sanity test = %s\n", result1 == 0 ? "FAILED" : "OK");
  dma_blocking_copy((uint32_t) dest, src1, 16, false);
  int result2 = memcmp(src1, dest, sizeof(src1));
  tilegen_printf("  copy #1     = %s\n", result2 == 0 ? "OK" : "FAILED");
  memset(dest, 0, sizeof(dest));
  dma_blocking_copy((uint32_t) dest, src2, 24, false);
  int result3 = memcmp(src2, dest, sizeof(src2));
  tilegen_printf("  copy #2     = %s\n", result3 == 0 ? "OK" : "FAILED");
  
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
    { "test_refresh_rate",      test_refresh_rate,      10 },
    { "test_scsi_dma",          test_scsi_dma,          10 }, // NOTE: dma_init() called here. May want to move that to start of main().
    { "test_real3d_status_bit", test_real3d_status_bit, 10 },
    { "test_double_buffer",     test_double_buffer,     10 },
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
