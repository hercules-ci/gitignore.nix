{ pkgs ? import ./nix {}}:
pkgs.mkShell {
  name = "dev-shell";
  buildInputs = [ pkgs.niv ];
}
