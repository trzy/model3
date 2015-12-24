#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

static long int get_file_size(FILE *fp)
{
  fseek(fp, 0, SEEK_END);
  long int size = ftell(fp);
  rewind(fp);
  return size;
}

static void byte_swap(uint8_t *buf, long int size)
{
  for (long int i = 0; i < size; i += 2)
  {
    uint8_t tmp = buf[i+0];
    buf[i+0] = buf[i+1];
    buf[i+1] = tmp;
  }
}

int main(int argc, char **argv)
{
  if (argc <= 1 || (argc > 2 && argc != 6))
  {
    printf("Usage: splitrom <file> [ic20 ic19 ic18 ic17]\n\n");
    printf("Splits flat binary <file> into 4 files: ic20.bin, ic19.bin, ic18.bin, ic17.bin.\n");
    printf("Output file names may optionally be overriden.\n");
    return 0;
  }
  FILE *fp = 0;
  uint8_t *buf = 0;
  const char *file = argv[1];
  const char *out[4] = { "ic20.bin", "ic19.bin", "ic18.bin", "ic17.bin" };
  if (argc == 6)
  {
    for (int i = 2; i <= 5; i++)
      out[i-2] = argv[i];
  }
  fp = fopen(file, "rb");
  if (!fp)
  {
    fprintf(stderr, "splitrom: unable to open '%s' for reading\n", file);
    goto fail;
  }
  long int size = get_file_size(fp);
  if ((size & 1))
  {
    fprintf(stderr, "splitrom: size of '%s' is not even\n", file);
    goto fail;
  }
  buf = malloc(size);
  if (!buf)
  {
    fprintf(stderr, "splitrom: out of memory (tried to allocate %lu bytes)\n", size);
    goto fail;
  }
  fread(buf, sizeof(uint8_t), size, fp);
  fclose(fp);
  byte_swap(buf, size);
  for (int i = 0; i < 4; i++)
  {
    fp = fopen(out[i], "wb");
    if (!fp)
    {
      fprintf(stderr, "splitrom: unable to open '%s' for writing\n", out[i]);
      goto fail;
    }
    for (long int j = i*2; j < size; j += 8)
      fwrite(&buf[j], sizeof(uint8_t), 2, fp);
    fclose(fp);
  }
  free(buf);
  return 0;
fail:
  if (buf)
    free(buf);
  if (fp)
    fclose(fp);
  return 1;
}