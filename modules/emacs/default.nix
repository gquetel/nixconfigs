{
  lib,
  config,
  pkgs,
  ...
}:
{
  users.users.gquetel = {
    packages = ([
      pkgs.emacs
      # I am trying doomemacs, it possess an optionnal dependency on fd, see [1]
      # - [1] https://github.com/doomemacs/doomemacs?tab=readme-ov-file#prerequisites
      pkgs.fd
      (pkgs.python312.withPackages (ps: [
        # Required for generation
        ps.python-lsp-server
        ps.black # format
        ps.isort # automatically sort packages
      ]))
    ]);
  };
}
