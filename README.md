## NixOS Config

A repository containing the configurations of my machines running NixOS. Existing machines are: 
- [hydra](./machines/hydra/): an old gaming desktop, today used for remote work. No fancy software are installed, it mostly consist of those used for research (zotero, obsidian, typst, ...)  
- [scylla](./machines/scylla/): a laptop for work, no fancy config here either, same installed softwares as hydra.
- [strix](./machines/strix/): A ThinkCentre acting as a webserver / mediaserver, also host a gitlab-runner instance.

Here are some nix-specific packages that might interest you, that are used in this repository: 
- [agenix](https://github.com/ryantm/agenix): To encrypt and manage secrets according to specific SSH keys.
- [colmena](https://github.com/zhaofengli/colmena): A neat deployment tool.
