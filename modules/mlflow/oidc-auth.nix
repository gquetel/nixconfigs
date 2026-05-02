{ lib
, buildPythonPackage
, fetchPypi
, setuptools
, alembic
, authlib
, cachelib
, flask
, flask-caching
, flask-session
, gunicorn
, python-dotenv
, requests
, sqlalchemy
}:

# Pinned to 5.7.0 — latest release compatible with mlflow 3.3.1 (the
# version in the repo's pinned nixpkgs). 6.x requires mlflow >= 3.8.1.
buildPythonPackage rec {
  pname = "mlflow-oidc-auth";
  version = "5.7.0";
  pyproject = true;

  src = fetchPypi {
    pname = "mlflow_oidc_auth";
    inherit version;
    hash = "sha256-TtrlKxqix13e8n8SL9U0XIin8CmNcJPEpIEMuuoJb6M=";
  };

  build-system = [ setuptools ];

  # mlflow-skinny is not packaged in nixpkgs; we ship full mlflow in the
  # surrounding python env, which provides the same modules at runtime.
  pythonRemoveDeps = [ "mlflow-skinny" ];

  dependencies = [
    alembic
    authlib
    cachelib
    flask
    flask-caching
    flask-session
    gunicorn
    python-dotenv
    requests
    sqlalchemy
  ];

  pythonImportsCheck = [ "mlflow_oidc_auth" ];
  doCheck = false;

  meta = with lib; {
    description = "OIDC auth plugin for MLflow";
    homepage = "https://github.com/mlflow-oidc/mlflow-oidc-auth";
    license = licenses.asl20;
  };
}
