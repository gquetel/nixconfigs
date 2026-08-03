{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  alembic,
  asgiref,
  authlib,
  cachetools,
  fastapi,
  flask,
  gunicorn,
  httpx,
  python-dotenv,
  requests,
  sqlalchemy,
  uvicorn,
}:

buildPythonPackage rec {
  pname = "mlflow-oidc-auth";
  version = "7.3.1";
  pyproject = true;

  src = fetchPypi {
    pname = "mlflow_oidc_auth";
    inherit version;
    hash = "sha256-qbI4sHF/BJbPA2AHi2XMmE5q+J/0lKPRWOX//uEXtRU=";
  };

  build-system = [ setuptools ];

  # __init__.py reads the version from this env var, else falls back to a
  # dev0 placeholder that fails nixpkgs' metadata-version check.
  env.MLFLOW_OIDC_AUTH_VERSION = version;

  # mlflow and mlflow-skinny are provided by the surrounding python env.
  pythonRemoveDeps = [
    "mlflow"
    "mlflow-skinny"
  ];

  # The pinned unstable nixpkgs ships slightly older or newer versions than
  # what pyproject.toml declares; packages are compatible at runtime.
  pythonRelaxDeps = [
    "sqlalchemy"
    "uvicorn"
    "fastapi"
    "asgiref"
    "gunicorn"
  ];

  dependencies = [
    alembic
    asgiref
    authlib
    cachetools
    fastapi
    flask
    gunicorn
    httpx
    python-dotenv
    requests
    sqlalchemy
    uvicorn
  ];

  pythonImportsCheck = [ "mlflow_oidc_auth" ];
  doCheck = false;

  meta = with lib; {
    description = "OIDC auth plugin for MLflow";
    homepage = "https://github.com/mlflow-oidc/mlflow-oidc-auth";
    license = licenses.asl20;
  };
}
