let
  # List of all systems / users public keys.
  system-strix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvHay0sNHYnR3of3Kb+shjU6F6aBhvvTnKoIjdfhw75 root@strix";
  system-garmr = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINyVDTeg/odX9AQso1e9yyFXUNwrxIU/XQGMmHJHZ59X root@garmr";

  gquetel-hydra = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIABgZ5qqnOl8LXcq2m/xaaKZlEB/ORDwIwaFSXJDs2eR gquetel@hydra";
  gquetel-scylla = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICK/iZJoWOdOasaD28jedexzjVc4tHosDTEYFIG/i9Fc gquetel@scylla";

  servers = [ system-strix system-garmr ];
  users = [
    gquetel-hydra
    gquetel-scylla
  ];
in
{
  # List of secrets and the users / systems we authorize to have access to.

  # Secrets for strix machine, it should be able to decrypt, and users should be able
  # To modify it
  "gquetel-strix.age".publicKeys = [ system-strix ] ++ users;
  "thesis-artefacts.age".publicKeys = [ system-strix ] ++ users;
  "gitlab-runner.env.age".publicKeys = [ system-strix ] ++ users;

  # Secrets for garmr machine, it should be able to decrypt, and laptop users
  # should be able to read them. 
  "step-ca.pwd.age".publicKeys = [ system-garmr ] ++ users;
}
