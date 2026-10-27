{
  buildPythonPackage,
  fetchPypi,
  aiohttp,
  aiohttp-retry,
  pydantic,
  python-dateutil,
  typing-extensions,
  urllib3,
  yarl,
}:
# Python client of the Hindsight API, required by Hermes' Hindsight memory
# provider.
buildPythonPackage rec {
  pname = "hindsight-client";
  version = "1.1.0";
  format = "wheel";

  src = fetchPypi {
    pname = "hindsight_client";
    inherit version format;
    dist = "py3";
    python = "py3";
    hash = "sha256-fCV2G5cxpsMimGR56yGYfiIQc7MT3KwStMv2yC2covI=";
  };

  dependencies = [
    aiohttp
    aiohttp-retry
    pydantic
    python-dateutil
    typing-extensions
    urllib3
    yarl
  ];

  pythonImportsCheck = [
    "hindsight_client"
    "hindsight_client_api"
  ];
}
