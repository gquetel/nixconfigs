{
  lib,
  config,
  pkgs,
  ...
}:
{
  # Some internal (tailnet) web applications cannot use Let's encrypt to generate
  # certificate: we do not own the domain used by MagicDNS.
  # Then, we will host a private Certificate Authority using step-ca, and generate
  # certificates from there. Traffic will be encrypted on the network, and browsers
  # will be happier.

  # https://smallstep.com/docs/step-ca/

  services.step-ca = {
    enable = true;

    # Address and port of step CA, overrides settings.address.
    address = "127.0.0.1";
    port = 5050;

    # File containing clear-text password for intermediate key passphrase.
    intermediatePasswordFile = "/run/keys/step-ca-pwd";
    settings = {
      root = "/var/lib/step-ca-data/.step/certs/root_ca.crt";
      federatedRoots = null;
      crt = "/var/lib/step-ca-data/.step/certs/intermediate_ca.crt";
      key = "/var/lib/step-ca-data/.step/secrets/intermediate_ca_key";
      dnsNames = [
        "ca.mesh.gq"
      ];
      logger = {
        format = "text";
      };
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
            # https://garmr.mesh.gq/acme/acme/directory
            type = "ACME";
            name = "acme";
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

  services.nginx.virtualHosts."ca.mesh.gq" = {
    # Enable SSL and use ACME certificate
    forceSSL = true;
    enableACME = true;

    locations."/" = {
      proxyPass = "https://127.0.0.1:5050";
      extraConfig = ''
        allow 100.64.0.0/10;
        allow fd7a:115c:a1e0::/48;
        deny all;
      '';
    };
  };
  
  security.acme.acceptTerms = true;

  security.acme.certs."ca.mesh.gq" = {
    server = "https://ca.mesh.gq/acme/acme/directory";
    webroot = "/var/lib/acme/.challenges";
  };

  environment.systemPackages = with pkgs; [
    step-cli
  ];

  # Installation steps:
  # - Enable service (activation will fail)
  # - Use: `step ca init` and fill prompted informations.
  # - Make sure user step-ca has access to all defined files (/var/lib/step-ca-data here,
  #   but it can be anything, as long as it's different than /var/lib/step-ca).

}
