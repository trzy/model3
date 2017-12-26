#ifndef INCLUDED_MODEL3_TIMER_H
#define INCLUDED_MODEL3_TIMER_H

#include <stdint.h>
#include <stdbool.h>

struct timer
{
  uint64_t start_ticks;
  uint64_t end_ticks;
};

extern void timer_init();
extern void timer_start(struct timer *t, float duration);
extern float timer_seconds_elapsed(const struct timer *t);
extern float timer_seconds_remaining(const struct timer *t);
extern bool timer_expired(const struct timer *t);

#endif  // INCLUDED_MODEL3_TIMER_H
