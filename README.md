# erambox

**Deployment scaffolder + config-as-code for a generic self-hosted GRC
(Governance / Risk / Compliance) web stack.**

erambox turns a small env-style config into a reproducible, hardened
`docker-compose.yml` plus app / database / reverse-proxy config files. It is a
**generic** GRC stack scaffolder — a web app, a database, and a TLS-terminating
reverse proxy — not tied to any specific vendor's proprietary files. You bring
the container images; erambox generates the wiring.

- **generate** — render `docker-compose.yml` + `config/app.conf` +
  `config/db-init.sql` + `config/proxy.conf` from your config, with `dev` and
  `prod` profiles.
- **validate** — check required vars, port validity, host port conflicts, and
  prod hardening rules (TLS required, no default secrets, real hostname).
  Exits non-zero on any error.
- **healthcheck** — probe the stack's health endpoints, or list the target
  URLs with `--dry-run` (no network).

Pure Bash. Modular sourced libraries under `lib/`. No `envsubst` dependency —
templating is done in pure bash via `{{KEY}}` placeholders.

Maintainer: **Cognis Digital**
License: **COCL 1.0**

---

## Requirements

- Bash 4.3+ (associative arrays + namerefs).
- For non-dry-run `healthcheck`: `curl` or `wget`.
- Docker / Docker Compose only at *deploy* time — erambox itself never calls
  Docker, and the test suite needs neither Docker nor the network.

## Quick start

```sh
# Validate the bundled dev example
./erambox.sh validate --config examples/grc.env

# Generate a dev stack into ./out
./erambox.sh generate --config examples/grc.env --profile dev --out ./out

# List the health-probe targets without touching the network
./erambox.sh healthcheck --config examples/grc.env --dry-run

# Generate a hardened prod stack
./erambox.sh generate --config examples/grc-prod.env --profile prod --out ./out-prod
```

Then, at deploy time:

```sh
cd ./out && docker compose up -d
```

## Commands

### generate

```
erambox.sh generate --config <file> --profile dev|prod --out <dir> [--force]
```

Renders, into `<dir>`:

| File                    | Purpose                                            |
|-------------------------|----------------------------------------------------|
| `docker-compose.yml`    | app + db + proxy services, volumes, network        |
| `config/app.conf`       | generic GRC app configuration                      |
| `config/db-init.sql`    | idempotent bootstrap schema (controls/risks/policies) |
| `config/proxy.conf`     | reverse-proxy vhost (HTTP in dev, TLS in prod)     |

`--force` overwrites a non-empty output directory. generate refuses to run on
a config that fails `validate`.

**Profile differences**

| Aspect            | `dev`                          | `prod`                                   |
|-------------------|--------------------------------|------------------------------------------|
| App host port     | published (`APP_PORT`)         | not published (internal `expose` only)   |
| DB host port      | optional (`DB_PORT`)           | not published                            |
| Proxy ports       | HTTP only                      | HTTP (301 → HTTPS) **and** HTTPS         |
| TLS               | off                            | required; cert/key mounted into proxy    |
| Proxy hardening   | basic                          | HSTS, `nosniff`, `X-Frame-Options`, etc. |
| Secure cookies    | off                            | on                                       |

### validate

```
erambox.sh validate --config <file> [--profile dev|prod]
```

Exits **non-zero** on any error. Checks:

- Required vars present (`APP_NAME`, `APP_IMAGE`, `APP_PORT`, `DB_*`,
  `PROXY_IMAGE`, `PROXY_HTTP_PORT`).
- Ports are valid integers in `1..65535`.
- No two services publish the same **host** port.
- `prod`: `TLS_ENABLED=true` with `TLS_CERT_PATH`, `TLS_KEY_PATH`,
  `PROXY_HTTPS_PORT`; a non-empty `APP_SECRET_KEY`; a non-`localhost`
  `PUBLIC_HOSTNAME`; and a strong, non-default `DB_PASSWORD`.

Unknown keys produce warnings, not errors.

### healthcheck

```
erambox.sh healthcheck --config <file> [--dry-run] [--profile dev|prod]
```

Resolves targets from the config and probes them. With `--dry-run`, prints
`label<TAB>url` lines and makes no network calls. In `dev` the targets are the
directly-published app and the HTTP proxy; in `prod` they are the HTTPS proxy
(and the HTTP redirect endpoint).

## Config reference

See [`examples/grc.env`](examples/grc.env) (dev) and
[`examples/grc-prod.env`](examples/grc-prod.env) (prod). Config files are
parsed line-by-line as `KEY=value` — they are **not** sourced, so no shell code
in a config is ever executed. Values may be single- or double-quoted; `#`
lines and blanks are ignored; an optional leading `export ` is tolerated.

| Key                 | Required | Notes                                             |
|---------------------|:--------:|---------------------------------------------------|
| `ERAMBOX_PROFILE`   |          | `dev` (default) or `prod`; CLI `--profile` wins   |
| `APP_NAME`          |   yes    | compose project + network name                    |
| `APP_IMAGE`         |   yes    | web app container image                           |
| `APP_PORT`          |   yes    | host port (dev) / logical port                    |
| `APP_INTERNAL_PORT` |          | in-container listen port (default `8080`)         |
| `APP_SECRET_KEY`    | prod     | app signing secret                                |
| `DB_IMAGE`          |   yes    | database image (default `postgres:16-alpine`)     |
| `DB_NAME` / `DB_USER` / `DB_PASSWORD` | yes | database credentials                |
| `DB_PORT`           |          | publish DB on host (dev convenience)              |
| `PROXY_IMAGE`       |   yes    | reverse-proxy image (default `nginx:1.27-alpine`) |
| `PROXY_HTTP_PORT`   |   yes    | host HTTP port for the proxy                      |
| `PROXY_HTTPS_PORT`  | prod     | host HTTPS port for the proxy                     |
| `TLS_ENABLED`       | prod     | must be `true` in prod                            |
| `TLS_CERT_PATH` / `TLS_KEY_PATH` | prod | host paths mounted into the proxy      |
| `PUBLIC_HOSTNAME`   | prod     | non-`localhost` in prod                           |
| `HEALTH_PATH`       |          | health endpoint path (default `/health`)          |

## Layout

```
erambox/
├── erambox.sh              # CLI entrypoint
├── lib/
│   ├── common.sh           # logging, arg helpers, port/dir utils
│   ├── config.sh           # safe KEY=value parser + defaults
│   ├── template.sh         # pure-bash {{KEY}} renderer
│   ├── validate.sh         # config validation + `validate` command
│   ├── generate.sh         # templates + `generate` command
│   └── healthcheck.sh      # target resolution + `healthcheck` command
├── examples/
│   ├── grc.env             # dev example
│   └── grc-prod.env        # prod example
├── tests/
│   └── run.sh              # self-contained suite (no Docker, no network)
└── .github/workflows/ci.yml
```

## Tests

```sh
bash tests/run.sh
```

The runner asserts the compose contains all three services, the prod profile
adds TLS + proxy hardening, validation passes on the examples and fails on
broken configs (missing var, port conflict, prod-without-TLS), and the
healthcheck dry-run lists the right targets. It exits non-zero on any failure.

## Scope

Defensive / deployment tooling only. erambox generates configuration and
scaffolding; it does not embed or redistribute any third party's proprietary
application code or config.

---

License: COCL 1.0
