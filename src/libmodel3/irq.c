#include "model3/irq.h"
#include "model3/dma.h"

static irq_callback_t s_callback;
static uint8_t s_irq_mask = 0;

uint8_t irq_get_pending(void)
{
  volatile uint8_t *irq_reg = (uint8_t *) 0xf0100018;
  return *irq_reg;
}

void _irq_hook(void)
{
  // Handle SCSI interrupt
  dma_irq_handler();

  // Handle all other interrupts
  if (s_callback)
    s_callback(irq_get_pending());
}

static void write_irq_mask_reg(uint8_t mask)
{
  volatile uint8_t *irq_mask_reg = (uint8_t *) 0xf0100014;
  *irq_mask_reg = mask;
}

uint8_t irq_enable(uint8_t mask)
{
  s_irq_mask |= mask;
  write_irq_mask_reg(s_irq_mask);
  return s_irq_mask;
}

uint8_t irq_disable(uint8_t mask)
{
  s_irq_mask &= ~mask;
  write_irq_mask_reg(s_irq_mask);
  return s_irq_mask;
}

void irq_set_callback(irq_callback_t callback)
{
  s_callback = callback;
}
