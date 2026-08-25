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
    pkgs.python3
    pkgs.python3Packages.pandas
    pkgs.python3Packages.seaborn
    pkgs.python3Packages.matplotlib
    pkgs.python3Packages.tqdm
  ];
}
