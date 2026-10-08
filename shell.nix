{
  pkgs ? import <nixpkgs> { },
libsodium-static ? pkgs.libsodium.overrideAttrs (old: {
  dontDisableStatic = true;
}),
libevent-static ? 
    (pkgs.libevent.override {static=true;}),
zeromq-static ? pkgs.zeromq.overrideAttrs (old: {
  dontDisableStatic = true;
}),

}:

with pkgs;
mkShell
{
  buildInputs = with pkgs; [
    stdenv
    stdenv.cc
    stdenv.cc.libc.static
    stdenv.cc.bintools
    valgrind
    gnumake
    automake
    autoconf
    openssl
    treefmt
    pkg-config-unwrapped
    scons
    gengetopt
    zeromq-static
libevent-static
libsodium-static
cppzmq
    git
    python3
    python3Packages.numpy
    python3Packages.pandas
    python3Packages.seaborn
    python3Packages.matplotlib
    python3Packages.tqdm
  ];
shellHook = ''
  export PKG_CONFIG_PATH="${libevent-static.dev}/lib/pkgconfig:${libsodium-static.dev}/lib/pkgconfig:${zeromq-static}/lib/pkgconfig:$PKG_CONFIG_PATH"
'';
}
