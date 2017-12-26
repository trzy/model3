#include "model3/timer.h"
#include "model3/ppc.h"

// For now, hard-coded to Step 1.0 value
static const float s_ticks_per_second = 66e6 / 4;

void timer_init()
{
  //TODO: initialize timing constants based on board stepping
}

void timer_start(struct timer *t, float duration)
{
  float ticks = duration * s_ticks_per_second;
  t->start_ticks = ppc_get_tb();
  t->end_ticks = t->start_ticks + (uint64_t) ticks;
}

float timer_seconds_elapsed(const struct timer *t)
{
  int64_t ticks = ppc_get_tb() - (int64_t) t->start_ticks;
  float seconds = (float) ticks / s_ticks_per_second;
  return seconds;
}

float timer_seconds_remaining(const struct timer *t)
{
  int64_t ticks = (int64_t) t->end_ticks - (int64_t) ppc_get_tb();
  float seconds = (float) ticks / s_ticks_per_second;
  return seconds;
}

bool timer_expired(const struct timer *t)
{
  return ppc_get_tb() >= t->end_ticks;
}
