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

## How to get needed libs after cross-compilation
Static compilation is not supported unfortunately, so to you need to bring the libraries used in compilation if you canno install them on the target machine.

A surefire way to do this is to get the needed libraries:
```
executable=path/to/exec
readelf -d ${executable} | grep NEEDED
```

The for each of these library do:
```
ldconfig -p | grep name_of_the_library
```
This will give you the path on the compilation host.
You need to get all the needed libraries and put them in a folder, suppose `libs`.

Once you have all the needed libs you need to get also the linker, which depending on the architecture might have different names, but it always starts with `ld-linux-ARCH`, for linux arm64 it could be `ld-linux-aarch64.so.1`.

Then to make sure the executable loads the libraries and uses the correct liker you need to run it like this:
```
  ./lib/ld-linux-aarch64.so.1 \
  --library-path "$PWD/lib" \
  ./memcached -u root -w 4M:0x60000000:/dev/mem
```

Where `$PWD/lib` is the path where you copied all the needed libraries (liker included).

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
