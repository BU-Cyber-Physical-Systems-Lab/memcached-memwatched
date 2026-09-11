##
# dump_timestamp
#
# @file
# @version 0.1

LDFLAGS+= -static
CFLAGS+= -Og -ggdb
.PHONY: all clean
SHELL:= bash
.SHELLFLAGS:= -eu -o pipefail -c
CC ?=gcc

all: dump_time

dump_time: dump_time.c
	$(CC) $(CFLAGS) -o $@ $<  $(LDFLAGS)

clean:
	-rm dump_time

# end
