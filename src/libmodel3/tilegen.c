#include "model3/tilegen.h"
#include "model3/ppc.h"
#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>

#include "charset.h"

enum Layers
{
  LayerA = 0,
  LayerAAlt,
  LayerB,
  LayerBAlt,
  NumLayers
};

static struct Cursor
{
  int x;
  int y;
} s_cursor;

static uint8_t s_text_layer = LayerA;

static uint32_t name_table_address(enum Layers layer)
{
  return 0xf1000000 + 0xf8000 + 0x2000*layer;
}

static inline uint32_t compute_offset_to_next_line(uint32_t current_offs)
{
  uint32_t next_line_offs = (current_offs + 64*2) & ~127;
  uint32_t adjust = next_line_offs - (current_offs + 4);
  return adjust;
}

static void print(int x, int y, const char *string)
{
  // Name table is 64x64, of which 62x48 is visible
  uint32_t dest_base = name_table_address(s_text_layer);
  if (x >= 62)
  {
    x = 0;
    y++;
  }
  uint32_t dest_offs = ((y*64) + x) * 2;
  dest_offs &= ~3;
  int offset = x & 1;
  bool done = false;
  while (!done)
  {
    if (y >= 48)
      return;
    uint32_t pair = ppc_lwbrx(dest_base + dest_offs);
    uint32_t adjust = 0;
    for (int i = offset; i < 2; i++)
    {
      if (x >= 62)  // wrap
      {
        adjust = compute_offset_to_next_line(dest_offs);
        x = 0;
        y++;
        break;
      }
      uint8_t c = *string++;
      if (!c)
      {
        done = true;
        break;
      }
      if (c == '\n')
      {
        adjust = compute_offset_to_next_line(dest_offs);
        x = 0;
        y++;
        break;
      }
      if (c == '\t')
      {
        // Our tab stop is only 2, so we have an easy job: if *next* x position
        // is not even, go back in input stream by one and do this over again
        string -= !(x & 1);
        c = ' ';  // use space character
      }
      c *= 2; // Scud Race charset: adjust like this or avoid rotation below
      uint16_t entry = (c >> 1) | (((uint16_t) c) << 15);
      if (i)
      {
        pair &= 0xffff0000;
        pair |= entry;
      }
      else
      {
        pair &= 0x0000ffff;
        pair |= ((uint32_t) entry) << 16;
      }
      x++;
    }
    offset = 0;
    ppc_stwbrx(dest_base + dest_offs, pair);
    dest_offs += 4;
    dest_offs += adjust;
  }
  s_cursor.x = x;
  s_cursor.y = y;
}

void tilegen_printf_at(int x, int y, const char *fmt, ...)
{
  if (!fmt)
    return;
  va_list vl;
  va_start(vl, fmt);
  char buf[1024];
  vsnprintf(buf, 1024, fmt, vl);
  va_end(vl);
  print(x, y, buf);
}

void tilegen_printf(const char *fmt, ...)
{
  if (!fmt)
    return;
  va_list vl;
  va_start(vl, fmt);
  char buf[1024];
  vsnprintf(buf, 1024, fmt, vl);
  va_end(vl);
  print(s_cursor.x, s_cursor.y, buf);
}

static inline void write_reg(uint8_t offset, uint32_t data)
{
  ppc_stwbrx(0xf1180000 + offset, data);
}

static void set_palette(uint16_t start_color, const uint16_t *pal, uint16_t num_colors)
{
  if (start_color > 32767)
    return;
  if (start_color + num_colors > 32768)
    num_colors = 32768 - start_color;
  const uint32_t pal_base_addr = 0xf1100000;
  for (uint32_t i = start_color*4; i < (start_color + num_colors)*4; i += 4)
  {
    uint32_t color = *pal++;
    ppc_stwbrx(pal_base_addr + i, color);
  }
}

static void set_memory_range(uint32_t start, uint32_t end, uint32_t value)
{
  for (; start < end; start += 4)
    ppc_stwbrx(start, value);
}

static inline uint16_t tilegen_t1bgr5(bool t, uint8_t r, uint8_t g, uint8_t b)
{
  return ((uint16_t) t << 15) | ((b & 0x1f) << 10) | ((g & 0x1f) << 5) | (r & 0x1f);
}

static void load_patterns(uint32_t dest_word_offset, const void *src_ptr, uint32_t num_words)
{
  const uint32_t *src = (const uint32_t *) src_ptr;
  uint32_t dest = 0xf1000000 + dest_word_offset * 4;
  for (uint32_t i = 0; i < num_words; i++)
    ppc_stwbrx(dest + i*4, *src++);
}

static void load_palette(uint32_t dest_color, const void *src_ptr, uint16_t num_colors)
{
  const uint16_t *src = (const uint16_t *) src_ptr;
  uint32_t dest = 0xf1100000 + dest_color*4;
  for (uint16_t i = 0; i < num_colors; i++)
    ppc_stwbrx(dest + i*4, *src++);
}

void tilegen_init(void)
{
  write_reg(0x08, 0xef);        // ?
  write_reg(0x40, 0);           // layer A/A' color offset
  write_reg(0x44, 0);           // layer B/B' color offset
  write_reg(0x60, 0x80000000);  // A scroll and layer enable
  write_reg(0x64, 0x80000000);  // A' scroll and layer enable
  write_reg(0x68, 0x80000000);  // B scroll and layer enable
  write_reg(0x6c, 0x80000000);  // B' scroll and layer enable
  write_reg(0x0c, 0x3);         // ?
  write_reg(0x20, 0x5ea);       // 8-bit color mode for all layers, priority setting 5, and unknown bits
  write_reg(0x10, 0x8);         // actually an IRQ ack register and probably not needed here
  
  /*
   * Carefully initialize VRAM:
   *  - Clear pattern table and load with characters.
   *  - Set all entries in scroll tables to 0x8000.
   *  - Stencil mask table: each entry is a word (high half -> A/A' selection,
   *    low half -> B/B'). The table is almost certainly 512 entries long but
   *    we will set first 384 entries to select primary layers and leave the
   *    remaining lines untouched, as VF3 does.
   *  - The layers are filled in with space characters except for layer B,
   *    presumably the bottom layer, which is set to pattern 0.
   */
  set_memory_range(0xf1000000, 0xf10f6000, 0);          // pattern table
  set_memory_range(0xf10f6000, 0xf10f7000, 0x80008000); // scroll table
  set_memory_range(0xf10f7000, 0xf10f7600, 0xffffffff); // stencil mask: lines 0-383
  //set_memory_range(0xf10f7600, 0xf10f7800, 0x00000000); // stencil mask: lines 384-511 (VF3 does not touch these)
  //set_memory_range(0xf10f7800, 0xf10f8000, 0x00000000); // ? (VF3 does not touch these)
  set_memory_range(0xf10f8000, 0xf10fa000, 0x00200020); // layer A (set to ' ' character)
  set_memory_range(0xf10fa000, 0xf10fc000, 0x00200020); // layer A'
  set_memory_range(0xf10fc000, 0xf10fe000, 0x00000000); // layer B (set to 0 -- perhaps for solid color?)
  set_memory_range(0xf10fe000, 0xf1100000, 0x00200020); // layer B'

  // Load character set
  load_patterns(0, tilegen_vf3_charset, 1024*(8*8));
  load_palette(0, tilegen_vf3_palette, 32768);
  s_cursor.x = 0;
  s_cursor.y = 0;
}
