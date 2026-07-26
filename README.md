# Memcached Memwatched
This is a version of memcached that uses RT-Bench's memory watcher, so it is possible to move the heap or set a memory limit.

## Compilation

To compile this project you will need all the dependencies of memcached:
- `autotools-dev` or `autoconfig`
- `automake`
- `libevent-dev`
- `gcc` or a C/C++ compiler
- `make`

If you also want to run mutilate to test memcached, you will need:
- `gcc` or a C/C++ compiler
- `scons`
- `libevent-dev`
- `gengetopt`
- `libzmq-dev`
- `zeromq`

To apply the patches in the patch folder, only `git` is needed.

If you are a nix user, you can directly use the provided `shell.nix` which
includes all the above dependencies.

To compile everything you can simply issue `make`, this command will make sure
all the submodules are loaded, will apply the patches and compile both
`mutilate` `memcached` will be located in the `bin` folder.

## Improving the memcached patch

The easisest way to improvie the memcached patch, is to apply it with 

``` sh
git -C src/memcached apply ../../patches/memcached.patch
```

Then keep editing the files in the `src/memcached` folder. Once you're done you
can update the patch with:

``` sh
git -C src/memcached diff > patches/memcached.patch
```

Which will overwrite the patchfile with your modifications.
