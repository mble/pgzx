{
  description = "Description for the project";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/~0.2511.tar.gz";

    parts.url = "github:hercules-ci/flake-parts";

    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zls = {
      url = "github:zigtools/zls/0.14.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.zig-overlay.follows = "zig-overlay";
    };

    pre-commit-hooks-nix = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }: let
    zig-stable = "0.15.2";

    zig-overlay = _final: prev: let
      orig = inputs.zig-overlay.packages.${prev.system};
    in {
      zigpkgs =
        orig
        // {
          stable = orig.${zig-stable};
        };
    };

    zls-overlay = final: prev: let
      zig = final.zigpkgs.stable;
      target = builtins.replaceStrings ["darwin"] ["macos"] prev.system;
      zlsDeps = prev.callPackage ./nix/zls-deps.nix {inherit zig;};
    in {
      zls = inputs.zls.packages.${prev.system}.zls.overrideAttrs (_oldAttrs: {
        nativeBuildInputs = [zig];
        buildPhase = ''
          NO_COLOR=1
          PACKAGE_DIR=${zlsDeps}
          zig build install --global-cache-dir $(pwd)/.cache --system $PACKAGE_DIR -Dtarget=${target} -Doptimize=ReleaseSafe --prefix $out
        '';
        checkPhase = ''
          zig build test --global-cache-dir $(pwd)/.cache --system $PACKAGE_DIR -Dtarget=${target}
        '';
      });
    };
  in
    inputs.parts.lib.mkFlake {inherit inputs;} {
      debug = true;

      imports = [
        inputs.pre-commit-hooks-nix.flakeModule
        ./nix/modules/nixpkgs.nix
      ];

      flake.overlays = rec {
        default = nixpkgs.lib.composeManyExtensions [
          zigpkgs
          zls
          pgzx_scripts
        ];
        zigpkgs = zig-overlay;
        zls = zls-overlay;
        pgzx_scripts = _final: prev: {
          pgzx_scripts = self.packages.${prev.system}.pgzx_scripts;
        };
      };

      flake.templates = rec {
        default = init;
        init = {
          path = ./nix/templates/init;
          description = "Initialize postgres extension projects";
        };
      };

      systems = ["x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin"];

      perSystem = {
        config,
        lib,
        pkgs,
        ...
      }: {
        nixpkgs = {
          config.allowBroken = true;
          overlays = [
            zig-overlay
            zls-overlay
          ];
        };

        pre-commit.pkgs = pkgs;
        pre-commit.settings = {
          hooks = {
            # editorconfig-checker.enable = true;

            # check github actions files
            actionlint.enable = true;

            # check nix files
            alejandra.enable = true;
            deadnix.enable = true;

            # check shell scripts
            shellcheck.enable = true;
            shfmt_local = {
              enable = true;
              name = "shfmt";
              description = "Shell script formatter";
              types = ["shell"];
              entry = "${pkgs.shfmt}/bin/shfmt -d -i 0 -ci -s";
            };

            # zig linters
            zigfmt = {
              enable = true;
              name = "Zig fmt";
              entry = "${pkgs.zigpkgs.stable}/bin/zig fmt --check";
              files = "\\.zig$|\\.zon$";
            };
          };
        };

        packages.pgzx_scripts = pkgs.stdenvNoCC.mkDerivation {
          name = "pgzx_scripts";
          src = ./dev/bin;
          installPhase = ''
            mkdir -p $out/bin
            cp -r $src/* $out/bin
          '';
        };

        devShells = let
          mkDevShell = postgresql: let
            devshell_nix = (import ./devshell.nix) {
              inherit pkgs lib postgresql;
            };
          in
            pkgs.mkShell (devshell_nix
              // {
                shellHook = ''
                  ${devshell_nix.shellHook or ""}
                  ${config.pre-commit.devShell.shellHook or ""}
                '';
              });

          # Default PG16 shell, used for the debug shell below.
          default_shell_nix = (import ./devshell.nix) {
            inherit pkgs lib;
            postgresql = pkgs.postgresql_16_jit;
          };
          default_user_shell =
            default_shell_nix
            // {
              shellHook = ''
                ${default_shell_nix.shellHook or ""}
                ${config.pre-commit.devShell.shellHook or ""}
              '';
            };

          # On darwin we expect command line tools to be installed.
          # It is possible to install clang/gcc as nix package, but linking
          # can be quite a pain.
          # On non-darwin systems we will use the nix toolchain for now.
          useSystemCC = pkgs.stdenv.isDarwin;
        in {
          default = mkDevShell pkgs.postgresql_16_jit;
          pg16 = mkDevShell pkgs.postgresql_16_jit;
          pg17 = mkDevShell pkgs.postgresql_17;
          pg18 = mkDevShell pkgs.postgresql_18;

          # Create development shell with C tools and dependencies to build Postgres locally.
          debug = pkgs.mkShell (default_user_shell
            // {
              hardeningDisable = ["all"];

              packages =
                default_user_shell.packages
                ++ [
                  pkgs.flex
                  pkgs.bison
                  pkgs.meson
                  pkgs.ninja
                  pkgs.ccache
                  pkgs.pkg-config
                  pkgs.cmake

                  pkgs.icu
                  pkgs.zip
                  pkgs.readline
                  pkgs.openssl
                  pkgs.libxml2
                  pkgs.llvmPackages_17.llvm
                  pkgs.llvmPackages_17.lld
                  pkgs.llvmPackages_17.clang
                  pkgs.llvmPackages_17.clang-unwrapped
                  pkgs.lz4
                  pkgs.zstd
                  pkgs.libxslt
                  pkgs.python3
                ]
                ++ (lib.optionals (!useSystemCC) [
                  pkgs.clang
                ]);
            });
        };
      };
    };
}
