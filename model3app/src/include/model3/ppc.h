#ifndef INCLUDED_MODEL3_PPC_H
#define INCLUDED_MODEL3_PPC_H

#include <stdint.h>

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

static inline uint32_t ppc_get_tbl(void)
{
  uint32_t data;
  asm volatile("mftb %0" : "=r" (data) ::);
  return data;
}

static inline uint32_t ppc_get_tbu(void)
{
  uint32_t data;
  asm volatile("mftbu %0" : "=r" (data) ::);
  return data;
}

extern uint64_t ppc_get_tb(void);
extern uint32_t ppc_get_pvr(void);
extern uint32_t ppc_get_hid0(void);
extern uint32_t ppc_get_hid1(void);
extern uint32_t ppc_get_msr(void);
extern void ppc_set_msr(uint32_t msr);
extern uint32_t ppc_get_dbatu(int n);
extern uint32_t ppc_get_dbatl(int n);
extern uint32_t ppc_get_ibatu(int n);
extern uint32_t ppc_get_ibatl(int n);
extern uint32_t ppc_get_sdr1(void);
extern uint32_t ppc_get_sr(int n);
extern void ppc_set_external_interrupt_enable(int on);

#endif  // INCLUDED_MODEL3_PPC_H
