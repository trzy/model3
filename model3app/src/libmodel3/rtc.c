/*
 * RTC registers are mapped alongside some sort of logic used to test battery
 * voltage. Care must be taken to preserve these bits when writing the 4 bits
 * mapped to the RTC.
 *
 * References:
 * -----------
 * - Seiko Epson Real Time Clock Module RTC-72421/72423 Application Manual 
 *   (ETM17E-02)
 */

#include "model3/rtc.h"
#include "model3/ppc.h"

static void write_reg(int reg, uint32_t data)
{
  ppc_stwbrx(0xf0140000 + 4*reg, data);
}

static uint32_t read_reg(int reg)
{
  return ppc_lwbrx(0xf0140000 + 4*reg);
}

static void wait_until_not_busy(void)
{
  //TODO: need to preserve high 24 bits here after each read when writing back
  volatile uint32_t cd = read_reg(0xd) | 1; // set hold bit
  write_reg(0xd, cd);
  while ((cd = read_reg(0xd)) & 2)
  {
    write_reg(0xd, cd & ~1);  // clear hold bit (required to update busy bit)
    write_reg(0xd, cd | 1);   // set hold bit
  }
  write_reg(0xd, cd & ~1);    // clear hold bit so time registers can update
}

static uint8_t read_until_stable(int reg)
{
  // As per manual: reading registers w/out use of hold bit
  volatile uint8_t val1;
  volatile uint8_t val2;
  do
  {
    val1 = read_reg(reg) & 0x0f;
    val2 = read_reg(reg) & 0x0f;
  } while (val1 != val2);
  return val1;
}

struct RTCTime rtc_get_time(void)
{
  struct RTCTime t;
  t.second = read_until_stable(0) + 10*read_until_stable(1);
  t.minute = read_until_stable(2) + 10*read_until_stable(3);
  uint8_t h10 = read_until_stable(5);
  t.hour = read_until_stable(4) + 10*(h10 & 3);
  t.day = read_until_stable(6) + 10*read_until_stable(7);
  t.month = read_until_stable(8) + 10*read_until_stable(9);
  t.year = read_until_stable(10) + 10*read_until_stable(11);
  t.day_of_week = read_until_stable(12);
  t.pm = (h10 >> 2) & 1;
  return t;
}

void rtc_init(void)
{
  uint32_t cf = read_reg(0xf) & 0xffffff00;
  write_reg(0xf, cf); // cf register: test=0, 24/12=0, stop=0, reset=0
  uint32_t cd = read_reg(0xd) & 0xffffff00;
  write_reg(0xd, cd); // cd register: 30s adj=0, irq flag=0, busy=0, hold=0
  wait_until_not_busy();
}
