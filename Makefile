##
# memcached-memwatched
#
# @file
# @version 0.1
SHELL:= bash
.SHELLFLAGS:= -eu -o pipefail -c
.PHONY: clean setup all clean-rt-bench clean-memcached clean-mutilate server clean-server clean-migration

BASE_FLDR=$(abspath $(lastword $(dir $(MAKEFILE_LIST))))
PATCH_FLDR=$(BASE_FLDR)/patches
SCRIPT_FLDR=$(BASE_FLDR)/scripts
RTBENCH_SRC_FLDR=src/rt-bench/generator/src
MEMCACHED_SRC_FLDR=src/memcached
MUTILATE_SRC_FLDR=test/mutilate
MIGRATION_SRC_FLDR=test/periodic_migration
MUTILATE_PATCH?= mutilate.patch
SCONS_OPTS?=
CONFIGURE_OPTS?=

ifdef CROSS_COMPILE 
SCONS_OPTS+=target=$(CROSS_COMPILE)
CONFIGURE_OPTS+=--host=$(CROSS_COMPILE:-=)
endif

all: $(MEMCACHED_SRC_FLDR)/memcached $(MUTILATE_SRC_FLDR)/mutilate $(MIGRATION_SRC_FLDR)/periodic_migration server
setup: $(MEMCACHED_SRC_FLDR)/README.md src/rt-bench/README.md $(RTBENCH_SRC_FLDR)/dlmalloc/source/dlmalloc.c $(MUTILATE_SRC_FLDR)/README.md

$(MEMCACHED_SRC_FLDR)/README.md:
	@git submodule update --init $(MEMCACHED_SRC_FLDR)

src/rt-bench/README.md:
	@git submodule update --init src/rt-bench

$(RTBENCH_SRC_FLDR)/dlmalloc/source/dlmalloc.c: src/rt-bench/README.md
	@git -C $(RTBENCH_SRC_FLDR) submodule update --init dlmalloc

$(MEMCACHED_SRC_FLDR)/configure:
	cd $(MEMCACHED_SRC_FLDR) && ./autogen.sh

$(MEMCACHED_SRC_FLDR)/Makefile: $(MEMCACHED_SRC_FLDR)/README.md $(MEMCACHED_SRC_FLDR)/configure
	cd $(MEMCACHED_SRC_FLDR) && ./configure $(CONFIGURE_OPTS)

$(MEMCACHED_SRC_FLDR)/memcached: $(MEMCACHED_SRC_FLDR)/Makefile $(RTBENCH_SRC_FLDR)/dlmalloc/source/dlmalloc.c
	@git -C $(RTBENCH_SRC_FLDR) apply $(PATCH_FLDR)/rt-bench.patch --check --reverse || git -C $(RTBENCH_SRC_FLDR) apply $(PATCH_FLDR)/rt-bench.patch
	@git -C $(RTBENCH_SRC_FLDR)/dlmalloc apply --check --reverse ../dlmalloc.patch || git -C $(RTBENCH_SRC_FLDR)/dlmalloc apply ../dlmalloc.patch
	@git -C $(MEMCACHED_SRC_FLDR) apply $(PATCH_FLDR)/memcached.patch --check --reverse || git -C $(MEMCACHED_SRC_FLDR) apply $(PATCH_FLDR)/memcached.patch
	$(MAKE) -C $(MEMCACHED_SRC_FLDR)

$(MUTILATE_SRC_FLDR)/README.md:
	@git submodule update --init $(MUTILATE_SRC_FLDR)

$(MUTILATE_SRC_FLDR)/mutilate: $(MUTILATE_SRC_FLDR)/README.md
	@git -C $(MUTILATE_SRC_FLDR) apply $(PATCH_FLDR)/$(MUTILATE_PATCH) --check --reverse || git -C $(MUTILATE_SRC_FLDR) apply $(PATCH_FLDR)/$(MUTILATE_PATCH)
	+scons -C $(MUTILATE_SRC_FLDR) $(SCONS_OPTS)

$(MIGRATION_SRC_FLDR)/periodic_migration:
	$(MAKE) -C $(MIGRATION_SRC_FLDR)

server: $(MIGRATION_SRC_FLDR)/periodic_migration $(MUTILATE_SRC_FLDR)/mutilate $(MEMCACHED_SRC_FLDR)/memcached $(SCRIPT_FLDR)/trigger_migration.sh $(SCRIPT_FLDR)/start_memcached.sh $(SCRIPT_FLDR)/get_memcached_libs.sh
	mkdir -p copy_on_board/memcached
	cp $(MIGRATION_SRC_FLDR)/periodic_migration copy_on_board/memcached/periodic_migration
	cp $(MEMCACHED_SRC_FLDR)/memcached copy_on_board/memcached/memcached
	cp $(MUTILATE_SRC_FLDR)/mutilate copy_on_board/memcached/mutilate
	cp $(SCRIPT_FLDR)/trigger_migration.sh copy_on_board/memcached/trigger_migration.sh
	cp $(SCRIPT_FLDR)/start_memcached.sh copy_on_board/memcached/start_memcached.sh
	cp $(SCRIPT_FLDR)/oneliner.sh copy_on_board/memcached/oneliner.sh
	cp $(SCRIPT_FLDR)/mutilate-migration-localhost.sh copy_on_board/memcached/mutilate-migration.sh

clean: clean-memcached clean-mutilate clean-rt-bench clean-migration clean-server

clean-server:
	-rm -r copy_on_board

clean-migration:
	$(MAKE) -C $(MIGRATION_SRC_FLDR) clean

clean-memcached:
	-make -C $(MEMCACHED_SRC_FLDR) clean
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
