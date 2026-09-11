{
  pkgs ? import <nixpkgs> { },
}:

with pkgs;

mkShell {
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
    pkg-config-unwrapped
    scons
    (libevent.override {static=true;})
    gengetopt
    zeromq
    git
    python3
    python3Packages.numpy
    python3Packages.pandas
    python3Packages.seaborn
    python3Packages.matplotlib
    python3Packages.tqdm
  ];
}
