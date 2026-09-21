{
  pkgs ? import <nixpkgs> {},
}:
let
  pkgs-cross = pkgs.pkgsCross.aarch64-multiplatform;
  host = pkgs-cross.stdenv.hostPlatform.config;
in
pkgs-cross.mkShell {
  nativeBuildInputs = with pkgs; [
    gnumake
    scons
    git
    gnused
    pkg-config
    gengetopt
    automake
    autoconf
    binutils
    python3
    python3Packages.pandas
    python3Packages.numpy
    python3Packages.seaborn
    python3Packages.matplotlib
    python3Packages.tqdm
    valgrind
    openssl
    zeromq
    pkgs-cross.stdenv.cc
    pkgs-cross.stdenv.cc.bintools
    treefmt
  ];

  buildInputs= with pkgs-cross; [
    openssl
    zeromq
    stdenv
    stdenv.cc.libc
    stdenv.cc.libc.static
    (libevent.override {static=true;})
  ];

  CROSS_COMPILE = "${host}-";
}
