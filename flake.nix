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
            cp git-ai $out/share/git-ai/
            cp -r scripts templates $out/share/git-ai/
            chmod +x $out/share/git-ai/git-ai
            makeWrapper $out/share/git-ai/git-ai $out/bin/git-ai \
              --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps}
          '';

          meta = with pkgs.lib; {
            description = "AI-powered git commit message generator";
            homepage = "https://github.com/git-extensions/git-ai";
            license = licenses.mit;
            maintainers = [ ];
            mainProgram = "git-ai";
            platforms = platforms.unix;
          };
        };

        devShells.default = pkgs.mkShell {
          name = "git-ai";
          packages = with pkgs; [
            bash
            gum
            bats
            shellcheck
          ];

          shellHook = ''
            if ! command -v claude &>/dev/null && ! command -v codex &>/dev/null; then
              echo "warning: no supported AI agent found — install Claude Code or Codex"
            fi
          '';
        };
      }
    );
}
