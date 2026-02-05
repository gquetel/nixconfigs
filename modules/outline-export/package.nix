{
  lib,
  buildGoModule,
  fetchFromGitHub,
  # Injected into the binary via ldflags, consumed by main.go:26-29.
  gitRev ? "0ad6a3b",
  gitVersion ? "1.2.0",
}:

# rec is needed because ldflags references version.
buildGoModule rec {
  pname = "outline-export";
  version = gitVersion;

  src = fetchFromGitHub {
    owner = "lrstanley";
    repo = "outline-export";
    rev = gitRev;
    hash = "sha256-OTB3VEf1R60OQCmWgpa/sScMkU/G+JC0QF65dhO4b/w=";
  };

  # Hash of Go module dependencies (go.mod:5-13). Update when go.mod/go.sum change.
  vendorHash = "sha256-iUDgb+e+cmMI8oBPGmINVFM/k81hnr8AQvPJzgGCb/Q=";

  # Makefile:41 (CGO_ENABLED=0)
  env.CGO_ENABLED = "0";

  # Makefile:44 (-tags=netgo,osusergo,static_build)
  tags = [
    "netgo" # pure-Go network stack
    "osusergo" # pure-Go user/group lookup
    "static_build"
  ];

  # Makefile:43 (-ldflags '-d -s -w -extldflags=-static')
  # -installsuffix netgo (Makefile:45) is obsolete since Go 1.10, omitted.
  # -trimpath (Makefile:46) is enabled by buildGoModule by default, omitted.
  ldflags = [
    "-d" # disable DWARF generation
    "-s" # strip symbol table
    "-w" # strip debug info
    "-extldflags=-static"
    # main.go:26-29 — linker-overridable version variables.
    "-X main.version=${version}"
    "-X main.commit=${gitRev}"
    "-X main.date=1970-01-01" # epoch for reproducibility
  ];

  meta = {
    description = "CLI tool to export all collections from an Outline wiki instance";
    homepage = "https://github.com/lrstanley/outline-export";
    license = lib.licenses.mit;
    mainProgram = "outline-export";
  };
}
