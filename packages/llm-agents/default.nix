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
}
