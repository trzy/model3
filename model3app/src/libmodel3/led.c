/*
 * Register 0xf010001c:
 *
 *     7     6     5     4     3     2     1     0
 *  +-----+-----+-----+-----+-----+-----+-----+-----+
 *  | LED7| LED8| LED9|LED10|LED11|LED12|LED13|LED14|
 *  +-----+-----+-----+-----+-----+-----+-----+-----+
 *
 *  LED7-14: 0 to turn corresponding LED on, 1 to turn off.
 */

#include "model3/led.h"
#include <stdlib.h>
#include <string.h>

static uint8_t s_default_sequence[] = { 0x01, 0x11, 0x31, 0x33, 0x37, 0x77, 0xf7, 0xff, 0xf7, 0x77, 0x37, 0x33, 0x31, 0x11 };
static uint8_t *s_sequence = s_default_sequence;
static size_t s_length = sizeof(s_default_sequence);
static size_t s_step = 0;

void led_set(uint8_t pattern)
{
  volatile uint8_t *led = (uint8_t *) 0xf010001c;
  *led = ~pattern;
}

void led_step(void)
{
  if (s_length)
  {
    led_set(s_sequence[s_step++]);
    s_step %= s_length;
  }
}

void led_set_default_sequence(void)
{
  if (s_sequence != s_default_sequence)
    free(s_sequence);
  s_sequence = s_default_sequence;
  s_length = sizeof(s_default_sequence);
  s_step = 0;
  led_step();
}

void led_set_sequence(const uint8_t *sequence, size_t length)
{
  led_set_default_sequence();
  if (sequence && sequence != s_default_sequence)
  {
    uint8_t *copy = malloc(length);
    if (copy)
    {
      memcpy(copy, sequence, length);
      s_sequence = copy;
      s_length = length;
      s_step = 0;
      led_step();
    }
  }
}
