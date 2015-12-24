#include <stdlib.h>
#include <errno.h>
#include <stdint.h>

// Defined by linker script
extern uint32_t _stack[];
extern uint32_t _end[];

// Defined in newlib
#undef errno
extern int errno;

void *sbrk(int num_bytes)
{
  static uint8_t *heap_end = 0;
  const uint8_t *stack_start = (uint8_t *) _stack - 0x10000;  // 64KB stack limit
  if (!heap_end)  // first call
    heap_end = (uint8_t *) _end;
  uint8_t *prev_heap_end = heap_end;
  heap_end += num_bytes;
  if (heap_end > stack_start)
  {
    //TODO: print error
    abort();
  }
  return prev_heap_end;
}

int kill(int pid, int sig)
{
  errno = EINVAL;
  return -1;
}

int getpid(void)
{
  return 1;
}

void _exit(int code)
{
  while(1);
}
