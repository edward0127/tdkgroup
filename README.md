# TDK Group Rails Website

Bilingual Rails website with CMS-backed public pages, admin draft editing,
Active Storage image assets, a contact form, sitemap, and robots controls.

## Local Setup

Install dependencies and prepare the database:

```sh
bundle install
bundle exec rails db:prepare
bundle exec rails db:seed
```

Run the app:

```sh
bin/rails server
```

Run checks:

```sh
bundle exec rails test
bundle exec rails zeitwerk:check
```

## Environment

Use `.env.example` as the safe placeholder reference. Do not commit a real
`.env`, `config/master.key`, local SQLite files, or storage uploads.
For Docker Compose production, copy `.env.prod.example` to `.env.prod` on the
server and fill real values there.

Important production variables:

- `APP_HOST`: host used by mailer URL helpers.
- `CONTACT_RECIPIENT_EMAIL`: contact form recipient. If unset, the app falls
  back to `info@tdkgroup.com.au`.
- `SMTP_ADDRESS` and related `SMTP_*`: optional SMTP delivery settings. When
  SMTP is not configured, local boot and page rendering still work.
- `ACTIVE_STORAGE_SERVICE`: defaults to `local`; can be set to `amazon` when
  S3 credentials and bucket env vars are configured.
- `PUBLIC_UPLOAD_ASSET_HOST`: optional public host used only for S3-backed CMS
  uploads.

## Production Storage Notes

Production SQLite paths are env-driven and default to persistent `/data` paths:

- `/data/production.sqlite3`
- `/data/production_cache.sqlite3`
- `/data/production_queue.sqlite3`
- `/data/production_cable.sqlite3`

Active Storage `local` uses Rails `storage/`. For production with local storage,
mount that directory persistently. S3 can be enabled later by setting
`ACTIVE_STORAGE_SERVICE=amazon` plus the AWS env vars in `.env.example`.

## Docker Compose Deployment

This app is prepared for the same single-container Compose deployment pattern
used by the Juicy Dumplings site.

Local release command:

```sh
./script/deploy_production.sh --auto-commit "Deploy TDK site"
```

First server setup, done manually:

```sh
mkdir -p /var/tdkgroup
git clone git@github.com:edward0127/tdkgroup.git /var/tdkgroup
cd /var/tdkgroup
cp .env.prod.example .env.prod
# edit .env.prod with real secrets
docker login ghcr.io
RUN_SEED=1 ./script/deploy.sh deploy
```

Normal server redeploy:

```sh
./script/deploy.sh deploy
```

Useful server commands:

```sh
./script/deploy.sh logs
./script/deploy.sh status
./script/deploy.sh restart
./script/deploy.sh seed
./script/deploy.sh down
```

The Compose service is `web`, the container is `tdkgroup_site`, and the app is
bound to `127.0.0.1:3014` on the host. The Dockerfile exposes port `80`, so
Compose maps `127.0.0.1:3014:80`.

The current Ubuntu 20.04 production host uses an older Docker/seccomp stack
where Ruby/Rails can fail during boot with `ThreadError: can't create Thread:
Operation not permitted`. The production Compose service therefore sets
`security_opt: seccomp=unconfined` so Rails can create threads reliably on that
host.

DNS and reverse proxy are separate deployment steps. Create DNS for
`tdkgroup.tudouke.com` pointing to the server IP, then configure the existing
server reverse proxy to route `tdkgroup.tudouke.com` to
`http://127.0.0.1:3014`. Do not place reverse proxy config in this app repo.
