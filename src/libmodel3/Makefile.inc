LIBMODEL3_LIB = $(LIBDIR)/libmodel3.a
LIBMODEL3_SRCS = src/libmodel3/crom.S src/libmodel3/startup.S src/libmodel3/jtag.c src/libmodel3/tilegen.c src/libmodel3/newlib_stubs.c src/libmodel3/ppc.c

DEPENDENCIES += $(LIBMODEL3_SRCS)

LIBMODEL3_OBJS = $(foreach file, $(LIBMODEL3_SRCS), $(LIBDIR)/$(basename $(notdir $(file))).o)
libmodel3: $(LIBDIR) $(LIBMODEL3_OBJS)
	$(info Creating Model 3 board support package)
	@$(AR) $(ARFLAGS) $(LIBMODEL3_LIB) $(LIBMODEL3_OBJS)

$(OBJDIR)/%.o: src/libmodel3/%.c $(OBJDIR)/%.d
	$(COMPILE_C)
	
$(OBJDIR)/%.o: src/libmodel3/%.S
	$(COMPILE_ASM)
