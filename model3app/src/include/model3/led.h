#ifndef INCLUDED_MODEL3_LED_H
#define INCLUDED_MODEL3_LED_H

#include <stdint.h>
#include <stdlib.h>

extern void led_set(uint8_t pattern);
extern void led_set_sequence(const uint8_t *sequence, size_t length);
extern void led_set_default_sequence(void);
extern void led_step(void);

#endif  // INCLUDED_MODEL3_LED_H
