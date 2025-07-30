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
    # Address and port of step CA, overrides settings.address. Is required.
    # 127.0.0.1 / localhost doesn't work, because clients will go to
    # https://ca.mesh.gq/acme/acme/directory and be given URL containing localhost as
    # the API endpoints to interact with.
    address = "ca.mesh.gq";
    port = 6060;

    # File containing clear-text password for intermediate key passphrase.
    intermediatePasswordFile = config.age.secrets.step-ca-pwd.path;
    settings = {
      root = "/var/lib/step-ca-data/root/ca.crt";
      crt = "/var/lib/step-ca-data/intermediate/im.crt";
      key = "/var/lib/step-ca-data/intermediate/im.key";
      # DNS name for the CA. Not sure how exactly this is used by step-ca, but
      # removing this entry breaks things.
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
            # https://ca.mesh.gq/acme/acme/directory
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
  security.acme.acceptTerms = true;

  # Certificate for this Vhost will be located under: /var/lib/acme/ca.mesh.gq
  services.nginx.virtualHosts."ca.mesh.gq" = {
    # Enable SSL and use ACME certificate
    forceSSL = true;
    enableACME = true;

    locations."/" = {
      proxyPass = "https://ca.mesh.gq:6060";
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
  security.pki.certificates = [
    # That second is the one used by minica on garmr to first create a self
    # signed certificate. Required otherwise deployment fails.
    ''
      -----BEGIN CERTIFICATE-----
      MIIB+zCCAYKgAwIBAgIIQb5m+VqV8sQwCgYIKoZIzj0EAwMwIDEeMBwGA1UEAxMV
      bWluaWNhIHJvb3QgY2EgNDFiZTY2MCAXDTI1MDcyODE4MTc1MloYDzIxMjUwNzI4
      MTgxNzUyWjAgMR4wHAYDVQQDExVtaW5pY2Egcm9vdCBjYSA0MWJlNjYwdjAQBgcq
      hkjOPQIBBgUrgQQAIgNiAATEmOlDxiYNGxaNhxGDgVTgOSSjHLsOY0zSwi20fz7M
      jtu/fgVsSj/boVRwrBkfEjQQ9bCVP+eSa7XMWphlqGQFBk4v5cl6lMS01FkG0lJx
      pZjEB64AtyWfFpgNUgaZE+CjgYYwgYMwDgYDVR0PAQH/BAQDAgKEMB0GA1UdJQQW
      MBQGCCsGAQUFBwMBBggrBgEFBQcDAjASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1Ud
      DgQWBBQEGhG/hr3sQ7AQrAikC2ixX5E0ejAfBgNVHSMEGDAWgBQEGhG/hr3sQ7AQ
      rAikC2ixX5E0ejAKBggqhkjOPQQDAwNnADBkAjAgXYtq1BtFJcBCR/btHhwvI3wT
      BIajNPcqMVODVYZOEwTQLxZc3NXcxLlZDhxG5hwCMA6zkHaMgq2ZFER2lzytpwm8
      17b2Z+VCtTEAp1+o0APKsKWoY6zR6EvIgKagT6L4Pg==
      -----END CERTIFICATE-----
    ''
  ];

  # Attribute set of certificates to get signed and renewed.
  security.acme.certs."ca.mesh.gq" = {
    # ACME Directory Resource URI: CA API URI.
    server = "https://ca.mesh.gq/acme/acme/directory";
    webroot = "/var/lib/acme/acme-challenge";
  };

  environment.systemPackages = with pkgs; [
    step-cli
  ];
}
