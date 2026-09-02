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

  # Agent CLI plus prebuilt web dashboard.
  "hermes-agent" = llmAgents.packages.${system}."hermes-agent".overrideAttrs (old: {
    postInstall = old.postInstall + ''
      # Make the agent's thread pool work on Python 3.14; see the appended file.
      pool=$(echo "$out"/lib/python*/site-packages/tools/daemon_pool.py)
      test -f "$pool" || { echo "daemon_pool.py not found; drop this patch"; exit 1; }
      cat ${./daemon-pool-compat.py} >> "$pool"

      # Stop the CLI from rewriting the NixOS-owned unit; see the appended file.
      gw=$(echo "$out"/lib/python*/site-packages/hermes_cli/gateway.py)
      test -f "$gw" || { echo "hermes_cli/gateway.py not found; drop this patch"; exit 1; }
      cat ${./nixos-unit-compat.py} >> "$gw"
    '';
  });
}
