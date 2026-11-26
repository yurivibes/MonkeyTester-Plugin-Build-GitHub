{
  description = "MonkeyTester-Plugin-Build-GitHub: MonkeyTester build plugin that builds on its own host";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        python = pkgs.python3;
        git = pkgs.git;
        src = pkgs.lib.cleanSource ./.;

        plugin = pkgs.writeShellApplication {
          name = "monkeytester-build-github";
          runtimeInputs = [ python git ];
          text = ''
            export PLUGIN_PORT="''${PLUGIN_PORT:-8095}"
            exec python3 ${src}/build_plugin.py "$@"
          '';
        };

        tests = pkgs.writeShellApplication {
          name = "monkeytester-build-github-tests";
          runtimeInputs = [ python git ];
          text = ''
            cd ${src}
            exec python3 -m unittest discover -s tests -v "$@"
          '';
        };
      in {
        packages.default = plugin;
        packages.monkeytester-build-github = plugin;

        # nix run .#      -> build-github plugin on :8095
        # nix run .#tests -> unit tests against the fake GitHub
        apps.default = { type = "app"; program = "${plugin}/bin/monkeytester-build-github"; };
        apps.tests = { type = "app"; program = "${tests}/bin/monkeytester-build-github-tests"; };

        devShells.default = pkgs.mkShell { packages = [ python git ]; };
      });
}
