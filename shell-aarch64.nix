{
  pkgs ? import <nixpkgs> {},
}:
let
  pkgs-cross = pkgs.pkgsCross.aarch64-multiplatform;
  host = pkgs-cross.stdenv.hostPlatform.config;
  build = pkgs.stdenv.buildPlatform.config;
in
pkgs-cross.mkShell {
  nativeBuildInputs = with pkgs; [
    gnumake
    scons
    python3
    git
    gnused
    pkg-config
    gengetopt
    automake
    autoconf
    binutils
    pkgs-cross.stdenv.cc
    pkgs-cross.stdenv.cc.libc.static
    pkgs-cross.stdenv.cc.bintools
    python3
    python3Packages.pandas
    python3Packages.numpy
    python3Packages.seaborn
    python3Packages.matplotlib
    python3Packages.tqdm
  ];
  buildInputs = with pkgs-cross; [
    (libevent.override {static=true;})
    openssl
    zeromq
    pkgs-cross.glibc.static
  ];
  CROSS_COMPILE = "${host}-";
  LDFLAGS="-lc";
}
