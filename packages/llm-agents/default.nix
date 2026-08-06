{
  inputs,
  pkgs,
}:
let
  llmAgents = builtins.getFlake "github:numtide/llm-agents.nix/${inputs.llm-agents.revision}";
  system = pkgs.stdenv.hostPlatform.system;
in
{
  "claude-code" = llmAgents.packages.${system}."claude-code";
  codex = llmAgents.packages.${system}.codex;

  # ACP (Agent Client Protocol) stdio servers wrapping the two CLIs above.
  "claude-agent-acp" = llmAgents.packages.${system}."claude-agent-acp";
  "codex-acp" = llmAgents.packages.${system}."codex-acp";

  # Agent CLI plus prebuilt web dashboard. The wheel keeps only the .py files
  # of the plugins/ tree, dropping the manifests and bundles the dashboard
  # needs, so ship that tree from source and point the loader at it.
  "hermes-agent" = llmAgents.packages.${system}."hermes-agent".overrideAttrs (old: {
    postInstall = old.postInstall + ''
      cp -r ${old.src}/plugins $out/share/hermes/plugins
    '';

    makeWrapperArgs = old.makeWrapperArgs ++ [
      "--set"
      "HERMES_BUNDLED_PLUGINS"
      "${placeholder "out"}/share/hermes/plugins"
    ];
  });
}
