{
  pkgs-cross ? import <nixpkgs> { crossSystem.config = "aarch64-unknown-linux-gnu"; },
}:
pkgs-cross.mkShell {
  nativeBuildInputs = with pkgs-cross; [
    gnumake
    automake
    autoconf
    scons
    python3
    git
    gnused
    pkg-config-unwrapped
    gengetopt
  ];
  buildInputs = with pkgs-cross; [
    stdenv
    glibc
    glibc.static
    gcc
    (libevent.override { static = true; })
    binutils
    openssl
    zeromq
  ];
  CONFIGURE_OPTS = "--host=x86_64";
  MUTILATE_PATCH = "mutilate-aarch64.patch";
  LIBPATH = "${(pkgs-cross.libevent.override { static = true; })}/lib";
}
