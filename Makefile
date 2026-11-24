##
# memcached-memwatched
#
# @file
# @version 0.1
SHELL:= bash
.SHELLFLAGS:= -eu -o pipefail -c
.PHONY: memcached mutilate test periodic_migration dump_time server nfs clean setup all clean-rt-bench clean-memcached clean-mutilate clean-server clean-migration

BASE_FLDR=$(abspath $(lastword $(dir $(MAKEFILE_LIST))))
PATCH_FLDR=$(BASE_FLDR)/patches
SCRIPT_FLDR=$(BASE_FLDR)/scripts
RTBENCH_SRC_FLDR=$(BASE_FLDR)/src/rt-bench
RTBENCH_MIGRATION_DEPS=$(addprefix $(RTBENCH_SRC_FLDR)/, generator/src/dlmalloc/source/dlmalloc.c generator/src/memory_watcher.c generator/include/logging.h generator/include/memory_watcher.h generator/include/multithread.h generator/include/optional_features.h)
LOCUSTA_SRC_FLDR=$(BASE_FLDR)/src/locusta_utils
PAGE_MIGRATION_SRC_FLDR=$(BASE_FLDR)/src/page_migration
TF_SRC_FLDR=$(BASE_FLDR)/src/tensorflow
TF_LOCUSTA_SRC_FLDR=$(BASE_FLDR)/src/tensorflow/tensorflow/lite/locusta
MEMCACHED_SRC_FLDR=$(BASE_FLDR)/src/memcached
MUTILATE_SRC_FLDR=$(BASE_FLDR)/test/mutilate
MIGRATION_SRC_FLDR=$(BASE_FLDR)/test/periodic_migration
DUMP_TIME_SRC_FLDR=$(BASE_FLDR)/test/dump_time
MUTILATE_PATCH?= mutilate.patch
SCONS_OPTS?=
CONFIGURE_OPTS?=
SERVER?=
CLIENT?=
LDFLAGS+=-static
SCONS_OPTS=linkflags="$(LDFLAGS)"
NFS_TARGET_FLDR?=/nfsroot/fciraolo/Locusta/
ifdef CROSS_COMPILE
LDFLAGS+=-lc
CONFIGURE_OPTS+=--host=$(CROSS_COMPILE:-=)
#SCONS_OPTS+=target=$(CROSS_COMPILE)
endif

all: memcached mutilate test tflite rt-bench
test: periodic_migration dump_time
setup: $(MEMCACHED_SRC_FLDR)/README.md src/rt-bench/README.md $(MUTILATE_SRC_FLDR)/README.md $(TF_SRC_FLDR)/README.md $(TF_LOCUSTA_SRC_FLDR)
	touch __init.py__

$(TF_SRC_FLDR)/README.md:
	git submodule update --init $(TF_SRC_FLDR)
	git -C $(TF_SRC_FLDR) checkout v2.21.0

$(TF_LOCUSTA_SRC_FLDR): $(TF_SRC_FLDR)/README.md
	mkdir $(TF_LOCUSTA_SRC_FLDR)
	ln $(PATCH_FLDR)/tflite/locusta/BUILD $(TF_LOCUSTA_SRC_FLDR)/BUILD
	for file in $$(find $(LOCUSTA_SRC_FLDR) -iname '*.c' -or -iname '*.h'); do ln $$file $(TF_LOCUSTA_SRC_FLDR)/$$(basename $$file); done
	for file in $$(find $(PAGE_MIGRATION_SRC_FLDR) -iname '*.c' -or -iname '*.h' -or -iname '*.a'); do ln $$file $(TF_LOCUSTA_SRC_FLDR)/$$(basename $$file); done

tflite: $(TF_SRC_FLDR)/bazel-bin/tensorflow/lite/tools/benchmark/benchmark_model

$(TF_SRC_FLDR)/bazel-bin/tensorflow/lite/tools/benchmark/benchmark_model: $(TF_LOCUSTA_SRC_FLDR) $(TF_SRC_FLDR)/README.md $(shell find $(LOCUSTA_SRC_FLDR) -iname '*.c' -or -iname "*.h") $(shell find $(PAGE_MIGRATION_SRC_FLDR) -iname '*.c' -or -iname '*.h' -or -iname '*.a')
	-git -C $(PATCH_FLDR) apply $(PATCH_FLDR)/tensorflow.patch
	cd $(TF_SRC_FLDR) && bazelisk build -c opt --config=monolithic --config=elinux_aarch64 //tensorflow/lite/tools/benchmark:benchmark_model
	chmod +w $(TF_SRC_FLDR)/bazel-bin/tensorflow/lite/tools/benchmark/benchmark_model

$(MEMCACHED_SRC_FLDR)/README.md:
	git submodule update --init $(MEMCACHED_SRC_FLDR)

rt-bench:
	-git -C $(RTBENCH_SRC_FLDR) apply $(PATCH_FLDR)/rt-bench.patch
	make -C $(RTBENCH_SRC_FLDR) compile-isolbench compile-image-filters #compile-vision

src/rt-bench/README.md:
	git submodule update --recursive --init src/rt-bench

$(MEMCACHED_SRC_FLDR)/configure:
	cd $(MEMCACHED_SRC_FLDR) && ./autogen.sh

$(MEMCACHED_SRC_FLDR)/Makefile: $(MEMCACHED_SRC_FLDR)/README.md $(MEMCACHED_SRC_FLDR)/configure
	cd $(MEMCACHED_SRC_FLDR) &&  LDFLAGS="$(LDFLAGS)" ./configure $(CONFIGURE_OPTS)

memcached: $(MEMCACHED_SRC_FLDR)/Makefile $(RTBENCH_SRC_FLDR)/generator/src/dlmalloc/source/dlmalloc.c
	-git -C $(RTBENCH_SRC_FLDR)/generator/src/dlmalloc apply ../dlmalloc.patch
	-git -C $(RTBENCH_SRC_FLDR) apply $(PATCH_FLDR)/rt-bench.patch
	-git -C $(MEMCACHED_SRC_FLDR) apply $(PATCH_FLDR)/memcached.patch
	$(MAKE) -C $(MEMCACHED_SRC_FLDR)

$(MUTILATE_SRC_FLDR)/README.md:
	git submodule update --init $(MUTILATE_SRC_FLDR)

mutilate: $(MUTILATE_SRC_FLDR)/README.md
	-git -C $(MUTILATE_SRC_FLDR) apply $(PATCH_FLDR)/$(MUTILATE_PATCH)
	scons -C $(MUTILATE_SRC_FLDR) $(SCONS_OPTS)

periodic_migration:
	$(MAKE) -C $(MIGRATION_SRC_FLDR)

dump_time:
	$(MAKE) -C $(DUMP_TIME_SRC_FLDR)

server: test memcached $(SCRIPT_FLDR)/trigger_migration.sh $(SCRIPT_FLDR)/start_memcached.sh $(SCRIPT_FLDR)/get_memcached_libs.sh tflite
	mkdir -p copy_on_board/{memcached,tflite}/
	cp $(TF_SRC_FLDR)/bazel-bin/tensorflow/lite/tools/benchmark/benchmark_model copy_on_board/tflite/
	cp $(DUMP_TIME_SRC_FLDR)/dump_time copy_on_board/memcached/dump_time
	cp $(MIGRATION_SRC_FLDR)/periodic_migration copy_on_board/{memcached,tflite}/periodic_migration
	cp $(MEMCACHED_SRC_FLDR)/memcached copy_on_board/memcached/memcached
	cp $(SCRIPT_FLDR)/trigger_migration.sh copy_on_board/{memcached,tflite}/trigger_migration.sh
	cp $(SCRIPT_FLDR)/start_memcached.sh copy_on_board/memcached/start_memcached.sh
	cp $(SCRIPT_FLDR)/oneliner.sh copy_on_board/memcached/oneliner.sh
	cp $(SCRIPT_FLDR)/mutilate-migration-localhost.sh copy_on_board/memcached/mutilate-migration.sh
	cp test/busybox-armv8l copy_on_board/busybox-armv8l
ifneq ($(SERVER),)
	scp -R copy_on_board/* $(SERVER):memcached-nix/
endif

rt-bench-nfs: rt-bench test
	mkdir -p $(NFS_TARGET_FLDR)/rtbench/canny $(NFS_TARGET_FLDR)/rtbench
	cp $(RTBENCH_SRC_FLDR)/image-filters/canny $(NFS_TARGET_FLDR)/rtbench/canny/
	cp $(RTBENCH_SRC_FLDR)/IsolBench/bandwidth $(NFS_TARGET_FLDR)/rtbench/bandwidth
	cp $(RTBENCH_SRC_FLDR)/image-filters/inputs/{4k,fullhd,vga}.bmp $(NFS_TARGET_FLDR)/rtbench/canny/
	cp $(MIGRATION_SRC_FLDR)/periodic_migration $(NFS_TARGET_FLDR)/rtbench/periodic_migration

tflite-nfs: tflite test
	mkdir -p $(NFS_TARGET_FLDR)/tflite
	cp $(TF_SRC_FLDR)/bazel-bin/tensorflow/lite/tools/benchmark/benchmark_model $(NFS_TARGET_FLDR)/tflite/
	cp $(MIGRATION_SRC_FLDR)/periodic_migration $(NFS_TARGET_FLDR)/tflite/periodic_migration

memcached-nfs: memcached test mutilate $(SCRIPT_FLDR)/trigger_migration.sh $(SCRIPT_FLDR)/start_memcached.sh $(SCRIPT_FLDR)/get_memcached_libs.sh
	mkdir -p $(NFS_TARGET_FLDR)/memcached
	cp $(MEMCACHED_SRC_FLDR)/memcached $(NFS_TARGET_FLDR)/memcached/memcached
	cp $(SCRIPT_FLDR)/trigger_migration.sh $(NFS_TARGET_FLDR)/memcached/trigger_migration.sh
	cp $(SCRIPT_FLDR)/start_memcached.sh $(NFS_TARGET_FLDR)/memcached/start_memcached.sh
	cp $(SCRIPT_FLDR)/oneliner.sh $(NFS_TARGET_FLDR)/oneliner.sh
	cp $(SCRIPT_FLDR)/mutilate-migration-localhost.sh $(NFS_TARGET_FLDR)/memcached/mutilate-migration.sh
	cp $(MIGRATION_SRC_FLDR)/periodic_migration $(NFS_TARGET_FLDR)/memcached/periodic_migration

nfs: test memcached  tflite tflite-models rtbench
	cp test/busybox-armv8l $(NFS_TARGET_FLDR)/busybox-armv8l
	cp $(DUMP_TIME_SRC_FLDR)/dump_time $(NFS_TARGET_FLDR)/dump_time
	-chmod -R 775 $(NFS_TARGET_FLDR)

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
	git -C $(MEMCACHED_SRC_FLDR) restore .
	git -C $(MEMCACHED_SRC_FLDR) clean -fxd

clean-rt-bench:
	git -C $(RTBENCH_SRC_FLDR)/generator/src/dlmalloc restore .
	git -C $(RTBENCH_SRC_FLDR)/generator/src/dlmalloc clean -fxd
	git -C $(RTBENCH_SRC_FLDR) restore .
	git -C $(RTBENCH_SRC_FLDR) clean -fxd

clean-mutilate:
	-scons -C $(MUTILATE_SRC_FLDR) -c clean
	git -C $(MUTILATE_SRC_FLDR) restore .
	git -C $(MUTILATE_SRC_FLDR) clean -fxd

# end
