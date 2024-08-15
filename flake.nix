{
  description = "Hercules CI Agent";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

  # Optional. Omit to use nixpkgs' nix
  # inputs.nix = {
  #   url = "github:NixOS/nix/master";
  #   inputs.nixpkgs.follows = "nixpkgs";
  # };

  outputs = inputs@{ self, nixpkgs, flake-parts, ... }:
    let
      agentFromFlakeConfig = cfg: opts: pkgs: lib:
        let
          mkIfNotNull = x: lib.mkIf (x != null) x;
        in
        {
          package = self.packages.${pkgs.system}.hercules-ci-agent; # defaultPriority below
          settings.labels.agent.source = "flake";
          settings.labels.agent.revision =
            mkIfNotNull (
              if (self?rev
                && opts.package.highestPrio == lib.modules.defaultOverridePriority or lib.modules.defaultPriority
              )
              then self.rev
              else if cfg.package ? rev
              then cfg.package.rev
              else null
            );
        };

      agentFromFlakeModule = { config, lib, options, pkgs, ... }: {
        _file = "${toString ./flake.nix}";
        config.services.hercules-ci-agent =
          agentFromFlakeConfig
            config.services.hercules-ci-agent
            options.services.hercules-ci-agent
            pkgs
            lib;
      };

      agentFromFlakeModule_multi = { config, lib, options, pkgs, ... }: {
        _file = "${toString ./flake.nix}";
        options =
          let
            mkIfNotNull = x: lib.mkIf (x != null) x;
            inherit (lib) types mkOption;
          in
          {
            services.hercules-ci-agents =
              mkOption {
                type = types.attrsOf (
                  types.submoduleWith {
                    modules = [
                      ({ options, config, ... }: {
                        config = agentFromFlakeConfig config options pkgs lib;
                      })
                    ];
                  }
                );
              };
          };
      };


      suffixAttrs = suf: inputs.nixpkgs.lib.mapAttrs' (n: v: { name = n + suf; value = v; });
    in
    flake-parts.lib.mkFlake { inherit inputs; } (flakeArgs@{ config, lib, inputs, ... }: {
      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
        ./nix/variants.nix
        ./nix/flake-private-dev-inputs.nix
        ./docs/flake-docs-render.nix
      ];
      config = {
        privateDevInputSubflakePath = "dev/private";
        partitionedAttrs.checks = "dev";
        partitionedAttrs.devShells = "dev";
        partitionedAttrs.herculesCI = "dev";
        partitions.dev.settings = { inputs, ... }: {
          imports = [
            ./nix/development.nix
            ./nix/flake-update-pre-commit.nix
            inputs.hercules-ci-effects.flakeModule
            inputs.pre-commit-hooks-nix.flakeModule
          ];
        };
        systems = [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-darwin"
          "x86_64-linux"
        ];
        flake = {
          overlay = config.flake.overlays.default;

          # A module like the one in Nixpkgs
          nixosModules.agent-service =
            { lib, pkgs, ... }:
            {
              _file = "${toString ./flake.nix}#nixosModules.agent-service";
              imports = [
                agentFromFlakeModule
                ./internal/nix/nixos/default.nix
              ];

              # This module replaces what's provided by NixOS
              disabledModules = [ "services/continuous-integration/hercules-ci-agent/default.nix" ];

              config = {
                services.hercules-ci-agent.settings.labels.module = "nixos-service";
              };
            };

          # An opinionated module for configuring an agent machine
          nixosModules.agent-profile =
            { lib, pkgs, ... }:
            {
              _file = "${toString ./flake.nix}#nixosModules.agent-profile";
              imports = [
                agentFromFlakeModule
                ./internal/nix/nixos/default.nix
                ./internal/nix/deploy-keys.nix
                ./internal/nix/gc.nix
              ];

              # This module replaces what's provided by NixOS
              disabledModules = [ "services/continuous-integration/hercules-ci-agent/default.nix" ];

              config = {
                services.hercules-ci-agent.settings.labels.module = "nixos-profile";
              };
            };

          # A module for configuring multiple agents on a single machine
          nixosModules.multi-agent-service =
            { lib, pkgs, ... }:
            {
              _file = "${toString ./flake.nix}#nixosModules.multi-agent-service";
              imports = [
                agentFromFlakeModule_multi
                ./internal/nix/nixos/multi.nix
              ];

              # Existence of the original module could cause confusion, even if they
              # can technically coexist.
              disabledModules = [ "services/continuous-integration/hercules-ci-agent/default.nix" ];

              options = let inherit (lib) types mkOption; in
                {
                  services.hercules-ci-agents =
                    mkOption {
                      type = types.attrsOf (
                        types.submoduleWith {
                          modules = [{ config.settings.labels.module = "nixos-multi-service"; }];
                        }
                      );
                    };
                };
            };

          # A nix-darwin module
          darwinModules.agent-service =
            { lib, pkgs, ... }:
            {
              _file = "${toString ./flake.nix}#darwinModules.agent-service";
              imports = [
                agentFromFlakeModule
                ./internal/nix/nix-darwin/default.nix
              ];

              # This module replaces what's provided by nix-darwin
              disabledModules = [ "services/hercules-ci-agent" ];

              config = {
                services.hercules-ci-agent.settings.labels.module = "darwin-service";
              };
            };

          # A nix-darwin module with more defaults set for machines that serve as agents
          darwinModules.agent-profile =
            { lib, pkgs, ... }:
            {
              _file = "${toString ./flake.nix}#darwinModules.agent-profile";
              imports = [
                agentFromFlakeModule
                ./internal/nix/nix-darwin/default.nix
                ./internal/nix/gc.nix
              ];

              # This module replaces what's provided by nix-darwin
              disabledModules = [ "services/hercules-ci-agent" ];

              config = {
                services.hercules-ci-agent.settings.labels.module = "darwin-profile";
              };
            };

          defaultTemplate = self.templates.nixos;
          templates = {
            nixos = {
              path = ./templates/nixos;
              description = "A NixOS configuration with Hercules CI Agent";
            };
          };
        };
        perSystem = { self', pkgs, ... }:
          {
            legacyPackages = import ./. { inherit pkgs; };

            packages = {
              inherit
                (self'.legacyPackages)
                hercules-ci-cli
                hercules-ci-agent
                hercules-ci-api-swagger
                hercules-ci-api-openapi3
                ;
              hci = self'.packages.hercules-ci-cli;
            };
          };
        # variants.nixUnstable.extraOverlay = final: prev: {
        #   nix = addDebug inputs.nix.defaultPackage.${prev.stdenv.hostPlatform.system};
        # };

        variants.forDevShell.isForDevShell = true;
        # Take the devShells from the dev variant
        flake.devShells = lib.mkIf (!config.isForDevShell) (
          lib.mkOverride ((lib.mkForce { }).priority - 1) (
            config.variants.forDevShell.flake.devShells
          )
        );
      };
      options = {
        # Set by variants
        extraOverlay = lib.mkOption {
          default = _: _: { };
        };
        isForDevShell = lib.mkOption {
          default = false;
          description = ''
            Whether we're producing a development attribute.

            We apply some overrides to fix things up in the context of devShell.
          '';
        };
      };
    });
}
