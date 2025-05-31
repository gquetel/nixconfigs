let
  # List of all systems / users public keys.
  hydra = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAH/lC/9diih/tyT2l/+GS/rjPHDOhjgr947w9ag1jRQ";
  
  gquetel-hydra = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIABgZ5qqnOl8LXcq2m/xaaKZlEB/ORDwIwaFSXJDs2eR gquetel@hydra";
  gquetel-scylla = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICK/iZJoWOdOasaD28jedexzjVc4tHosDTEYFIG/i9Fc gquetel@scylla";
  gquetel-pegasus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHCwtGA7+CTWUwDWBvS2HgLY0a7rT/7AZyCe4+qln5/n gquetel@pegasus";

  servers = [hydra];
  users = [gquetel-hydra gquetel-scylla gquetel-pegasus];
in
{
   # List of secrets and the users / systems we authorize to have access to.
   "gquetel-hydra.age".publicKeys = [hydra];
   "thesis-artefacts.age".publicKeys = [hydra];
}
