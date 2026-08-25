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
RTBENCH_SRC_FLDR=src/rt-bench/generator/src
MEMCACHED_SRC_FLDR=src/memcached
MUTILATE_SRC_FLDR=test/mutilate
MIGRATION_SRC_FLDR=test/periodic_migration
MUTILATE_PATCH?= mutilate.patch

ifdef CROSS_COMPILE 
CC=$(CROSS_COMPILE)gcc
AR=$(CROSS_COMPILE)AR
LD=$(CROSS_COMPILE)LD
STRIP=$(CROSS_COMPILE)STRIP
CONFIGURE_OPTS+= --host=x86_64
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
	cd $(MEMCACHED_SRC_FLDR) &&  export CC="$(CC)" &&  ./configure $(CONFIGURE_OPTS)

$(MEMCACHED_SRC_FLDR)/memcached: $(MEMCACHED_SRC_FLDR)/Makefile $(RTBENCH_SRC_FLDR)/dlmalloc/source/dlmalloc.c $(MEMCACHED_SRC_FLDR)/*.c $(MEMCACHED_SRC_FLDR)/*.h
	@git -C $(RTBENCH_SRC_FLDR) apply $(PATCH_FLDR)/rt-bench.patch --check --reverse || git -C $(RTBENCH_SRC_FLDR) apply $(PATCH_FLDR)/rt-bench.patch
	@git -C $(RTBENCH_SRC_FLDR)/dlmalloc apply --check --reverse ../dlmalloc.patch || git -C $(RTBENCH_SRC_FLDR)/dlmalloc apply ../dlmalloc.patch
	@git -C $(MEMCACHED_SRC_FLDR) apply $(PATCH_FLDR)/memcached.patch --check --reverse || git -C $(MEMCACHED_SRC_FLDR) apply $(PATCH_FLDR)/memcached.patch
	make -C $(MEMCACHED_SRC_FLDR)

$(MUTILATE_SRC_FLDR)/README.md:
	@git submodule update --init $(MUTILATE_SRC_FLDR)

$(MUTILATE_SRC_FLDR)/mutilate: $(MUTILATE_SRC_FLDR)/README.md  $(MUTILATE_SRC_FLDR)/*.cc $(MUTILATE_SRC_FLDR)/*.h
	git -C $(MUTILATE_SRC_FLDR) apply $(PATCH_FLDR)/$(MUTILATE_PATCH) --check --reverse || git -C $(MUTILATE_SRC_FLDR) apply $(PATCH_FLDR)/$(MUTILATE_PATCH)
	sed -i "/env.Append(LIBPATH/ i\env.Append(LIBPATH= [\'$(LIBPATH)\'])" test/mutilate/SConstruct
	scons -C $(MUTILATE_SRC_FLDR)

$(MIGRATION_SRC_FLDR)/periodic_migration:
	make -C $(MIGRATION_SRC_FLDR) clean

server: $(MIGRATION_SRC_FLDR)/periodic_migration $(MEMCACHED_SRC_FLDR)/memcached $(SCRIPT_SRC_FLDR)/trigger_migration.sh $(SCRIPT_SRC_FLDR)/start_memcached.sh $(SCRIPT_SRC_FLDR)/get_memcached_libs.sh
	mkdir -p copy_on_server/memcached/lib
	cp $(MIGRATION_SRC_FLDR)/periodic_migration copy_on_sever/
    cp $(MEMCACHED_SRC_FLDR)/memcached copy_on_server/
	cp $(SCRIPT_SRC_FLDR)/trigger_migration.sh copy_on_server/
	cp $(SCRIPT_SRC_FLDR)/start_memcached.sh copy_on_server/
	./$(SCRIPT_SRC_FLDR)/get_memcached_libs.sh copy_on_server/memcached copy_on_server/lib
	./$(SCRIPT_SRC_FLDR)/get_memcached_libs.sh copy_on_server/periodic_mirgation copy_on_server/lib

clean: clean-memcached clean-mutilate clean-rt-bench clean-migration clean-server

clean-server:
	-rm -r copy_on_server

clean-migration:
	make -C $(MIGRATION_SRC_FLDR) clean

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
