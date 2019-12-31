#include "model3/utils.h"
#include "model3/ppc.h"

void byte_reverse_words(uint32_t *src, uint32_t num_words)
{
  for (uint32_t i = 0; i < num_words; i++)
  {
    ppc_stwbrx((uint32_t) &src[i], src[i]);
  }
}
