#include <stdint.h>
#include <ctype.h>
#include <string.h>

enum JTAGStates
{
  TestLogicReset, // 0
  RunTestIdle,    // 1
  SelectDRScan,   // 2
  CaptureDR,      // 3
  ShiftDR,        // 4
  Exit1DR,        // 5
  PauseDR,        // 6
  Exit2DR,        // 7
  UpdateDR,       // 8
  SelectIRScan,   // 9
  CaptureIR,      // 10
  ShiftIR,        // 11
  Exit1IR,        // 12
  PauseIR,        // 13
  Exit2IR,        // 14
  UpdateIR        // 15
};

static const uint8_t s_fsm[16][2] =
{ // tms=0,1
  {  1,  0 },     // 0  Test-Logic/Reset
  {  1,  2 },     // 1  Run-Test/Idle
  {  3,  9 },     // 2  Select-DR-Scan
  {  4,  5 },     // 3  Capture-DR
  {  4,  5 },     // 4  Shift-DR
  {  6,  8 },     // 5  Exit1-DR
  {  6,  7 },     // 6  Pause-DR
  {  4,  8 },     // 7  Exit2-DR
  {  1,  2 },     // 8  Update-DR
  { 10,  0 },     // 9  Select-IR-Scan
  { 11, 12 },     // 10 Capture-IR
  { 11, 12 },     // 11 Shift-IR
  { 13, 15 },     // 12 Exit1-IR
  { 13, 14 },     // 13 Pause-IR
  { 11, 15 },     // 14 Exit2-IR
  {  1,  2 }      // 15 Update-IR
};

static uint8_t s_state = TestLogicReset;

static int hex_to_int(char c)
{
  if (isdigit(c))
    return c - '0';
  else
    return tolower(c) - 'a' + 10;
}

static void string_to_reverse_bit_vector(uint8_t *bits, const char *bitstr, size_t num_bits)
{
  // String is serialized from back to front, with right-most bits written to
  // higher positions in bit vector so as to be shifted in last
  memset(bits, 0, num_bits/8 + 1);
  const char *lsb = &bitstr[strlen(bitstr)];
  for (int bit = num_bits - 1; bit >= 0; )
  {
    --lsb;
    int nibble = lsb < bitstr ? 0 : hex_to_int(*lsb);
    for (int i = 0; i < 4 && bit >= 0; i++, bit--)
    {
      int x = nibble & 1;
      nibble >>= 1;
      bits[bit/8] |= (x << (bit & 7));
    }
  }
}

static void pulse(int tms, int tdi)
{
  tms = !!tms;
  tdi = !!tdi;
  volatile uint8_t *jtag_port = (uint8_t *) 0xf010000c;
  uint8_t data = (1 << 7) | (0 << 6) | (tdi << 5) | (tms << 2); // trst, tck, tdi, tms
  *jtag_port = data;
  data |= (1 << 6);
  *jtag_port = data;
}

static void go_state(int next_state)
{
  int tms = s_fsm[s_state][0] == next_state ? 0 : 1;
  pulse(tms, 0);
  s_state = next_state;
}

static void shift_data_then_go_state(const char *bitstr, size_t num_bits, int next_state)
{
  uint8_t bits[num_bits/8+1];
  string_to_reverse_bit_vector(bits, bitstr, num_bits);
  int tms_current = s_fsm[s_state][0] == s_state ? 0 : 1;
  int tms_next = s_fsm[s_state][0] == next_state ? 0 : 1;
  // Remain in current state for first n-1 bits and then transition with last
  // data bit
  for (size_t i = 0; i < num_bits; i++)
  {
    int tdi = bits[i/8] & (1 << (i & 7));
    pulse(i == (num_bits - 1) ? tms_next : tms_current, tdi);
  }
  s_state = next_state;
}

static void load_data_register(const char *bitstr, int num_bits)
{
  go_state(SelectDRScan);
  go_state(CaptureDR);
  go_state(ShiftDR);
  shift_data_then_go_state(bitstr, num_bits, Exit1DR);
  go_state(UpdateDR);
}

static void load_instruction_register(const char *bitstr, int num_bits)
{
  go_state(SelectDRScan);
  go_state(SelectIRScan);
  go_state(CaptureIR);
  go_state(ShiftIR);
  shift_data_then_go_state(bitstr, num_bits, Exit1IR);
  go_state(UpdateIR);
}

static void reset_logic()
{
  go_state(SelectDRScan);
  go_state(SelectIRScan);
  go_state(TestLogicReset);
  shift_data_then_go_state("0", 4, RunTestIdle);
}

static void run_command(const char *instruction, int arg_length, const char *arg1, const char *arg2, const char *arg3)
{
  load_instruction_register(instruction, 46);
  if (arg1)
  {
    load_data_register(arg1, arg_length);
    go_state(RunTestIdle);
  }
  if (arg2)
  {
    load_data_register(arg2, arg_length);
    go_state(RunTestIdle);
  }
  if (arg3)
  {
    load_data_register(arg3, arg_length);
    go_state(RunTestIdle);
  }
}

void jtag_init(void)
{
  // This is the exact sequence used at boot-up by VF3, minus a lengthy test
  // involving dozens of alternating bit patterns (probably a RAM test)
  shift_data_then_go_state("0", 7, RunTestIdle);
  load_data_register("9d40c6d11d40c6d11ea0a3684ea023688ea0c3684ea0e3688", 197);
  go_state(RunTestIdle);
  reset_logic();
  reset_logic();
  run_command("3fffffffffe2", 42, "3a00000800", "3a818da23a", 0);
  run_command("3fffffffffe1", 19, "7401", 0, 0);
  run_command("3fffffffffe2", 42, "fa00000020", "3a818da23a", "3a818da23a");  // is the third arg strictly necessary?
  reset_logic();
  run_command("3fff18fc6318", 197, "1d40c6d11d40c6d10ea0a3684ea023688ea0c3684ea0e3688", 0, 0);
  run_command("3fffffffffe2", 42, "3a00000020", 0, 0);
  run_command("3fff18fc6318", 197, "1d40c6d11d40c6d10ea0a3684ea023688ea0c3684ea0e3688", 0, 0);
  run_command("3ffffffffc5f", 42, "3860000000", 0, 0);
  run_command("3fffffff8bff", 42, "3800000000", 0, 0);
  run_command("3ffffff17fff", 42, "3000000000", "23000000000", 0);
  run_command("3fffe2ffffff", 42, "0", 0, 0);
  run_command("3ffc5fffffff", 42, "0", 0, 0);
  run_command("3fffe2ffffff", 42, "0", 0, 0);
  run_command("3ffc5fffffff", 42, "0", 0, 0);
  run_command("3fffffffffe2", 42, "3a00000020", 0, 0);
  run_command("3ffffffffc5f", 42, "3840000000", 0, 0);
  run_command("3fffffffffe2", 42, "3a00004060", 0, 0);
  run_command("3ffffffffc5f", 42, "3800000000", 0, 0);
}
