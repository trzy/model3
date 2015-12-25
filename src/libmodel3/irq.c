#include "model3/irq.h"

static irq_callback_t s_callbacks[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };
static uint8_t s_irq_mask = 0;

uint8_t irq_get_pending_mask(void)
{
  volatile uint8_t *irq_reg = (uint8_t *) 0xf0100018;
  return *irq_reg;
}

void _irq_hook(void)
{
  uint8_t pending = irq_get_pending_mask();
  for (int i = 0; i < 8; i++)
  {
    if ((pending & 1) && s_callbacks[i])
      s_callbacks[i](i);
    pending >>= 1;
  }
}

static void write_irq_mask_reg(uint8_t mask)
{
  volatile uint8_t *irq_mask_reg = (uint8_t *) 0xf0100014;
  *irq_mask_reg = mask;
}

void irq_enable(int irqnum)
{
  s_irq_mask |= (irqnum < 0) ? 0xff : (1 << irqnum);
  write_irq_mask_reg(s_irq_mask);
}

void irq_disable(int irqnum)
{
  s_irq_mask &= ~((irqnum < 0) ? 0xff : (1 << irqnum));
  write_irq_mask_reg(s_irq_mask);
}

void irq_set_callback(int irqnum, irq_callback_t callback)
{
  if (irqnum < 0)
  {
    for (int i = 0; i < 8; i++)
      s_callbacks[i] = callback;
  }
  else if (irqnum < 8)
    s_callbacks[irqnum] = callback;
}
