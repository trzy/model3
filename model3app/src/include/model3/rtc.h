#ifndef INCLUDED_MODEL3_RTC_H
#define INCLUDED_MODEL3_RTC_H

#include <stdint.h>

struct RTCTime
{
  uint8_t year;
  uint8_t month;
  uint8_t day;
  uint8_t day_of_week;
  uint8_t hour;
  uint8_t minute;
  uint8_t second;
  uint8_t pm;
};

extern struct RTCTime rtc_get_time(void);
extern void rtc_init(void);

#endif  // INCLUDED_MODEL3_RTC_H
