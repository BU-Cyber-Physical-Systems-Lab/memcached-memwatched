##
#
# periodic migration
# @file
# @version 0.1
LDFLAGS= -lrt -lm
CFLAGS= -Og -ggdb -I../../src/locusta_utils/
.PHONY: all clean
SHELL:= bash
.SHELLFLAGS:= -eu -o pipefail -c
CC ?=gcc

all: periodic_migration

periodic_migration: periodic_migration.c
	$(CC) $(CFLAGS) -o $@ $<  $(LDFLAGS)

clean:
	-rm periodic_migration
# end
