TARGET = scheme

OBJS = main.o scheme.o platdep.o

EXTRA_TARGETS = EBOOT.PBP

CFLAGS = -g -DSCHEME_VERSION=\"$(shell git describe --always --dirty)\"

#BUILD_PRX=1

LIBS =

PSPSDK=$(shell psp-config --pspsdk-path)
include $(PSPSDK)/lib/build.mak
