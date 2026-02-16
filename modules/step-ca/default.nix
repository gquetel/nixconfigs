{
  lib,
  config,
  pkgs,
  ...
}:
{
  # Some internal (tailnet) web applications cannot use Let's encrypt to generate
  # certificate: we do not own the domains used in the extra records fields.

  # Therefore, we host a private Certificate Authority using step-ca, and generate
  # certificates from there. Traffic will be encrypted on the network, and browsers
  # will be happier.

  # https://smallstep.com/docs/step-ca/

  # 1 - Generate CA certificate:  step certificate create --profile=root-ca \
  #     "garmr Root CA" ca.crt ca.key --no-password --insecure

  # 2 - Generate intermediate certificate with custom password:
  #     step certificate create  --profile=intermediate-ca "garmr Intermediate CA" \
  #     im.crt im.key --ca=../root/ca.crt --ca-key=../root/ca.key

  # 3 - Make sure the user step-ca has access to all files:
  #     chown -R step-ca:step-ca /var/lib/step-ca-data/

  # step-ca binds to a Tailscale IP, so we need to wait for Tailscale to be online.
  systemd.services.step-ca = {
    after = [ "tailscale-online.service" ];
    requires = [ "tailscale-online.service" ];
  };

  services.step-ca = {
    enable = true;
    # Is required. Address and port of step CA, overrides settings.address.
    # 127.0.0.1 / localhost doesn't work, because these values are used to build URL
    # given at https://ca.mesh.gq/acme/acme/directory.
    address = "100.64.0.5";
    port = 6060;

    # File containing clear-text password for intermediate key passphrase.
    intermediatePasswordFile = config.age.secrets.step-ca-pwd.path;
    settings = {
      root = "/var/lib/step-ca-data/root/ca.crt";
      crt = "/var/lib/step-ca-data/intermediate/im.crt";
      key = "/var/lib/step-ca-data/intermediate/im.key";

      # DNS entries for which the certificate ca.mesh.gq should be valid
      # We add 100.64.0.5, because this is what will be used by links in links
      # provided by https://ca.mesh.gq/acme/acme/directory.

      dnsNames = [
        "ca.mesh.gq"
        "100.64.0.5"
      ];

      db = {
        type = "badgerv2";
        dataSource = "/var/lib/step-ca/db";
        badgerFileLoadingMode = "";
      };
      authority = {
        provisioners = [
          {
            # https://smallstep.com/docs/step-ca/provisioners/#example-3
            # ACME server directory URL is:
            # https://ca.mesh.gq/acme/acme/directory
            type = "ACME";
            name = "acme";
            claims = {
              # Issue certificates that lasts a week rather  than 24h
              defaultTLSCertDuration = "168h";
            };
          }
        ];

      };
      tls = {
        cipherSuites = [
          "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256"
          "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
        ];
        minVersion = 1.2;
        maxVersion = 1.3;
        renegotiation = false;
      };
    };
  };
  # nginx vhosts also bind to a Tailscale IP.
  systemd.services.nginx = {
    after = [ "tailscale-online.service" ];
    requires = [ "tailscale-online.service" ];
  };

  security.acme.acceptTerms = true;
  security.acme.defaults.renewInterval = "hourly";

  # Certificate for this Vhost will be located under: /var/lib/acme/ca.mesh.gq
  services.nginx.virtualHosts."ca.mesh.gq" = {
    # Enable SSL and use ACME certificate
    forceSSL = true;
    enableACME = true;
    listen = [
      {
        addr = "100.64.0.5";
        port = 443;
        ssl = true;
      }
      {
        addr = "100.64.0.5";
        port = 80;
      }
    ];
    locations."/" = {
      proxyPass = "https://100.64.0.5:6060";
      # Only allow interactions from machines in the tailnet.
      # And localhost for when when tailnet is not active yet.
      extraConfig = ''
        allow 100.64.0.0/10;
        allow fd7a:115c:a1e0::/48;
        allow ::1/128;
        deny all;
      '';
    };
  };

  # Attribute set of certificates to get signed and renewed.
  security.acme.certs."ca.mesh.gq" = {
    # ACME Directory Resource URI: CA API URI.
    server = "https://100.64.0.5:6060/acme/acme/directory";
    webroot = "/var/lib/acme/acme-challenge";
  };

  environment.systemPackages = with pkgs; [
    step-cli
  ];
}
