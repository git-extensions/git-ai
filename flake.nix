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
        runtimeDeps = with pkgs; [ gum ];
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "git-ai";
          version = pkgs.lib.removeSuffix "\n" (builtins.readFile ./version.txt);
          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            mkdir -p $out/share/git-ai $out/bin
            cp -r * $out/share/git-ai/
            chmod +x $out/share/git-ai/git-ai
            makeWrapper $out/share/git-ai/git-ai $out/bin/git-ai \
              --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps}
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
