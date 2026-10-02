{
  config,
  nodes,
  ...
}:
# paperhippo (~/repos/paperhippo), served on the tailnet at papers.mesh.gq.
let
  host = "papers.mesh.gq";
  cfg = config.services.paperhippo;
  ip = nodes.strix.config.machine.meta.ipTailscale;
in
{
  # TODO: pin with npins once the repository is on GitHub.
  imports = [ ../../../paperhippo/nix/module.nix ];

  services.paperhippo = {
    enable = true;
    llm = {
      baseUrl = "https://inference.luj.fr/v1";
      qaModel = "deepseek-v4-flash";
    };
    environmentFile = config.age.secrets.paperhippo-env.path;
  };

  age.secrets.paperhippo-env.file = ../../secrets/paperhippo-env.age;

  services.nginx.virtualHosts.${host} = {
    forceSSL = true;
    enableACME = true;
    listen = [
      {
        addr = ip;
        port = 443;
        ssl = true;
      }
      {
        addr = ip;
        port = 80;
      }
    ];
    locations."/" = {
      recommendedProxySettings = true;
      proxyPass = "http://127.0.0.1:${toString cfg.port}";
      extraConfig = ''
        allow 100.64.0.0/10;
        allow fd7a:115c:a1e0::/48;
        deny all;

        client_max_body_size 64m;
        # Answers wait for the LLM.
        proxy_read_timeout 300s;
      '';
    };
  };

  security.acme.certs.${host}.server = "https://ca.mesh.gq/acme/acme/directory";
}
