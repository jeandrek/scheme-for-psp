TARGET = scheme

OBJS = main.o scheme.o

EXTRA_TARGETS = EBOOT.PBP

#BUILD_PRX=1

LIBS =

PSPSDK=$(shell psp-config --pspsdk-path)
include $(PSPSDK)/lib/build.mak
