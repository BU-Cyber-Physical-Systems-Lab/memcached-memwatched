{
  pkgs ? import <nixpkgs> { },
}:

with pkgs;

mkShell {
  buildInputs = [
    pkgs.stdenv
    pkgs.gnumake
    pkgs.automake
    pkgs.autoconf
    pkgs.openssl
    pkgs.pkg-config-unwrapped
    pkgs.libevent.dev
    pkgs.scons
    pkgs.libevent
    pkgs.gengetopt
    pkgs.zeromq
    pkgs.git
  ];
}
