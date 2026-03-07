{
  description = "git-ai development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "git-ai";
          version = builtins.readFile ./version.txt;
          src = ./.;
          installPhase = ''
            mkdir -p $out/bin
            cp -r * $out/bin/
            chmod +x $out/bin/git-ai
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            bash
            gum
            bats
            shellcheck
          ];

          shellHook = ''
            if ! command -v claude &>/dev/null; then
              echo "warning: 'claude' CLI not found — install via: https://code.claude.com/docs/en/terminal-guide"
            fi
          '';
        };
      }
    );
}
