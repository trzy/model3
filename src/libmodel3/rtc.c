/*
 * Based on Seiko Epson RTC-72421/72423 manual...
 */

#include "model3/rtc.h"

static void write_reg(int reg, uint8_t data)
{
  // Take care to preserve low order bytes, which are mapped to battery test
  // logic
  volatile uint32_t *addr = (uint32_t *) (0xf0140000 + 4*reg);
  uint32_t data32 = (*addr & 0x00ffffff) | ((uint32_t) data << 24);
  *addr = data32;
}

static uint8_t read_reg(int reg)
{
  volatile uint32_t *addr = (uint32_t *) (0xf0140000 + 4*reg);
  return *addr >> 24;
}

static void wait_until_not_busy(void)
{
  do
  {
    write_reg(0xf, 0);  // clear hold bit
    write_reg(0xf, 1);  // set hold bit
  } while (read_reg(0xd) & 2);
}

static uint8_t read_until_stable(int reg)
{
  // As per manual: reading registers w/out use of hold bit
  volatile uint8_t val1;
  volatile uint8_t val2;
  do
  {
    val1 = read_reg(reg);
    val2 = read_reg(reg);
  } while (val1 != val2);
  return val1;
}

struct RTCTime rtc_get_time(void)
{
  struct RTCTime t;
  t.second = read_until_stable(0) + 10*read_until_stable(1);
  t.minute = read_until_stable(2) + 10*read_until_stable(3);
  t.hour = read_until_stable(4) + 10*read_until_stable(5);
  t.day = read_until_stable(6) + 10*read_until_stable(7);
  t.month = read_until_stable(8) + 10*read_until_stable(9);
  t.year = read_until_stable(10) + 10*read_until_stable(11);
  t.day_of_week = read_until_stable(12);
  return t;
}

void rtc_init(void)
{
  write_reg(0xf, 0);  // cf register: test=0, 24/12=0, stop=0, reset=0
  write_reg(0xd, 0);  // cd register: 30s adj=0, irq flag=0, busy=0, hold=0
  wait_until_not_busy();
}
