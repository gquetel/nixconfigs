{ lib
, buildPythonPackage
, fetchPypi
, setuptools
, alembic
, asgiref
, authlib
, cachetools
, fastapi
, flask
, gunicorn
, httpx
, python-dotenv
, requests
, sqlalchemy
, uvicorn
}:

buildPythonPackage rec {
  pname = "mlflow-oidc-auth";
  version = "7.1.0";
  pyproject = true;

  src = fetchPypi {
    pname = "mlflow_oidc_auth";
    inherit version;
    hash = "sha256-YwDfO/9hdcqpEfo48JMdYZpl3Npo7K9ZBfbYOU8b8sk=";
  };

  build-system = [ setuptools ];

  # mlflow and mlflow-skinny are provided by the surrounding python env.
  pythonRemoveDeps = [ "mlflow" "mlflow-skinny" ];

  # The pinned unstable nixpkgs ships slightly older patch versions than
  # what pyproject.toml declares; packages are compatible at runtime.
  pythonRelaxDeps = [ "sqlalchemy" "uvicorn" "fastapi" "asgiref" ];

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
