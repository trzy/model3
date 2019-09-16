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
#include <string.h>

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

static void trigger_real3d()
{
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

static void measure_frame_rate(void)
{
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
  while (1)
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
      tilegen_printf_at(2, 44, "VBL: %1.3f Hz", fps);
      tilegen_printf_at(2, 45, "CPU: %1.3f MHz", mhz);
      tilegen_printf_at(2, 46, "%d/%02d/%02d %02d:%02d:%02d", t.month, t.day, t.year, t.hour, t.minute, t.second);
      tb0 = tb;
    }
    
    // After each occurrance of IRQ 2, refresh IRQ stats
    if (n != s_irq_count[1])
    {
      n = s_irq_count[1];
      for (int i = 0; i < 8; i++)
      {
        // Compute running average of time delta relative to IRQ2:
        // avg' = ((n-1) * avg + sample) / n
        avg_delta[i] = ((n - 1) * avg_delta[i] + s_irq2_delta[i]) / n;
        
        // Refresh
        tilegen_clear_line_from(2, 5 + i);
        tilegen_printf_at(2, 5 + i, "IRQ%02x: %04d  %08x %g", 1 << i, s_irq_count[i], s_irq2_delta[i], avg_delta[i]);
      }
    }
  }
}

int main(void)
{
  jtag_init();
  tilegen_init();
  irq_set_callback(irq_callback);
  irq_enable(0x03);
  ppc_set_external_interrupt_enable(1);
  rtc_init();
  led_set_default_sequence();

  tilegen_printf_at(0, 1, "*** MODEL 3 FRAME IRQ TEST ***");
  tilegen_printf_at(0, 2, "  by Bart Trzynadlowski");

  measure_frame_rate();
  return 0;
}
