LIBMODEL3_LIB = $(LIBDIR)/libmodel3.a
LIBMODEL3_SRCS =                            \
	model3app/src/libmodel3/crom.S            \
	model3app/src/libmodel3/startup.S         \
	model3app/src/libmodel3/ppc.c             \
	model3app/src/libmodel3/utils.c           \
	model3app/src/libmodel3/timer.c           \
	model3app/src/libmodel3/jtag.c            \
  model3app/src/libmodel3/rtc.c             \
	model3app/src/libmodel3/irq.c             \
	model3app/src/libmodel3/dma.c             \
	model3app/src/libmodel3/led.c             \
	model3app/src/libmodel3/tilegen.c         \
	model3app/src/libmodel3/real3d.c          \
	model3app/src/libmodel3/newlib_stubs.c

DEPENDENCIES += $(LIBMODEL3_SRCS)

LIBMODEL3_OBJS = $(foreach file, $(LIBMODEL3_SRCS), $(LIBDIR)/$(basename $(notdir $(file))).o)
libmodel3: $(LIBDIR) $(LIBMODEL3_OBJS)
	$(info Creating Model 3 board support package)
	@$(AR) $(ARFLAGS) $(LIBMODEL3_LIB) $(LIBMODEL3_OBJS)

$(OBJDIR)/%.o: model3app/src/libmodel3/%.c $(OBJDIR)/%.d
	$(COMPILE_C)
	
$(OBJDIR)/%.o: model3app/src/libmodel3/%.S
	$(COMPILE_ASM)
