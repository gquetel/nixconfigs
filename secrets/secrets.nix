let
  # List of all systems / users public keys.
  # Can be found under /etc/ssh/*.pub
  system-strix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvHay0sNHYnR3of3Kb+shjU6F6aBhvvTnKoIjdfhw75 root@strix";
  system-garmr = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINyVDTeg/odX9AQso1e9yyFXUNwrxIU/XQGMmHJHZ59X root@garmr";
  system-vapula = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJS3TWYs0F4beUVQHE4XXBi+0jqI/stwN7FVx6AK9E/Q root@nixos";

  gquetel-scylla = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICK/iZJoWOdOasaD28jedexzjVc4tHosDTEYFIG/i9Fc gquetel@scylla";
  gquetel-charybdis = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGI/nKCR/pq8yHrDdlQ3ml1jcio0Npxm5D7vJlG4QaDi gquetel@charybdis";

  servers = [
    system-strix
    system-garmr.age
    system-vapula
  ];
  users = [
    gquetel-scylla
    gquetel-charybdis
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
  "dex-mlflow-secret.age".publicKeys = [ system-strix ] ++ users;
  "mlflow-session-key.age".publicKeys = [ system-strix ] ++ users;
  "plausible-secret-key-base.age".publicKeys = [ system-strix ] ++ users;

  # Secrets for garmr machine
  "step-ca.pwd.age".publicKeys = [ system-garmr ] ++ users;
  "grafana-secret-key.age".publicKeys = [ system-garmr ] ++ users;
  "plane.env.age".publicKeys = [ system-garmr ] ++ users;

  # Secrets for vapula machine
  # Wireguard, public key = zoDZGWMPZ+QGAh8Ml9OospRJRlaoaWVFpU7EkdJv3XU=
  # private key can be decrypted using agenix -d wireguard-pvkey.age
  "wireguard-pvkey.age".publicKeys = [ system-vapula ] ++ users;

  # Expire 15 july 2027
  "claude-oauth-token.age".publicKeys = [ system-vapula ] ++ users;
  # Expire 15 october 2026
  "plane-agent.env.age".publicKeys = [ system-vapula ] ++ users;
  # Expire 15 july 2027
  "tailscale-authkey.age".publicKeys = [ system-vapula ] ++ users;

  # Zotero Web API key, read-only, for the thesis-citations agent profile.
  "zotero-agent.env.age".publicKeys = [ system-vapula ] ++ users;
  # GitLab deploy token (read_repository only) for cloning quetel_phd_latex.
  "thesis-repo-token.env.age".publicKeys = [ system-vapula ] ++ users;

}
