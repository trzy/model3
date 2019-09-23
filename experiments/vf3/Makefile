#
# Virtua Fighter 3 Patch Makefile
#
# Builds all Virtua Fighter 3 patches. Places each set of patched ROMs in its
# own subdirectory.
#
# Execute in top-level directory:
#
#   make -f experiments/vf3/Makefile
#
# Prerequisites:
# - Tools must be built and present in BINDIR.
#

###############################################################################
# Tools
###############################################################################

# PowerPC cross-compiler
AS = /c/mingw64-ppc/bin/powerpc-603e-eabi-gcc
LD = /c/mingw64-ppc/bin/powerpc-603e-eabi-ld
OBJCOPY = /c/mingw64-ppc/bin/powerpc-603e-eabi-objcopy

# Tools that must be built and present
PATCHTOOL = $(BINDIR)/patchtool
MERGEROM = $(BINDIR)/mergerom
SPLITROM = $(BINDIR)/splitrom

###############################################################################
# Files
###############################################################################

BINDIR = bin
OBJDIR = obj

#
# Input ROMs: IC20 IC19 IC18 IC17
#
# CRCs should be: 736A9431 731B6B78 9C5727E2 A7DF4D75
#
VF3_CROM_FILES = \
	experiments/vf3/roms/epr-19230c.20 \
	experiments/vf3/roms/epr-19229c.19 \
	experiments/vf3/roms/epr-19228c.18 \
	experiments/vf3/roms/epr-19227c.17

# Merged ROM filename (temporary)
# Must be consistent with patch_script.txt
MERGED_VF3_CROM_FILE = $(OBJDIR)/vf3_crom.bin

# Patched ROM filename (temporary)
# Must be consistent with patch_script.txt
PATCHED_VF3_CROM_FILE = $(OBJDIR)/vf3_crom_patched.bin

###############################################################################
# Patch Build Function
###############################################################################

#
# Parameters:
#   $(1) = Assembly source file (without extension, .S implied)
#
define BuildPatch
	mkdir -p $(BINDIR)/vf3_$(1)
	$(AS) -c experiments/vf3/src/$(1).S -o $(OBJDIR)/$(1).o
	$(LD) $(OBJDIR)/$(1).o -T experiments/vf3/src/vf3.ld -o $(OBJDIR)/vf3_patch.elf
	$(OBJCOPY) $(OBJDIR)/vf3_patch.elf $(OBJDIR)/vf3_patch.bin -O binary
	$(PATCHTOOL) experiments/vf3/src/patch_script.txt
	$(SPLITROM) $(PATCHED_VF3_CROM_FILE) $(BINDIR)/vf3_$(1)/vf3_ic20_patched.bin $(BINDIR)/vf3_$(1)/vf3_ic19_patched.bin $(BINDIR)/vf3_$(1)/vf3_ic18_patched.bin $(BINDIR)/vf3_$(1)/vf3_ic17_patched.bin 
endef

###############################################################################
# Rules
###############################################################################

all: $(OBJDIR)
	$(MERGEROM) $(VF3_CROM_FILES) $(MERGED_VF3_CROM_FILE)
	$(call BuildPatch,patch_timestamps)
	$(call BuildPatch,patch_timeline)
	$(call BuildPatch,patch_pingpong)
	$(call BuildPatch,patch_flush)

$(OBJDIR):
	mkdir $(OBJDIR)

$(BINDIR):
	mkdir $(BINDIR)
	