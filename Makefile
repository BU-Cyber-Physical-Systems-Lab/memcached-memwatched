##
# memcached-memwatched
#
# @file
# @version 0.1
SHELL:= bash
.SHELLFLAGS:= -eu -o pipefail -c
.PHONY: clean setup all clean-rt-bench clean-memcached clean-mutilate

BASE_FLDR=$(abspath $(lastword $(dir $(MAKEFILE_LIST))))
PATCH_FLDR=$(BASE_FLDR)/patches
RTBENCH_SRC_FLDR=src/rt-bench/generator/src
MEMCACHED_SRC_FLDR=src/memcached
MUTILATE_SRC_FLDR=test/mutilate
MUTILATE_PATCH?= mutilate.patch
BIN_FLDR=bin
LIBPATH?=$(BASE_FLDR)/lib

all: $(BIN_FLDR)/memcached-debug $(BIN_FLDR)/memcached $(BIN_FLDR)/mutilate
setup: $(MEMCACHED_SRC_FLDR)/README.md $(RTBENCH_SRC_FLDR)/README.md $(RTBENCH_SRC_FLDR)/dlmalloc/source/dlmalloc.c $(MUTILATE_SRC_FLDR)/mutilate

$(MEMCACHED_SRC_FLDR)/README.md:
	@git submodule update --init $(MEMCACHED_SRC_FLDR)

src/rt-bench:
	@git submodule update --init $(RTBENCH_SRC_FLDR)

$(RTBENCH_SRC_FLDR)/dlmalloc/source/dlmalloc.c:
	@git submodule update --init $(RTBENCH_SRC_FLDR)/dlmalloc

$(MEMCACHED_SRC_FLDR)/configure:
	cd $(MEMCACHED_SRC_FLDR) && ./autogen.sh

$(MEMCACHED_SRC_FLDR)/Makefile: $(MEMCACHED_SRC_FLDR)/Makefile.am $(MEMCACHED_SRC_FLDR)/configure
	cd $(MEMCACHED_SRC_FLDR) &&	./configure $(CONFIGURE_OPTS)

$(BIN_FLDR)/memcached-debug $(BIN_FLDR)/memcached: $(MEMCACHED_SRC_FLDR)/Makefile $(RTBENCH_SRC_FLDR)/dlmalloc/source/dlmalloc.c $(MEMCACHED_SRC_FLDR)/*.c $(MEMCACHED_SRC_FLDR)/*.h
	@mkdir -p bin
	@git -C $(RTBENCH_SRC_FLDR) apply $(PATCH_FLDR)/rt-bench.patch --check --reverse || git -C $(RTBENCH_SRC_FLDR) apply $(PATCH_FLDR)/rt-bench.patch
	@git -C $(RTBENCH_SRC_FLDR)/dlmalloc apply --check --reverse ../dlmalloc.patch || git -C $(RTBENCH_SRC_FLDR)/dlmalloc apply ../dlmalloc.patch
	@git -C $(MEMCACHED_SRC_FLDR) apply $(PATCH_FLDR)/memcached.patch --check --reverse || git -C $(MEMCACHED_SRC_FLDR) apply $(PATCH_FLDR)/memcached.patch
	make -C $(MEMCACHED_SRC_FLDR)
	cp $(MEMCACHED_SRC_FLDR)/memcached bin/
	cp $(MEMCACHED_SRC_FLDR)/memcached-debug bin/

$(MUTILATE_SRC_FLDR)/README.md:
	@git submodule update --init $(MUTILATE_SRC_FLDR)

$(BIN_FLDR)/mutilate: $(MUTILATE_SRC_FLDR)/README.md  $(MUTILATE_SRC_FLDR)/*.cc $(MUTILATE_SRC_FLDR)/*.h
	@mkdir -p bin
	git -C $(MUTILATE_SRC_FLDR) apply $(PATCH_FLDR)/$(MUTILATE_PATCH) --check --reverse || git -C $(MUTILATE_SRC_FLDR) apply $(PATCH_FLDR)/$(MUTILATE_PATCH)
	sed -i "/env.Append(LIBPATH/ i\env.Append(LIBPATH= [\'$$LIBPATH\'])" test/mutilate/SConstruct
	scons -C $(MUTILATE_SRC_FLDR)
	cp $(MUTILATE_SRC_FLDR)/mutilate bin/


clean: clean-memcached clean-mutilate
	rm -rf bin

clean-memcached:
	rm -f bin/memcached*
	-make -C $(MEMCACHED_SRC_FLDR) clean
	git -C $(MEMCACHED_SRC_FLDR) restore .
	git -C $(MEMCACHED_SRC_FLDR) clean -fxd

clean-rt-bench:
	make -C src/rt-bench clean
	git -C $(RTBENCH_SRC_FLDR)/dlmalloc restore .
	git -C $(RTBENCH_SRC_FLDR) clean -fxd

clean-mutilate:
	rm -f bin/mutilate
	-scons -C $(MUTILATE_SRC_FLDR) -c clean
	git -C $(MUTILATE_SRC_FLDR) restore .
	git -C $(MUTILATE_SRC_FLDR) clean -fxd

# end
