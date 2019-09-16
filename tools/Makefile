#
# Makefile for tools.
#
# Execute in top-level directory:
#
#   make -f tools/Makefile
#

BINDIR = bin

# Build all tools
all: $(BINDIR)
	gcc tools/mergerom/mergerom.c -o $(BINDIR)/mergerom -Wall -O3 -std=c11
	gcc tools/splitrom/splitrom.c -o $(BINDIR)/splitrom -Wall -O3 -std=c11
	gcc tools/patchtool/patchtool.c -o $(BINDIR)/patchtool -Wall -O3 -std=c11

$(BINDIR):
	mkdir $(BINDIR)