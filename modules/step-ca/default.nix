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

  services.step-ca = {
    enable = true;

    # Address and port of step CA, overrides settings.address.
    address = "127.0.0.1";
    port = 5050;

    # File containing clear-text password for intermediate key passphrase.
    intermediatePasswordFile = config.age.secrets.step-ca-pwd.path;
    settings = {
      root = "/var/lib/step-ca-data/root/ca.crt";
      crt = "/var/lib/step-ca-data/intermediate/im.crt";
      key = "/var/lib/step-ca-data/intermediate/im.key";
      dnsNames = [
        "ca.mesh.gq" 
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

  # Attribute set of certificates to get signed and renewed.
  security.acme.certs."ca.mesh.gq" = {
    server = "https://ca.mesh.gq/acme/acme/directory";
  };

  environment.systemPackages = with pkgs; [
    step-cli
  ];
}
