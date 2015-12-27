#ifndef INCLUDED_MODEL3_IRQ_H
#define INCLUDED_MODEL3_IRQ_H

#include <stdint.h>

typedef void (*irq_callback_t)(uint8_t pending);
extern uint8_t irq_get_pending(void);
extern uint8_t irq_enable(uint8_t mask);
extern uint8_t irq_disable(uint8_t mask);
extern void irq_set_callback(irq_callback_t callback);

#endif  // INCLUDED_MODEL3_IRQ_H