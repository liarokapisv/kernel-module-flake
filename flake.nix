{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , fenix
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (fenix.packages.${system}.latest) rustc clippy rustfmt rust-src;

      # Flake options
      enableBPF = true;
      enableRust = true;
      enableGdb = true;
      useRustForLinux = true;

      buildLib = pkgs.callPackage ./build {
        inherit rustc clippy rustfmt rust-src;
      };

      linuxConfigs = pkgs.callPackage ./configs/kernel.nix {
        inherit enableBPF enableRust useRustForLinux enableGdb;
      };
      inherit (linuxConfigs) kernelArgs kernelConfig;

      # Config file derivation
      configfile = buildLib.buildKernelConfig {
        inherit
          (kernelConfig)
          generateConfigFlags
          structuredExtraConfig
          enableRust
          ;
        inherit kernel nixpkgs;
      };

      # Kernel derivation
      kernelDrv = buildLib.buildKernel {
        inherit
          (kernelArgs)
          src
          modDirVersion
          version
          enableRust
          enableGdb
          ;

        inherit configfile nixpkgs;
      };

      linuxDev = pkgs.linuxPackagesFor kernelDrv;
      kernel = linuxDev.kernel;

      buildRustModule = buildLib.buildRustModule { inherit kernel; };
      buildCModule = buildLib.buildCModule { inherit kernel; };

      modules = [ cModule ] ++ pkgs.lib.optional enableRust rustModule;

      initramfs = buildLib.buildInitramfs {
        inherit kernel modules;

        extraBin =
          {
            strace = "${pkgs.strace}/bin/strace";
          }
          // pkgs.lib.optionalAttrs enableBPF {
            stackcount = "${pkgs.bcc}/bin/stackcount";
          };
        storePaths = [ pkgs.foot.terminfo ] ++ pkgs.lib.optionals enableBPF [ pkgs.bcc pkgs.python3 ];
      };

      runQemu = buildLib.buildQemuCmd { inherit kernel initramfs enableGdb; };
      runGdb = buildLib.buildGdbCmd { inherit kernel modules; };

      cModule = buildCModule {
        name = "helloworld";
        src = ./modules/helloworld;
      };

      rustModule = buildRustModule {
        name = "rust-out-of-tree";
        src =
          if useRustForLinux
          then ./modules/rfl_rust
          else ./modules/rust;
      };

      ebpf-stacktrace = pkgs.stdenv.mkDerivation {
        name = "ebpf-stacktrace";
        src = ./ebpf/ebpf_stacktrace;
        installPhase = ''
          runHook preInstall

          mkdir $out
          cp ./helloworld $out/
          cp ./helloworld_dbg $out/
          cp runit.sh $out/

          runHook postInstall
        '';
        meta.platforms = [ "x86_64-linux" ];
      };

      genRustAnalyzer =
        pkgs.writers.writePython3Bin
          "generate-rust-analyzer"
          { }
          (builtins.readFile ./scripts/generate_rust_analyzer.py);

      devShell =
        let
          nativeBuildInputs = with pkgs;
            [
              bear # for compile_commands.json, use bear -- make
              runQemu
              git
              gdb
              qemu
              pahole

              # static analysis
              flawfinder
              cppcheck
              sparse
              rustc
            ]
            ++ lib.optional enableGdb runGdb
            ++ lib.optionals enableRust [ rustfmt genRustAnalyzer ];
          buildInputs = [ pkgs.nukeReferences kernel.dev ];
        in
        pkgs.mkShell {
          inherit buildInputs nativeBuildInputs;
          KERNEL = kernel.dev;
          KERNEL_VERSION = kernel.modDirVersion;
          RUST_LIB_SRC = pkgs.rustPlatform.rustLibSrc;
        };
    in
    {
      lib = {
        builders = import ./build/default.nix;
      };

      packages.${system} = {
        inherit initramfs kernel cModule ebpf-stacktrace rustModule genRustAnalyzer rust-src;
        kernelConfig = configfile;
      };

      devShells.${system}.default = devShell;
    };
}
