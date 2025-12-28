let
  # List of all systems / users public keys.
  # Can be found under /etc/ssh/*.pub
  system-strix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvHay0sNHYnR3of3Kb+shjU6F6aBhvvTnKoIjdfhw75 root@strix";
  system-garmr = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINyVDTeg/odX9AQso1e9yyFXUNwrxIU/XQGMmHJHZ59X root@garmr";
  system-vapula = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJS3TWYs0F4beUVQHE4XXBi+0jqI/stwN7FVx6AK9E/Q root@nixos";

  gquetel-hydra = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIABgZ5qqnOl8LXcq2m/xaaKZlEB/ORDwIwaFSXJDs2eR gquetel@hydra";
  gquetel-scylla = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICK/iZJoWOdOasaD28jedexzjVc4tHosDTEYFIG/i9Fc gquetel@scylla";

  servers = [
    system-strix
    system-garmr
    system-vapula
  ];
  users = [
    gquetel-hydra
    gquetel-scylla
  ];
in
{
  # List of secrets and the users / systems we authorize to have access to.
  # The machines using the secrets should be able to decrypt, so as our users.

  # Secrets for strix machine
  "gquetel-strix.age".publicKeys = [ system-strix ] ++ users;
  "thesis-artefacts.age".publicKeys = [ system-strix ] ++ users;
  "temporary.age".publicKeys = [ system-strix ] ++ users;
  "gitlab-runner.env.age".publicKeys = [ system-strix ] ++ users;
  "dex-outline-secret.age".publicKeys = [ system-strix ] ++ users;

  # Secrets for garmr machine
  "step-ca.pwd.age".publicKeys = [ system-garmr ] ++ users;

}
