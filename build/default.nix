{ pkgs
, lib ? pkgs.lib
, rustc
, rustfmt
, clippy
, rust-src
}: {
  buildCModule = pkgs.callPackage ./c-module.nix { };
  buildRustModule = pkgs.callPackage ./rust-module.nix {
    inherit rustc;
  };

  buildInitramfs = pkgs.callPackage ./initramfs.nix { };

  buildKernelConfig = pkgs.callPackage ./kernel-config.nix {
    inherit rustc rustfmt rust-src;
  };
  buildKernel = pkgs.callPackage ./kernel.nix {
    inherit rustc rustfmt clippy rust-src;
  };

  buildQemuCmd = pkgs.callPackage ./run-qemu.nix { };
  buildGdbCmd = pkgs.callPackage ./run-gdb.nix { };
}
