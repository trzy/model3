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
  if (argc <= 5)
  {
    printf("Usage: mergerom <ic20> <ic19> <ic18> <ic17> <crom>\n\n");
    printf("Merges individual byte-swapped CROM images into a single flat file.\n");
    return 0;
  }
  
  int error = 1;

  // Get file names
  const char *out = argv[5];
  const char *in[4];
  for (int i = 1; i <= 4; i++)
  {
      in[i - 1] = argv[i];
  }
  uint8_t *input_buf[4] = { NULL, NULL, NULL, NULL };
  long int input_size[4] = { 0, 0, 0, 0 };
  
  // Load each input ROM
  for (int i = 0; i < 4; i++)
  {
    FILE *ifp = fopen(in[i], "rb");
    if (!ifp)
    {
      fprintf(stderr, "mergerom: unable to open '%s' for reading\n", in[i]);
      goto fail;
    }
    
    input_size[i] = get_file_size(ifp);
    if ((input_size[i] & 1))
    {
      fprintf(stderr, "mergerom: size of '%s' is not even\n", in[i]);
      fclose(ifp);
      goto fail;
    }

    if (input_size[0] != input_size[i])
    {
      fprintf(stderr, "mergerom: input files must be the same size\n");
      fclose(ifp);
      goto fail;
    }
    
    input_buf[i] = malloc(input_size[i]);
    if (!input_buf[i])
    {
      fprintf(stderr, "mergerom: out of memory\n");
      fclose(ifp);
      goto fail;
    }
    
    fread(input_buf[i], sizeof(uint8_t), input_size[i], ifp);
    byte_swap(input_buf[i], input_size[i]);
    fclose(ifp);
  }
  
  // Open output file for writing
  FILE *fp = fopen(out, "wb");
  if (!fp)
  {
    fprintf(stderr, "mergerom: unable to open '%s' for writing\n", out);
    goto fail;
  }
  
  // Merge in sequence: IC20, IC19, IC18, IC17 (each is 16 bits wide)
  size_t pos[4] = { 0, 0, 0, 0 };
  for (long int i = 0; i < input_size[0] * 4; i += 2*4)
  {
    for (int j = 0; j < 4; j++)
    {
      fwrite(&input_buf[j][pos[j]], sizeof(uint8_t), 2, fp);
      pos[j] += 2;
    }
  }
  
  fclose(fp);
  
  // Success!
  error = 0;

fail:
  for (int i = 0; i < 4; i++)
  {
    if (input_buf[i] != NULL)
    {
      free(input_buf[i]);
    }
  }
  
  return error;
}