##
# memcached-memwatched
#
# @file
# @version 0.1
SHELL:= bash
.SHELLFLAGS:= -eu -o pipefail -c
.PHONY: memcached mutilate test clean setup all clean-rt-bench clean-memcached clean-mutilate server clean-server clean-migration

BASE_FLDR=$(abspath $(lastword $(dir $(MAKEFILE_LIST))))
PATCH_FLDR=$(BASE_FLDR)/patches
SCRIPT_FLDR=$(BASE_FLDR)/scripts
RTBENCH_SRC_FLDR=src/rt-bench/generator/src
MEMCACHED_SRC_FLDR=src/memcached
MUTILATE_SRC_FLDR=test/mutilate
MIGRATION_SRC_FLDR=test/periodic_migration
DUMP_TIME_SRC_FLDR=test/dump_time
MUTILATE_PATCH?= mutilate.patch
SCONS_OPTS?=
CONFIGURE_OPTS?=
SERVER?=
CLIENT?=
LDFLAGS+=-static
SCONS_OPTS=linkflags=$(LDFLAGS)
ifdef CROSS_COMPILE
LDFLAGS+=-lc
CONFIGURE_OPTS+=--host=$(CROSS_COMPILE:-=)
SCONS_OPTS+=target=$(CROSS_COMPILE)
endif

all: $(MEMCACHED_SRC_FLDR)/memcached $(MUTILATE_SRC_FLDR)/mutilate $(MIGRATION_SRC_FLDR)/periodic_migration server client
setup: $(MEMCACHED_SRC_FLDR)/README.md src/rt-bench/README.md $(RTBENCH_SRC_FLDR)/dlmalloc/source/dlmalloc.c $(MUTILATE_SRC_FLDR)/README.md

memcached: $(MEMCACHED_SRC_FLDR)/memcached
mutilate: $(MUTILATE_SRC_FLDR)/mutilate
test: mutilate $(MIGRATION_SRC_FLDR)/periodic_migration $(DUMP_TIME_SRC_FLDR)/dump_time

$(MEMCACHED_SRC_FLDR)/README.md:
	@git submodule update --init $(MEMCACHED_SRC_FLDR)

src/rt-bench/README.md:
	@git submodule update --init src/rt-bench

$(RTBENCH_SRC_FLDR)/dlmalloc/source/dlmalloc.c: src/rt-bench/README.md
	@git -C $(RTBENCH_SRC_FLDR) submodule update --init dlmalloc

$(MEMCACHED_SRC_FLDR)/configure:
	cd $(MEMCACHED_SRC_FLDR) && ./autogen.sh

$(MEMCACHED_SRC_FLDR)/Makefile: $(MEMCACHED_SRC_FLDR)/README.md $(MEMCACHED_SRC_FLDR)/configure
	cd $(MEMCACHED_SRC_FLDR) &&  LDFLAGS="$(LDFLAGS)" ./configure $(CONFIGURE_OPTS)

$(MEMCACHED_SRC_FLDR)/memcached: $(MEMCACHED_SRC_FLDR)/Makefile $(RTBENCH_SRC_FLDR)/dlmalloc/source/dlmalloc.c
	-git -C $(RTBENCH_SRC_FLDR) apply $(PATCH_FLDR)/rt-bench.patch
	-git -C $(RTBENCH_SRC_FLDR)/dlmalloc apply ../dlmalloc.patch
	-git -C $(MEMCACHED_SRC_FLDR) apply $(PATCH_FLDR)/memcached.patch
	$(MAKE) -C $(MEMCACHED_SRC_FLDR)

$(MUTILATE_SRC_FLDR)/README.md:
	@git submodule update --init $(MUTILATE_SRC_FLDR)

$(MUTILATE_SRC_FLDR)/mutilate: $(MUTILATE_SRC_FLDR)/README.md
	-git -C $(MUTILATE_SRC_FLDR) apply $(PATCH_FLDR)/$(MUTILATE_PATCH)
	scons -C $(MUTILATE_SRC_FLDR) $(SCONS_OPTS)
ifdef CROSS_COMPILE
	mv $(MUTILATE_SRC_FLDR)/mutilate $(MUTILATE_SRC_FLDR)/mutilate-cross
endif

$(MIGRATION_SRC_FLDR)/periodic_migration:
	$(MAKE) -C $(MIGRATION_SRC_FLDR)

$(DUMP_TIME_SRC_FLDR)/dump_time:
	$(MAKE) -C $(DUMP_TIME_SRC_FLDR)

server: $(DUMP_TIME_SRC_FLDR)/dump_time $(MIGRATION_SRC_FLDR)/periodic_migration $(MUTILATE_SRC_FLDR)/mutilate $(MEMCACHED_SRC_FLDR)/memcached $(SCRIPT_FLDR)/trigger_migration.sh $(SCRIPT_FLDR)/start_memcached.sh $(SCRIPT_FLDR)/get_memcached_libs.sh
	mkdir -p copy_on_board/
	cp $(DUMP_TIME_SRC_FLDR)/dump_time copy_on_board/dump_time
	cp $(MIGRATION_SRC_FLDR)/periodic_migration copy_on_board/periodic_migration
	cp $(MEMCACHED_SRC_FLDR)/memcached copy_on_board/memcached
	-cp $(MUTILATE_SRC_FLDR)/mutilate-cross copy_on_board/mutilate
	cp $(SCRIPT_FLDR)/trigger_migration.sh copy_on_board/trigger_migration.sh
	cp $(SCRIPT_FLDR)/start_memcached.sh copy_on_board/start_memcached.sh
	cp $(SCRIPT_FLDR)/oneliner.sh copy_on_board/oneliner.sh
	cp $(SCRIPT_FLDR)/mutilate-migration-localhost.sh copy_on_board/mutilate-migration.sh
ifneq ($(SERVER),)
	scp -R copy_on_board/* $(SERVER):memcached-nix/
endif

client: mutilate
ifneq ($(CLIENT),)
	scp -R $(MUTILATE_SRC_FLDR)/mutilate $(CLIENT):
endif

clean: clean-memcached clean-mutilate clean-rt-bench clean-migration clean-server clean-time

clean-time:
	$(MAKE) -C $(DUMP_TIME_SRC_FLDR) clean

clean-server:
	-rm -r copy_on_board

clean-migration:
	$(MAKE) -C $(MIGRATION_SRC_FLDR) clean

clean-memcached:
	-$(MAKE) -C $(MEMCACHED_SRC_FLDR) clean
	-rm $(MEMCACHED_SRC_FLDR)/mutilate-cross
	git -C $(MEMCACHED_SRC_FLDR) restore .
	git -C $(MEMCACHED_SRC_FLDR) clean -fxd

clean-rt-bench:
	git -C $(RTBENCH_SRC_FLDR)/dlmalloc restore .
	git -C $(RTBENCH_SRC_FLDR) restore .
	git -C $(RTBENCH_SRC_FLDR) clean -fxd

clean-mutilate:
	-scons -C $(MUTILATE_SRC_FLDR) -c clean
	git -C $(MUTILATE_SRC_FLDR) restore .
	git -C $(MUTILATE_SRC_FLDR) clean -fxd

# end
