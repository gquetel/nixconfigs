# Secrets

Secrets are encrypted with [agenix](https://github.com/ryantm/agenix).
[`secrets.nix`](./secrets.nix) lists who can decrypt each file: the hosts that
use it and the admin user keys. Below, we list what each file contains.

## strix

| File                            | Content                                                                         |
| ------------------------------- | ------------------------------------------------------------------------------- |
| `gquetel-strix.age`             | Password hash of gquetel.                                                       |
| `thesis-artefacts.age`          | htpasswd lines (`user:hash`) of thesis-artefacts.gquetel.fr.                    |
| `gitlab-runner.env.age`         | `CI_SERVER_URL`, `CI_SERVER_TOKEN`, given by GitLab when you create the runner. |
| `dex-outline-secret.age`        | Dex client secret of Outline.                                                   |
| `dex-mlflow-secret.age`         | Dex client secret of MLflow.                                                    |
| `mlflow-session-key.age`        | Session key of MLflow.                                                          |
| `plausible-secret-key-base.age` | Secret key base of Plausible.                                                   |
| `hermes-outline-password.age`   | Dex password of the Hermes's Outline account.                                   |
| `restic-strix.pwd.age`          | Restic password of the repository `restic-strix`.                               |
| `restic-strix.env.age`          | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` of the Garage key `restic-strix`.  |

## garmr

| File                         | Content                                                                                                                                                                                                   |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `step-ca.pwd.age`            | Password of the intermediate CA key.                                                                                                                                                                      |
| `grafana-secret-key.age`     | Secret key of Grafana.                                                                                                                                                                                    |
| `plane.env.age`              | `SECRET_KEY`, `LIVE_SERVER_SECRET_KEY`, `POSTGRES_PASSWORD`, `DATABASE_URL`, `RABBITMQ_DEFAULT_PASS`, `AMQP_URL`, `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`. |
| `wazuh-server.env.age`       | `INDEXER_PASSWORD`, `DASHBOARD_PASSWORD`, `API_PASSWORD`.                                                                                                                                                 |
| `dex-wazuh-secret.age`       | Dex client secret of the Wazuh dashboard.                                                                                                                                                                 |
| `backrest.env.age`           | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` of the read-only Garage key `backrest`.                                                                                                                      |
| `dex-backrest-secret.age`    | Dex client secret of the Backrest oauth2-proxy.                                                                                                                                                           |
| `backrest-cookie-secret.age` | Cookie secret of the Backrest oauth2-proxy.                                                                                                                                                               |

## vapula

| File                             | Content                                                                           |
| -------------------------------- | --------------------------------------------------------------------------------- |
| `mullvad-pvkey.age`              | `PRIVATE_KEY` (WireGuard key), `ADDRESS` (comma-separated tunnel addresses).      |
| `dex-hermes-secret.age`          | Dex client secret of the Hermes oauth2-proxy.                                     |
| `hermes-cookie-secret.age`       | Cookie secret of the Hermes oauth2-proxy.                                         |
| `hermes.env.age`                 | Provider API keys and other env variables for Hermes.                             |
| `hermes-plane-token.age`         | Plane API token and other env variables the agent VM needs to reach Plane.        |
| `agent-secrets.env.age`          | Env variables of the agent VM, such as `CLAUDE_CODE_OAUTH_TOKEN`.                 |
| `hindsight.env.age`              | `POSTGRES_PASSWORD`, `HINDSIGHT_API_DATABASE_URL` `HINDSIGHT_API_TENANT_API_KEY`. |
| `hindsight-inference.env.age`    | `HINDSIGHT_API_LLM_API_KEY` of the `inference` LLM backend.                       |
| `hindsight-cp.env.age`           | `HINDSIGHT_CP_DATAPLANE_API_KEY`, equal to `HINDSIGHT_API_TENANT_API_KEY`.        |
| `dex-hindsight-secret.age`       | Dex client secret of the Hindsight Control Plane oauth2-proxy.                    |
| `hindsight-oauth2-proxy.env.age` | `OAUTH2_PROXY_CLIENT_SECRET`, `OAUTH2_PROXY_COOKIE_SECRET`.                       |

## fafnir

| File             | Content                                                             |
| ---------------- | ------------------------------------------------------------------- |
| `garage.env.age` | `GARAGE_RPC_SECRET`, `GARAGE_ADMIN_TOKEN`. |

## All hosts

| File                   | Content                                 |
| ---------------------- | --------------------------------------- |
| `wazuh-authd.pass.age` | Enrolment password of the Wazuh agents. |
