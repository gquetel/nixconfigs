let
  # List of all systems / users public keys.
  # Can be found under /etc/ssh/*.pub
  system-strix = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvHay0sNHYnR3of3Kb+shjU6F6aBhvvTnKoIjdfhw75 root@strix";
  system-garmr = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINyVDTeg/odX9AQso1e9yyFXUNwrxIU/XQGMmHJHZ59X root@garmr";
  system-vapula = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJS3TWYs0F4beUVQHE4XXBi+0jqI/stwN7FVx6AK9E/Q root@nixos";
  system-scylla = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK7rePqrc63RwbDDBA1K6cwfvs43XWnGuwmByure5XBA root@scylla";
  system-charybdis = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICXm/0/TLnyVSnVIfZeMJv++ubX4nMJCTrK92sTYzDHN root@charybdis";
  system-surtr = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUaxCpfBb94BRWBzicB4DuGLKWSy1GkpBY9vz5x+QzK root@surtr";
  system-fafnir = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKOPRjYMWMwu6/GYFn/TWgVRXyx8Rnyf6sKa/H4Xo6xE root@fafnir";

  inherit (import ../keys.nix) gquetel-scylla gquetel-charybdis gquetel-surtr;

  servers = [
    system-strix
    system-garmr
    system-vapula
    system-fafnir
  ];
  workstations = [
    system-scylla
    system-charybdis
    system-surtr
  ];
  users = [
    gquetel-scylla
    gquetel-charybdis
    gquetel-surtr
  ];
in
{
  # Recipients of each secret. The content of each file is in README.md.

  # Secrets for strix machine
  "gquetel-strix.age".publicKeys = [ system-strix ] ++ users;
  "thesis-artefacts.age".publicKeys = [ system-strix ] ++ users;
  "gitlab-runner.env.age".publicKeys = [ system-strix ] ++ users;
  "dex-outline-secret.age".publicKeys = [ system-strix ] ++ users;
  "dex-mlflow-secret.age".publicKeys = [ system-strix ] ++ users;
  "mlflow-session-key.age".publicKeys = [ system-strix ] ++ users;
  "plausible-secret-key-base.age".publicKeys = [ system-strix ] ++ users;
  "hermes-outline-password.age".publicKeys = users;
  "restic-strix.pwd.age".publicKeys = [
    system-strix
    system-garmr
  ]
  ++ users;
  "restic-strix.env.age".publicKeys = [ system-strix ] ++ users;

  # Secrets for garmr machine
  "step-ca.pwd.age".publicKeys = [ system-garmr ] ++ users;
  "grafana-secret-key.age".publicKeys = [ system-garmr ] ++ users;
  "plane.env.age".publicKeys = [ system-garmr ] ++ users;
  "wazuh-server.env.age".publicKeys = [ system-garmr ] ++ users;
  "dex-wazuh-secret.age".publicKeys = [
    system-strix
    system-garmr
  ]
  ++ users;
  "backrest.env.age".publicKeys = [ system-garmr ] ++ users;
  "dex-backrest-secret.age".publicKeys = [
    system-strix
    system-garmr
  ]
  ++ users;
  "backrest-cookie-secret.age".publicKeys = [ system-garmr ] ++ users;

  # Secrets for vapula machine
  "mullvad-pvkey.age".publicKeys = [ system-vapula ] ++ users;
  "dex-hermes-secret.age".publicKeys = [
    system-strix
    system-vapula
  ]
  ++ users;
  "hermes-cookie-secret.age".publicKeys = [ system-vapula ] ++ users;
  "hermes.env.age".publicKeys = [ system-vapula ] ++ users;
  "hermes-plane-token.age".publicKeys = [ system-vapula ] ++ users;
  "agent-secrets.env.age".publicKeys = [ system-vapula ] ++ users;
  "hindsight.env.age".publicKeys = [ system-vapula ] ++ users;
  "hindsight-inference.env.age".publicKeys = [ system-vapula ] ++ users;
  "hindsight-cp.env.age".publicKeys = [ system-vapula ] ++ users;
  "dex-hindsight-secret.age".publicKeys = [ system-strix ] ++ users;
  "hindsight-oauth2-proxy.env.age".publicKeys = [ system-vapula ] ++ users;

  # Secrets for fafnir machine
  "garage.env.age".publicKeys = [ system-fafnir ] ++ users;

  # Secrets for all machines
  "wazuh-authd.pass.age".publicKeys = servers ++ workstations ++ users;
}
