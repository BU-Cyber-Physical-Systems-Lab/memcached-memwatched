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
    libevent
    binutils
    openssl
    zeromq
  ];
  CONFIGURE_OPTS = "--host=x86_64";
}
