{
  description = "pwndbg";

  nixConfig = {
    extra-substituters = [
      "https://pwndbg.cachix.org"
    ];
    extra-trusted-public-keys = [
      "pwndbg.cachix.org-1:HhtIpP7j73SnuzLgobqqa8LVTng5Qi36sQtNt79cD3k="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      ...
    }:
    let
      # Self contained packages for: Debian, RHEL-like (yum, rpm), Alpine, Arch packages
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
      forPortables = nixpkgs.lib.genAttrs [
        "deb"
        "rpm"
        "apk"
        "archlinux"
      ];
      crossNames = {
        "x86_32" = "gnu32";
        "x86_64" = "gnu64";
        "arm32" = "armv7l-hf-multiplatform";
        "arm64" = "aarch64-multiplatform";
        "riscv64" = "riscv64";
        "s390x" = "s390x";
        "ppc64" = "ppc64"; # broken lldb compilation ;(
        "ppc64le" = "powernv";
        "loong64" = "loongarch64-linux"; # broken stdenv: https://github.com/NixOS/nixpkgs/issues/380901
      };
      mapKeysWithName =
        formatfunc: values:
        (nixpkgs.lib.attrsets.mapAttrs' (
          name: value: {
            name = (formatfunc name);
            value = value;
          }
        ))
          values;

      overlayDarwin =
        final: prev:
        nixpkgs.lib.optionalAttrs prev.stdenv.isDarwin {
          pwndbg_gdb = prev.pwndbg_gdb.override {
            # Darwin version of libiconv causes issues with our portable build
            libiconv = prev.pkgsStatic.libiconvReal;
          };
        };
      pkgsBySystem = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          overlays = [
            (final: prev: {
              pwndbg_gdb = prev.gdb;
              pwndbg_lldb = prev.lldb_19;
            })
            (
              final: prev:
              nixpkgs.lib.optionalAttrs
                (prev.stdenv.targetPlatform.isPower64 && prev.stdenv.targetPlatform.isBigEndian)
                {
                  # ncurses is broken with gcc14+
                  ncurses = prev.ncurses.override {
                    stdenv = prev.gcc13Stdenv;
                  };
                }
            )
            (
              final: prev:
              nixpkgs.lib.optionalAttrs
                (prev.stdenv.targetPlatform.isPower64 && prev.stdenv.targetPlatform.isLittleEndian)
                {
                  # new boost is broken: https://github.com/NixOS/nixpkgs/issues/382179
                  boost = prev.boost183;
                }
            )
            overlayDarwin
            (final: prev: {
              pwndbg_gdb = import ./nix/overlay/gdb.nix { prev = prev; };
              pwndbg_lldb = import ./nix/overlay/lldb.nix { prev = prev; };
            })
          ];
        }
      );
      pkgUtil = forAllSystems (system: import ./nix/bundle/pkg.nix { pkgs = pkgsBySystem.${system}; });

      portableDrvLldb =
        system:
        import ./nix/portable.nix {
          pkgs = pkgsBySystem.${system};
          pwndbg = self.packages.${system}.pwndbg-lldb;
        };
      portableDrv =
        system:
        import ./nix/portable.nix {
          pkgs = pkgsBySystem.${system};
          pwndbg = self.packages.${system}.pwndbg;
        };
      portableDrvs =
        system:
        nixpkgs.lib.optionalAttrs pkgsBySystem.${system}.stdenv.isLinux (
          mapKeysWithName (name: "pwndbg-gdb-portable-${name}") (
            forPortables (
              packager:
              pkgUtil.${system}.buildPackagePFPM {
                inherit packager;
                drv = portableDrv system;
                config = ./nix/bundle/nfpm.yaml;
                preremove = ./nix/bundle/preremove.sh;
              }
            )
          )
        );
      tarballDrv = system: {
        "pwndbg-gdb-portable-tarball" = pkgUtil.${system}.buildPackageTarball { drv = portableDrv system; };
        "pwndbg-lldb-portable-tarball" = pkgUtil.${system}.buildPackageTarball {
          drv = portableDrvLldb system;
        };
      };
      pwndbg_gdb_drvs = (
        system: {
          pwndbg = import ./nix/pwndbg.nix {
            pkgs = pkgsBySystem.${system};
            inputs = inputs;
          };
          pwndbg-dev = import ./nix/pwndbg.nix {
            pkgs = pkgsBySystem.${system};
            inputs = inputs;
            isDev = true;
          };
        }
      );
      pwndbg_lldb_drvs = (
        system: {
          pwndbg-lldb = import ./nix/pwndbg.nix {
            pkgs = pkgsBySystem.${system};
            inputs = inputs;
            isLLDB = true;
          };
          pwndbg-lldb-dev = import ./nix/pwndbg.nix {
            pkgs = pkgsBySystem.${system};
            inputs = inputs;
            isDev = true;
            isLLDB = true;
          };
        }
      );
      tarballCrossDrv =
        system: cross: attrs:
        (pkgUtil.${system}.buildPackageTarball {
          drv = (
            import ./nix/portable.nix {
              pkgs = pkgsBySystem.${system}.pkgsCross.${crossNames.${cross}};
              pwndbg = (
                import ./nix/pwndbg.nix (
                  {
                    pkgs = pkgsBySystem.${system}.pkgsCross.${crossNames.${cross}};
                    inputs = inputs;
                  }
                  // attrs
                )
              );
            }
          );
        });
      crossDrvs =
        system:
        nixpkgs.lib.optionalAttrs pkgsBySystem.${system}.stdenv.isLinux (
          (nixpkgs.lib.attrsets.mapAttrs' (cross: value: {
            name = "pwndbg-gdb-cross-${cross}-tarball";
            value = tarballCrossDrv system cross { };
          }) crossNames)
          // (nixpkgs.lib.attrsets.mapAttrs' (cross: value: {
            name = "pwndbg-lldb-cross-${cross}-tarball";
            value = tarballCrossDrv system cross { isLLDB = true; };
          }) crossNames)
        );
    in
    {
      packages = forAllSystems (
        system:
        {
          default = self.packages.${system}.pwndbg;
        }
        // (crossDrvs system)
        // (portableDrvs system)
        // (tarballDrv system)
        // (pwndbg_gdb_drvs (if (system == "aarch64-darwin") then "x86_64-darwin" else system))
        // (pwndbg_lldb_drvs system)
      );

      devShells = forAllSystems (
        system:
        import ./nix/devshell.nix {
          pkgs = pkgsBySystem.${system};
          inputs = inputs;
          isLLDB = true;
        }
      );
      formatter = forAllSystems (system: pkgsBySystem.${system}.nixfmt-rfc-style);
    };
}
