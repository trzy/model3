#ifndef INCLUDED_MODEL3_IRQ_H
#define INCLUDED_MODEL3_IRQ_H

#include <stdint.h>

typedef void (*irq_callback_t)(int irqnum);
extern uint8_t irq_get_pending_mask(void);
extern void irq_enable(int irqnum);
extern void irq_disable(int irqnum);
extern void irq_set_callback(int irqnum, irq_callback_t callback);

#endif  // INCLUDED_MODEL3_IRQ_H