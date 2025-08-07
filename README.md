## NixOS Config

A repository containing the configurations of my machines running NixOS. Existing machines are: 
- [hydra](./machines/hydra/): an old gaming desktop, today used for remote work. No fancy software are installed, it mostly consists of those used for research (Zotero,Oobsidian, typst, ...)  
- [scylla](./machines/scylla/): a laptop for work, no fancy config here either, same installed software programs as hydra.
- [strix](./machines/strix/): a ThinkCenter acting as a webserver, mediaserver, also host a gitlab-runner and an outline instance.
- [garmr](./machines/garmr/): a ThinkCenter hosting a Headscale server and Certificate Authority.

Here are some nix-specific packages that might interest you, that are used in this repository: 
- [agenix](https://github.com/ryantm/agenix): To encrypt and manage secrets according to specific SSH keys.
- [colmena](https://github.com/zhaofengli/colmena): A neat configuration deployment tool. This is a wrapper around your usual configuration deployment. It supports parallel deployment and is great to quickly update the Thinkcenters.
