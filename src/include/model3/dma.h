#ifndef INCLUDED_MODEL3_DMA_H
#define INCLUDED_MODEL3_DMA_H

#include <stdint.h>
#include <stdbool.h>

extern int dma_irq_handler();
extern void dma_copy(uint32_t dest_addr, uint32_t *src, uint32_t num_words);
extern void dma_blocking_copy(uint32_t dest_addr, uint32_t *src, uint32_t num_words, bool byte_reverse);
extern bool dma_init();

#endif  // INCLUDED_MODEL3_DMA_H