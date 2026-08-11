# Detective

Realtime investigation game built with Phoenix, LiveSvelte, Tailwind CSS, and PostgreSQL.

## Local development

1. Start PostgreSQL with `docker compose -f docker-compose.dev.yml up -d`.
2. Run `mix setup` to install dependencies, migrate, seed the original cases, and build assets.
3. Start Phoenix with `mix phx.server` or `iex -S mix phx.server`.

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Run the project gate with `mix precommit`. Run Svelte tests separately with
`npm run test:ui -- --maxWorkers=2`.

## Production release

Build the release image:

```sh
docker build -t detective:latest .
```

The runtime requires `DATABASE_URL`, `SECRET_KEY_BASE`, and `PHX_HOST`.
Apply migrations before starting a new release:

```sh
docker run --rm --env-file .env detective:latest /app/bin/migrate
docker run --rm --env-file .env -p 4000:4000 detective:latest
```

Container probes may use:

- `GET /health/live` for endpoint liveness.
- `GET /health/ready` for endpoint and PostgreSQL readiness.

TLS should terminate at the deployment ingress or load balancer. Configure a
production Swoosh adapter before enabling public registration or magic-link login.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
