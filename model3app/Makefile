#TODO: could improve this by using multiple Makefiles for each subproject and adding them automatically as depencies to "all"?

OUTPUT_ROM = crom.bin
OUTPUT_ELF = crom.elf
SRCS = model3app/src/test/test.c
LIBS = libmodel3

OBJDIR = obj
LIBDIR = obj
BINDIR = bin

CC = /c/mingw64-ppc/bin/powerpc-603e-eabi-gcc
LD = /c/mingw64-ppc/bin/powerpc-603e-eabi-gcc
AR = /c/mingw64-ppc/bin/powerpc-603e-eabi-ar
OBJCOPY = /c/mingw64-ppc/bin/powerpc-603e-eabi-objcopy
LDSCRIPT = model3app/src/libmodel3/ldscripts/model3.ld

DEPFLAGS = -MT $@	-MMD -MP -MF $(OBJDIR)/$*.d
CPPFLAGS = $(DEPFLAGS) -Imodel3app/src/include -I$(dir $<)
CFLAGS = -std=gnu99 -Os
ARFLAGS = rcs
LIBFLAGS = $(subst lib, -l, $(LIBS))
LDFLAGS = -T $(LDSCRIPT) -L$(LIBDIR) $(LIBFLAGS) -lc $(LIBFLAGS)  # gross hack: need to repeat libs twice and sandwich -lc because of interdependency with BSP

OBJS = $(foreach file,$(SRCS),$(OBJDIR)/$(basename $(notdir $(file))).o)
DEPENDENCIES = $(SRCS)  # so dependencies get included -- maybe rename this?

# Top-level rule gets built first
all: $(OBJDIR) $(BINDIR) $(LIBS) $(OBJS)
	$(info Linking $(BINDIR)/$(OUTPUT_ELF))
	@$(LD) $(OBJS) $(LDFLAGS) -o $(BINDIR)/$(OUTPUT_ELF)
	$(info Producing ROM image: $(BINDIR)/$(OUTPUT_ROM))
	@$(OBJCOPY) $(BINDIR)/$(OUTPUT_ELF) $(BINDIR)/$(OUTPUT_ROM) -O binary --pad-to=0x100000000

# Rules to build Model 3 BSP
include model3app/src/libmodel3/Makefile.inc

define COMPILE_C
	$(info Compiling $<)
	@$(CC) -c $(CPPFLAGS) $(CFLAGS) $< -o $@
endef

define COMPILE_ASM  # note: no dependency tracking for asm files (yet)
	$(info Assembling $<)
	@$(CC) -c $(CPPFLAGS) $< -o $@
endef

$(OBJDIR)/%.o: model3app/src/test/%.c $(OBJDIR)/%.d
	$(COMPILE_C)

$(OBJDIR):
	$(info Creating directory: $(OBJDIR))
	@mkdir $(OBJDIR)

$(LIBDIR):
	$(info Creating directory: $(LIBDIR))
	@mkdir $(LIBDIR)
	
$(BINDIR):
	$(info Creating directory: $(BINDIR))
	@mkdir $(BINDIR)

$(OBJDIR)/%.d: ;

clean:
	$(info Deleting binaries)
	@rm -f $(BINDIR)/$(OUTPUT_ELF)
	@rm -f $(BINDIR)/$(OUTPUT_ROM)
	$(info Deleting libraries)
	@rm -f $(OBJDIR)/*.a  # should be libdir but I'm afraid I'll delete real libs one day :P
	$(info Deleting object files)
	@rm -f $(OBJDIR)/*.o
	$(info Deleting dependency files)
	@rm -f $(OBJDIR)/*.d

include	$(patsubst %, $(OBJDIR)/%.d, $(basename $(notdir $(DEPENDENCIES))))