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
}
