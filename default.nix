{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) nix lib;
  h = pkgs.haskell.lib.compose;

  # Overrides are copied (almost) verbatim over from original flake.nix

  haskellOverlay = self: super: {
    hercules-ci-optparse-applicative =
      self.callPackage ./nix/hercules-ci-optparse-applicative.nix { };
    hercules-ci-agent = self.callPackage ./hercules-ci-agent/package.nix {};
    hercules-ci-cnix-store = lib.pipe (self.callPackage ./hercules-ci-cnix-store/package.nix {}) [
      (x: x.override (o: { inherit nix; }))
      (x: x.overrideAttrs (o: {
        passthru = o.passthru // { nixPackage = nix; };
      }))
    ];
    hercules-ci-cnix-expr = lib.pipe (self.callPackage ./hercules-ci-cnix-expr/package.nix {}) [
      (x: x.override (o: { inherit nix; }))
      (h.addBuildTool pkgs.git)
    ];
    hercules-ci-cli = self.callPackage ./hercules-ci-cli/package.nix {};
    hercules-ci-api = self.callPackage ./hercules-ci-api/package.nix {};
  };

  pkgs' = pkgs.extend (final: prev: let
    super = final.haskellPackages;
    self = super;
    addCompactUnwind =
      if pkgs.stdenv.hostPlatform.isDarwin
      then h.appendConfigureFlags [ "--ghc-option=-fcompact-unwind" ]
      else x: x;
  in {
    haskellPackages = prev.haskellPackages.override {
      overrides = haskellOverlay;
    };

    hercules-ci-api = lib.pipe super.hercules-ci-api [
      h.justStaticExecutables
      addCompactUnwind
    ];

    hercules-ci-agent = lib.pipe super.hercules-ci-agent [
      h.justStaticExecutables
      (h.addBuildTool pkgs.makeBinaryWrapper)
      addCompactUnwind
      h.enableDWARFDebugging
      (h.addBuildDepends [ pkgs.boost ])
      (h.overrideCabal (o: {
        postCompileBuildDriver = ''
          echo Setup version:
          ./Setup --version
        '';
        postInstall = ''
          ${o.postInstall or ""}
          mkdir -p $out/libexec
          mv $out/bin/hercules-ci-agent $out/libexec
          makeWrapper $out/libexec/hercules-ci-agent $out/bin/hercules-ci-agent --prefix PATH : ${lib.makeBinPath 
            ([ pkgs.gnutar pkgs.gzip pkgs.git pkgs.openssh ]
             ++ lib.optional pkgs.stdenv.isLinux pkgs.crun)}
        '';
        passthru = o.passthru or { } // {
          inherit nix;
        };
      }))
      (self.generateOptparseApplicativeCompletions [ "hercules-ci-agent" ])
    ];
    
    hercules-ci-cli = lib.pipe super.hercules-ci-cli [
      (h.addBuildTool pkgs.makeBinaryWrapper)
      addCompactUnwind
      h.disableLibraryProfiling
      h.justStaticExecutables
      (self.generateOptparseApplicativeCompletions [ "hci" ])
      (h.overrideCabal (o:
        let wrap = lib.optionalString pkgs.stdenv.isLinux "wrapProgram $out/bin/hci --prefix PATH : ${lib.makeBinPath [ pkgs.crun ]}";
        in
        {
          postInstall =
            o.postInstall or ""
            + ''
              remove-references-to \
                -t "${super.hercules-ci-agent}" \
                -t "${super.hercules-ci-cli}" \
                "$out/bin/hci"
              ${wrap}
            '';
        }
      ))
    ];

    hercules-ci-api-swagger = pkgs.callPackage ./hercules-ci-api/swagger.nix { inherit (self) hercules-ci-api; };
    hercules-ci-api-openapi3 = pkgs.callPackage ./nix/openapi3.nix { inherit (self) hercules-ci-api; };
  });
in {
  inherit
    (pkgs')
    haskellPackages
    hercules-ci-cli
    hercules-ci-agent
    hercules-ci-api-swagger
    hercules-ci-api-openapi3
    ;
}
