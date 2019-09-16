#ifndef INCLUDED_MODEL3_TILEGEN_H
#define INCLUDED_MODEL3_TILEGEN_H

#include <stdint.h>

extern void tilegen_printf_at(int x, int y, const char *fmt, ...);
extern void tilegen_printf(const char *fmt, ...);
extern void tilegen_clear_line_from(int x, int y);
extern void tilegen_clear_line(int y);
extern void tilegen_clrscr();
extern void tilegen_write_reg(int offset, uint32_t data);
extern void tilegen_init(void);

#endif  // INCLUDED_MODEL3_TILEGEN_H
