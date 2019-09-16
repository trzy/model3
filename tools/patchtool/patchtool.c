#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>

typedef enum
{
  Invalid,
  Load,
  Save,
  Insert,
  Write32
} command_t;

typedef struct
{
  command_t command;
  int line_number;
  
  union
  {
    struct
    {
      const char *filename;
    } load_params;
    
    struct
    {
      const char *filename;
    } save_params;
    
    struct
    {
      const char *filename;
      uint32_t at_offset;
    } insert_params;
    
    struct
    {
      uint32_t offset;
      uint32_t value;
    } write32_params;
  };
} operation;

static operation *add_operation(operation **operations_out, size_t *num_operations_out, int line_number)
{
  size_t num_operations = *num_operations_out + 1;
  operation *operations = realloc(*operations_out, sizeof(operation) * num_operations);
  *operations_out = operations;
  *num_operations_out = num_operations;
  operation *op = &operations[num_operations - 1];
  op->command = Invalid;
  op->line_number = line_number;
  return op;
}

static bool is_hex(const char *str)
{
  for (; *str != 0; str++)
  {
    if (!isxdigit(*str))
    {
      return false;
    }
  }
  return true;
}

static uint32_t parse_hex(const char *str)
{
  return strtoul(str, NULL, 16);
}

static bool load_text_file(char **contents_out, size_t *size_out, const char *filename)
{
  FILE *fp = fopen(filename, "rb");
  if (fp == 0)
  {
    fprintf(stderr, "Error: Unable to open file for reading: %s\n", filename);
    return true;
  }
  fseek(fp, 0, SEEK_END);
  long int size = ftell(fp);
  rewind(fp);
  char *buffer = malloc(size + 1);
  fread(buffer, sizeof(char), size, fp);
  fclose(fp);
  *contents_out = buffer;
  *size_out = (size_t) size + 1;
  buffer[size] = 0; // in case file didn't end with newline
  return false;
}

static bool load_binary_file(uint8_t **contents_out, size_t *size_out, const char *filename)
{
  FILE *fp = fopen(filename, "rb");
  if (fp == 0)
  {
    fprintf(stderr, "Error: Unable to open file for reading: %s\n", filename);
    return true;
  }
  fseek(fp, 0, SEEK_END);
  long int size = ftell(fp);
  rewind(fp);
  uint8_t *buffer = malloc((size_t)size);
  fread(buffer, sizeof(uint8_t), size, fp);
  fclose(fp);
  *contents_out = buffer;
  *size_out = (size_t) size;
  return false;
}

static char *find_next_line(char *start, size_t length)
{
  char *end = &start[length];
  char *next_line = start;
  while (next_line < end && *next_line++ != '\n')
  {
  }
  return next_line;
}

static void strip_comments(char *line, size_t line_length)
{
  size_t i = 0;

  // Find '#'
  for (; i < line_length && line[i] != '#'; i++)
  {
  }

  // Replace entire comment with spaces until end of line
  for (; i < line_length && line[i] != '\n'; i++)
  {
    line[i] = ' ';
  }
}

static char *my_strtok_s(char *str, size_t *bytes_remaining, char **state)
{
  if (str != NULL)
  {
    *state = str;
  }
  
  // Resume search
  str = *state;
  
  // Search for next token
  while (*bytes_remaining > 0 && *str != 0)
  { 
    if (false == isspace(*str))
    {
      // Found a token. Find place to insert terminator.
      while (*bytes_remaining > 0)
      {
        if (isspace(*str) || *str == 0)
        {
          // Found end of token. Terminate the substring, save state, and exit.
          char *token_start = *state;
          *str = 0;
          *state = str + 1; // resume search at next character
          return token_start;
        }
        
       *bytes_remaining -= 1;
        str += 1;
      }
      
      // No whitespace found after token. String ended early.
      return NULL;
    }
    
    str += 1;
    *bytes_remaining -= 1;
  }
  
  // No more tokens
  return NULL;
}

static bool process_line(operation *op, char *current_line, size_t line_length, const char *filename, int line_number)
{
  strip_comments(current_line, line_length);
  
  // Each line consists of 3 tokens (or 0 for an empty line)
  size_t bytes_remaining = line_length;
  char *state = 0;
  char *tokens[3];
  int tokens_found = 0;
  char *token = my_strtok_s(current_line, &bytes_remaining, &state);
  while (token)
  {
    if (tokens_found < 3)
    {
      tokens[tokens_found] = token;
    }
    tokens_found += 1;
    token = my_strtok_s(NULL, &bytes_remaining, &state);
  }
  
  //printf("%d tokens\n", tokens_found);
  
  if (tokens_found == 0)
  {
    return false;
  }
  
  // Process tokens
  if (!strcmp(tokens[0], "load"))
  {
    if (tokens_found != 2)
    {
      fprintf(stderr, "Error: %s:%d: 'load' requires one argument (file name).\n", filename, line_number);
      return true;
    }
    op->command = Load;
    op->load_params.filename = tokens[1];
  }
  else if (!strcmp(tokens[0], "save"))
  {
    if (tokens_found != 2)
    {
      fprintf(stderr, "Error: %s:%d: 'save' requires one argument (file name).\n", filename, line_number);
      return true;
    }
    op->command = Save;
    op->save_params.filename = tokens[1];
  }
  else if (!strcmp(tokens[0], "insert"))
  {
    if (tokens_found != 3 || !is_hex(tokens[1]))
    {
      fprintf(stderr, "Error: %s:%d: 'insert' requires two arguments (hexadecimal offset and file name).\n", filename, line_number);
      return true;
    }
    op->command = Insert;
    op->insert_params.filename = tokens[2];
    op->insert_params.at_offset = parse_hex(tokens[1]);
  }
  else if (!strcmp(tokens[0], "write32"))
  {
    if (tokens_found != 3 || !is_hex(tokens[1]) || !is_hex(tokens[2]))
    {
      fprintf(stderr, "Error: %s:%d: 'write32' requires two hexadecimal arguments (offset and value).\n", filename, line_number);
      return true;
    }
    op->command = Write32;
    op->write32_params.offset = parse_hex(tokens[1]);
    op->write32_params.value = parse_hex(tokens[2]);
  }
  else
  {
    fprintf(stderr, "Error: %s:%d: Invalid command: %s\n", filename, line_number, tokens[0]);
    return true;
  }
  
  return false;
}

static bool load_operations(char **script, size_t *script_size, operation **operations_out, size_t *num_operations_out, const char *scriptfile)
{
  if (load_text_file(script, script_size, scriptfile))
  {
    return true;
  }
  
  bool error = false;
  size_t script_bytes_remaining = *script_size;
  char *current_line = *script;
  int line_number = 0;
  do
  {
    // Identify current line
    char *next_line = find_next_line(current_line, script_bytes_remaining);
    size_t line_length = next_line - current_line;
    if (0 == line_length)
    {
      break;
    }
    
    // Process it
    line_number += 1;
    operation *op = add_operation(operations_out, num_operations_out, line_number);
    error |= process_line(op, current_line, line_length, scriptfile, line_number);
    
    // Advance to next line
    script_bytes_remaining -= line_length;
    current_line = next_line;
  } while(true);

  return error;
}

static bool do_load(uint8_t **buffer, size_t *size, const char *filename)
{
  bool error = load_binary_file(buffer, size, filename);
  if (!error)
  {
    printf("Loaded %s (0x%zx bytes)\n", filename, *size);
  }
  return error;
}

static bool do_save(const char *filename, const uint8_t *buffer, size_t size)
{
  FILE *fp = fopen(filename, "wb");
  if (NULL == fp)
  {
    fprintf(stderr, "Error: Unable to open file for writing: %s\n", filename);
    return true;
  }
  fwrite(buffer, sizeof(uint8_t), size, fp);
  fclose(fp);
  printf("Saved %s (0x%zx bytes)\n", filename, size);
  return false;
}

static bool do_insert(uint8_t *buffer, size_t buffer_size, const char *filename, uint32_t at_offset)
{
  uint8_t *data;
  size_t data_size;
  if (load_binary_file(&data, &data_size, filename))
  {
    return true;
  }

  bool error_code = false;

  size_t end = (size_t) at_offset + data_size;
  if (end > buffer_size)
  {
    fprintf(stderr, "Error: Cannot insert '%s' at 0x%08x because it would overflow buffer.\n", filename, at_offset);
    error_code = true;
    goto cleanup;
  }
  
  memcpy(&buffer[at_offset], data, data_size);
  printf("Applied patch: 0x%08x = %s (0x%zx bytes)\n", at_offset, filename, data_size);

cleanup:
  free(data);
  return error_code;  
}

static bool do_write32(uint8_t *buffer, size_t buffer_size, uint32_t offset, uint32_t value)
{
  size_t end = (size_t) offset + sizeof(uint32_t);
  if (end > buffer_size)
  {
    fprintf(stderr, "Error: Offset exceeds buffer length.\n");
    return true;
  }
  buffer[offset + 0] = (value >> 24) & 0xff;
  buffer[offset + 1] = (value >> 16) & 0xff;
  buffer[offset + 2] = (value >> 8) & 0xff;
  buffer[offset + 3] = (value >> 0) & 0xff;
  printf("Applied patch: 0x%08x = 0x%08x\n", offset, value);
  return false;
}

static bool run_operations(int *error_line, operation *operations, size_t num_operations)
{
  uint8_t *buffer = NULL;
  size_t size = 0;

  bool error = false;

  for (int i = 0; i < num_operations && !error; i++)
  {
    *error_line = operations[i].line_number;
  
    switch (operations[i].command)
    {
    case Load:
      if (buffer != NULL)
      {
        free(buffer);
      }
      error |= do_load(&buffer, &size, operations[i].load_params.filename);
      break;
    case Save:
      error |= do_save(operations[i].save_params.filename, buffer, size);
      break;
    case Insert:
      error |= do_insert(buffer, size, operations[i].insert_params.filename, operations[i].insert_params.at_offset);
      break;
    case Write32:
      error |= do_write32(buffer, size, operations[i].write32_params.offset, operations[i].write32_params.value);
      break;
    default:
      break;
    }
  }
  
  return error;
}

int main(int argc, char **argv)
{
  if (argc <= 1)
  {
    printf("Usage: patchtool <file>\n");
    printf("Patches ROM files as instructed by the script file.\n");
    return 0;
  }

  char *script = NULL;
  size_t script_size = 0;
  operation *operations = NULL;
  size_t num_operations = 0;
  if (load_operations(&script, &script_size, &operations, &num_operations, argv[1]))
  {
    fprintf(stderr, "Error: Processing aborted due to errors in script.\n");
    return 1;
  }
  
  int error_line = 0;
  if (run_operations(&error_line, operations, num_operations))
  {
    fprintf(stderr, "Error: Processing halted at %s:%d.\n", argv[1], error_line);
    return 1;
  }
  
  return 0;
}