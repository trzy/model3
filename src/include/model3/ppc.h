#ifndef INCLUDED_MODEL3_PPC_H
#define INCLUDED_MODEL3_PPC_H

#include <stdint.h>

extern uint32_t ppc_get_pvr(void);
extern uint32_t ppc_get_hid0(void);
extern uint32_t ppc_get_hid1(void);
extern uint32_t ppc_get_msr(void);
extern uint32_t ppc_get_dbatu(int n);
extern uint32_t ppc_get_dbatl(int n);
extern uint32_t ppc_get_ibatu(int n);
extern uint32_t ppc_get_ibatl(int n);
extern uint32_t ppc_get_sdr1(void);
extern uint32_t ppc_get_sr(int n);

static inline void ppc_stwbrx(uint32_t addr, uint32_t data)
{
  asm volatile
  (
    "stwbrx %0,%1,%2"
    :
    : "r" (data),
      "r" (0),
      "r" (addr)
  );
} 

static inline uint32_t ppc_lwbrx(uint32_t addr)
{
  uint32_t data;
  asm volatile
  (
    "lwbrx %0,%1,%2"
    : "=r" (data)
    : "r" (0),
      "r" (addr)
  );
  return data;
}

#endif  // INCLUDED_MODEL3_PPC_H
