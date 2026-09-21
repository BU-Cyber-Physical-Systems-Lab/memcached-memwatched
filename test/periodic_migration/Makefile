##
#
# periodic migration
# @file
# @version 0.1
LDFLAGS+= -lrt -lm -static
CFLAGS+= -Og -ggdb -I../../src/locusta_utils/ -I../../src/rt-bench/generator/include/
.PHONY: all clean
SHELL:= bash
.SHELLFLAGS:= -eu -o pipefail -c
CC ?=gcc

all: periodic_migration

periodic_migration: periodic_migration.c scheduling.o
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

scheduling.o: ../../src/rt-bench/generator/src/scheduling.c
	$(CC) $(CFLAGS) -c -o $@ $^ $(LDFLAGS)

clean:
	-rm periodic_migration *.o
# end
