{
  config,
  pkgs,
  inputs,
  ...
}:

let
  llmAgents = pkgs.callPackage ../../packages/llm-agents {
    inherit inputs;
  };
in
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware.nix
    ../../modules/fish
    ../../modules/fonts
    ../../modules/common
    ../../modules/tailscale
    ../../modules/fail2ban
    ../../modules/gitlab-runner
    ../../modules/dex
    ../../modules/outline
    ../../modules/servers
    ../../modules/plausible
    ../../modules/mlflow
    ../../modules/uptime-kuma
    ../../modules/wazuh-agent

    "${(import ../../npins).agenix}/modules/age.nix"
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  time.timeZone = "Europe/Paris";
  console.keyMap = "fr";

  # ---------------- My config  ----------------
  machine.meta = {
    ipTailscale = "100.64.0.3";
  };
  # Changed passwords will be reset according to the users.users configuration.
  users.mutableUsers = false;

  users.users.gquetel = {
    hashedPasswordFile = config.age.secrets.gquetel-strix.path;
    packages = [
      llmAgents."claude-code"
      llmAgents.codex
    ];
    openssh.authorizedKeys.keys = [
      # Scholarsec deploy.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMj/R2lRH0XRspKGInAI/glUtV0EodRT2fRzW2cC4M3g github-deploy-key"
      # GH Website deployment with restricted rights.
      ''command="${pkgs.rrsync}/bin/rrsync -wo /var/www/html/gquetel.fr",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkmeypF0OLB+L1c6RGZTOgkyf0j9BMYAqotbBtSMc2i web-deploy''
    ];
  };

  # ---------------- Networking  ----------------
  networking = {
    hostName = "strix";
    firewall.allowedTCPPorts = [
      22
      80
      443
      444
    ];
  };

  servers.lanAddresses = [
    "192.168.1.33/24"
    "2a01:cb00:253:ed00::0003/64"
  ];
  # Theses makes sure that when redirecting traffic, we use this IP and
  # not the privacy preserving ones.
  systemd.network.networks."10-wired".routes = [
    {
      Destination = "2a01:cb00:253:ed00::5/128";
      PreferredSource = "2a01:cb00:253:ed00::3";
    }
    {
      Destination = "2a01:cb00:253:ed00::7/128";
      PreferredSource = "2a01:cb00:253:ed00::3";
    }
  ];

  # Colmena deployment info
  deployment.targetHost = "strix";

  # ----------------- age secrets -----------------
  # https://github.com/ryantm/agenix?tab=readme-ov-file#agesecretsnamemode
  age.secrets.gquetel-strix.file = ../../secrets/gquetel-strix.age;
  age.secrets.thesis-artefacts = {
    file = ../../secrets/thesis-artefacts.age;
    mode = "770";
    owner = "nginx";
    group = "nginx";
  };

  # ----------------- Drivers -----------------

  environment.systemPackages = with pkgs; [
    goaccess
  ];

  # ----------------- Services -----------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
    };
  };

  # SNI Proxy Ressources:
  # - https://blog.le-vert.net/?p=224
  # -  https://nginx.org/en/docs/http/ngx_http_realip_module.html
  # - https://github.com/JulienMalka/snowfield/blob/f3e41b53c459fc4bda0d0773851dc0753e6e27ae/profiles/behind-sniproxy.nix#L10

  # ------------ Nginx ------------
  services.nginx = {
    # The SNI proxy below sends from loopback.
    appendHttpConfig = ''
      set_real_ip_from ::1;
    '';

    streamConfig = ''
      map $ssl_preread_server_name $targetBackend {
         movies.gquetel.fr   [2a01:cb00:253:ed00::7]:444;
         dmd.gquetel.fr   [2a01:cb00:253:ed00::7]:444;
         mesh.gquetel.fr   [2a01:cb00:253:ed00::5]:444;
         
         default [::1]:444;
      }

      log_format proxy '$remote_addr -> $targetBackend';
      access_log /var/log/nginx/proxy.log proxy;

      server {
          listen 192.168.1.33:443;
          proxy_protocol on;
          proxy_pass $targetBackend;
          ssl_preread on;
      }
    '';
  };
  systemd.services.nginx = {
    after = [ "tailscale-online.service" ];
    requires = [ "tailscale-online.service" ];
  };

  # Route only ACME HTTP-01 challenge requests to vapula; everything else on
  # port 80 for these hostnames is rejected to limit backend HTTP exposure.
  services.nginx.virtualHosts."dmd.gquetel.fr" = {
    listen = [
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
    locations."/.well-known/acme-challenge/".proxyPass = "http://[2a01:cb00:253:ed00::7]";
    locations."/".return = "404";
  };

  services.nginx.virtualHosts."movies.gquetel.fr" = {
    listen = [
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
    locations."/.well-known/acme-challenge/".proxyPass = "http://[2a01:cb00:253:ed00::7]";
    locations."/".return = "404";
  };

  # Route only ACME HTTP-01 challenge requests to garmr.
  services.nginx.virtualHosts."mesh.gquetel.fr" = {
    listen = [
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
    locations."/.well-known/acme-challenge/".proxyPass = "http://[2a01:cb00:253:ed00::5]";
    locations."/".return = "404";
  };

  services.nginx.virtualHosts."gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    listen = [
      {
        addr = "[::]";
        port = 444;
        ssl = true;
        proxyProtocol = true;
      }
      {
        addr = "[::]";
        port = 443;
        ssl = true;
      }
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
    root = "/var/www/html/gquetel.fr";
  };

  # VHost on which pdf artefacts are hosted.
  services.nginx.virtualHosts."thesis-artefacts.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    listen = [
      {
        addr = "[::]";
        port = 444;
        ssl = true;
        proxyProtocol = true;
      }
      {
        addr = "[::]";
        port = 443;
        ssl = true;
      }
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
    root = "/var/www/pdfs";
    locations."/" = {
      extraConfig = ''
        auth_basic "Documents de thèse de Grégor";
        auth_basic_user_file ${config.age.secrets.thesis-artefacts.path} ;

        types {
          application/pdf pdf;
        }
        autoindex on;
      '';
    };
  };

  services.nginx.virtualHosts."scholarsec.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    listen = [
      {
        addr = "[::]";
        port = 444;
        ssl = true;
        proxyProtocol = true;
      }
      {
        addr = "[::]";
        port = 443;
        ssl = true;
      }
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
    root = "/var/www/html/scholarsec";
  };

  # Redirect old domain name to new one
  services.nginx.virtualHosts."secscholar.gquetel.fr" = {
    forceSSL = true;
    enableACME = true;
    listen = [
      {
        addr = "[::]";
        port = 444;
        ssl = true;
        proxyProtocol = true;
      }
      {
        addr = "[::]";
        port = 443;
        ssl = true;
      }
      {
        addr = "0.0.0.0";
        port = 80;
      }
    ];
    globalRedirect = "scholarsec.gquetel.fr";
  };

  # ---------------- Modules ----------------
  plausible.enable = true;
  mlflow.enable = true;
  uptime-kuma.enable = true;
  # Public mTLS ingest so the off-tailnet compute cluster can push runs.
  # Reaches this host via the SNI proxy's default branch; mTLS terminates at
  # the per-host nginx vhost. Client certs are issued by step-ca (ca.mesh.gq).
  mlflow.ingest = {
    enable = true;
    clientCA = ../../modules/step-ca/roots.pem;
    allowedCIDRs = [
      "137.194.144.0/20" # Telecom Paris wifi pool
      "137.194.176.0/20" # Telecom Paris ethernet pool
      "137.194.192.0/24" # Telecom Paris cluster machines
      "137.194.132.0/22" # Telecom Paris slurm cluster machines
      "86.238.112.146" # Home
    ];
  };
  programs.rust-motd.settings.service_status = {
    gitlab-runner = "gitlab-runner";
    outline = "outline";
    prometheus_node_exporter = "prometheus-node-exporter";
    mlflow = "mlflow";
    uptime-kuma = "uptime-kuma";
  };

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.05"; # Did you read the comment?
}
