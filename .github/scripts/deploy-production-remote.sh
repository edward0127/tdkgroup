#!/usr/bin/env bash
# GitHub Actions production cutover for TDK Group.
# The workflow fetches this exact file from APP_REVISION and passes the immutable
# IMAGE_REF produced by the same run, keeping source, Compose model and image aligned.
set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-/var/tdkgroup}"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/edward0127/tdkgroup}"
CONTAINER_NAME="${CONTAINER_NAME:-tdkgroup_site}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-tdkgroup}"
DATA_VOLUME="${DATA_VOLUME:-${COMPOSE_PROJECT}_tdkgroup_data}"
ENV_FILE="${ENV_FILE:-${PROJECT_DIR}/.env.prod}"
DEPLOY_DIR="${DEPLOY_DIR:-${PROJECT_DIR}/.deploy}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/tdkgroup}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-http://127.0.0.1:3014/up}"
PUBLIC_HEALTHCHECK_URL="${PUBLIC_HEALTHCHECK_URL:-https://tdkgroup.tudouke.com/up}"
READY_TRIES="${READY_TRIES:-30}"
READY_SLEEP="${READY_SLEEP:-2}"
LOCK_WAIT_SECONDS="${LOCK_WAIT_SECONDS:-600}"

IMAGE_REF="${IMAGE_REF:-}"
APP_REVISION="${APP_REVISION:-}"
GH_RUN_ID="${GH_RUN_ID:-manual}"

PHASE="startup"
CUTOVER_STARTED=0
DEPLOY_ACCEPTED=0
CURRENT_IMAGE_REF=""
CURRENT_IMAGE_ID=""
CURRENT_REVISION=""
MODEL_FILE=""
PREVIOUS_MODEL_FILE=""
BACKUP_DIR=""
BACKUP_CREATED=0
DATABASE_RESTORE_SAFE=1

log() { printf '[%s] %s\n' "$PHASE" "$*"; }
fail() { printf 'ERROR [%s] %s\n' "$PHASE" "$*" >&2; return 1; }

is_full_commit() {
  local value="$1"
  [[ "$value" =~ ^[0-9a-f]{40}$ ]]
}

is_immutable_image() {
  local digest
  case "$1" in
    "${IMAGE_NAME}"@sha256:*) digest="${1#*@sha256:}" ;;
    *) return 1 ;;
  esac
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]]
}

is_safe_run_id() {
  [[ "$1" =~ ^[A-Za-z0-9._-]{1,128}$ ]]
}

compose_with() {
  local compose_file="$1"
  local image_ref="$2"
  local revision="$3"
  shift 3

  TDKGROUP_IMAGE="$image_ref" \
  TDKGROUP_ENV_FILE="$ENV_FILE" \
  APP_REVISION="$revision" \
    docker compose \
      --project-name "$COMPOSE_PROJECT" \
      --project-directory "$PROJECT_DIR" \
      -f "$compose_file" \
      "$@"
}

target_compose() {
  compose_with "$MODEL_FILE" "$IMAGE_REF" "$APP_REVISION" "$@"
}

previous_compose() {
  compose_with "$PREVIOUS_MODEL_FILE" "$CURRENT_IMAGE_REF" "$CURRENT_REVISION" "$@"
}

container_exists() {
  docker inspect "$CONTAINER_NAME" >/dev/null 2>&1
}

healthcheck() {
  local attempt
  for attempt in $(seq 1 "$READY_TRIES"); do
    if curl -fsS "$HEALTHCHECK_URL" >/dev/null; then
      log "healthcheck passed after ${attempt} attempt(s)"
      return 0
    fi
    if [[ "$attempt" -lt "$READY_TRIES" ]]; then
      sleep "$READY_SLEEP"
    fi
  done
  fail "healthcheck failed: ${HEALTHCHECK_URL}"
}

public_healthcheck() {
  local attempt
  for attempt in $(seq 1 "$READY_TRIES"); do
    if curl -fsS "$PUBLIC_HEALTHCHECK_URL" >/dev/null; then
      log "public healthcheck passed after ${attempt} attempt(s)"
      return 0
    fi
    if [[ "$attempt" -lt "$READY_TRIES" ]]; then
      sleep "$READY_SLEEP"
    fi
  done
  fail "public healthcheck failed: ${PUBLIC_HEALTHCHECK_URL}"
}

database_smoke() {
  docker exec "$CONTAINER_NAME" bin/rails runner \
    'value = ActiveRecord::Base.connection.select_value("SELECT 1"); abort "database smoke failed" unless value.to_i == 1'
  docker exec "$CONTAINER_NAME" sh -c 'test -w /data && test -w /rails/storage'
  log "database and writable-volume smoke checks passed"
}

read_current_state() {
  if ! container_exists; then
    log "no existing application container was found"
    return 0
  fi

  CURRENT_IMAGE_REF="$(docker inspect "$CONTAINER_NAME" --format '{{.Config.Image}}')"
  CURRENT_IMAGE_ID="$(docker inspect "$CONTAINER_NAME" --format '{{.Image}}')"
  CURRENT_REVISION="$(docker image inspect "$CURRENT_IMAGE_ID" --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' 2>/dev/null || true)"
  log "current image id: ${CURRENT_IMAGE_ID}"
  if is_full_commit "$CURRENT_REVISION"; then
    log "current revision: ${CURRENT_REVISION}"
  else
    CURRENT_REVISION=""
    log "current image predates revision labels"
  fi
}

prepare_previous_model() {
  [[ -n "$CURRENT_IMAGE_REF" ]] || return 0

  local source_revision
  source_revision="$CURRENT_REVISION"
  if ! is_full_commit "$source_revision" || ! git cat-file -e "${source_revision}^{commit}" 2>/dev/null; then
    source_revision="$(git rev-parse HEAD)"
  fi

  PREVIOUS_MODEL_FILE="${DEPLOY_DIR}/docker-compose-previous-${GH_RUN_ID}.yml"
  local previous_tmp="${PREVIOUS_MODEL_FILE}.tmp.$$"
  git show "${source_revision}:docker-compose.yml" > "$previous_tmp"
  grep -q 'web:' "$previous_tmp" || fail "previous Compose model does not contain the web service"
  chmod 600 "$previous_tmp"
  mv -f "$previous_tmp" "$PREVIOUS_MODEL_FILE"
  log "saved previous Compose model from ${source_revision}"
}

target_is_older_than_current() {
  [[ -n "$CURRENT_REVISION" ]] || return 1
  [[ "$CURRENT_REVISION" != "$APP_REVISION" ]] || return 1
  git cat-file -e "${CURRENT_REVISION}^{commit}" 2>/dev/null || return 1
  git merge-base --is-ancestor "$APP_REVISION" "$CURRENT_REVISION"
}

backup_sqlite_databases() {
  local stamp short_revision safe_run
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  short_revision="${APP_REVISION:0:12}"
  safe_run="${GH_RUN_ID//[^A-Za-z0-9._-]/_}"
  BACKUP_DIR="${BACKUP_ROOT}/${stamp}-${short_revision}-${safe_run}"
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"

  if ! docker volume inspect "$DATA_VOLUME" >/dev/null 2>&1; then
    log "data volume does not exist; treating this as a fresh install"
    return 0
  fi

  log "creating SQLite backups in ${BACKUP_DIR}"
  docker run --rm \
    --user 0 \
    -v "${DATA_VOLUME}:/data" \
    -v "${BACKUP_DIR}:/backup" \
    --entrypoint /bin/bash \
    "$IMAGE_REF" \
    -Eeuo pipefail -c '
      shopt -s nullglob
      databases=(/data/*.sqlite3)
      if (( ${#databases[@]} == 0 )); then
        exit 0
      fi
      for database in "${databases[@]}"; do
        name="${database##*/}"
        sqlite3 "$database" ".timeout 30000" ".backup /backup/${name}"
        test -s "/backup/${name}"
      done
    '
  chmod -R go-rwx "$BACKUP_DIR"

  if compgen -G "${BACKUP_DIR}/*.sqlite3" >/dev/null; then
    BACKUP_CREATED=1
  elif [[ -n "$CURRENT_IMAGE_ID" ]]; then
    fail "running production container had no SQLite databases to back up"
  else
    log "data volume is empty; treating this as a fresh install"
    return 0
  fi

  log "SQLite backup completed"
}

restore_sqlite_databases() {
  [[ "$BACKUP_CREATED" == "1" ]] || return 0
  docker volume inspect "$DATA_VOLUME" >/dev/null

  log "restoring SQLite databases from ${BACKUP_DIR}"
  docker run --rm \
    --user 0 \
    -v "${DATA_VOLUME}:/data" \
    -v "${BACKUP_DIR}:/backup:ro" \
    --entrypoint /bin/bash \
    "$IMAGE_REF" \
    -Eeuo pipefail -c '
      shopt -s nullglob
      backups=(/backup/*.sqlite3)
      (( ${#backups[@]} > 0 ))
      rm -f /data/*.sqlite3 /data/*.sqlite3-wal /data/*.sqlite3-shm /data/*.sqlite3-journal
      for backup in "${backups[@]}"; do
        name="${backup##*/}"
        cp -p "$backup" "/data/${name}"
      done
      chown 1000:1000 /data/*.sqlite3
    '
  log "SQLite restore completed"
}

verify_target_image() {
  local expected_id running_id running_revision configured_ref
  expected_id="$(docker image inspect "$IMAGE_REF" --format '{{.Id}}')"
  running_id="$(docker inspect "$CONTAINER_NAME" --format '{{.Image}}')"
  configured_ref="$(docker inspect "$CONTAINER_NAME" --format '{{.Config.Image}}')"
  running_revision="$(docker image inspect "$running_id" --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}')"

  [[ "$running_id" == "$expected_id" ]] || fail "running image id does not match the image built by this run"
  [[ "$configured_ref" == "$IMAGE_REF" ]] || fail "container image reference is not the immutable target digest"
  [[ "$running_revision" == "$APP_REVISION" ]] || fail "OCI revision label does not match APP_REVISION"
  log "image digest and OCI revision checks passed"
}

fast_forward_checkout() {
  PHASE="record"
  cd "$PROJECT_DIR"

  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    log "tracked server checkout changes detected; leaving checkout unchanged"
    return 0
  fi

  git checkout -q main
  local checkout_revision
  checkout_revision="$(git rev-parse HEAD)"
  if [[ "$checkout_revision" == "$APP_REVISION" ]]; then
    return 0
  fi

  if git merge-base --is-ancestor "$checkout_revision" "$APP_REVISION"; then
    git merge --ff-only "$APP_REVISION"
  elif git merge-base --is-ancestor "$APP_REVISION" "$checkout_revision"; then
    log "server checkout is already newer; leaving it unchanged"
  else
    log "server checkout diverged; deployed artifact is accepted but checkout was not changed"
  fi
}

write_receipt() {
  local receipt_tmp="${DEPLOY_DIR}/last-success.env.tmp.$$"
  {
    printf 'APP_REVISION=%s\n' "$APP_REVISION"
    printf 'IMAGE_REF=%s\n' "$IMAGE_REF"
    printf 'GH_RUN_ID=%s\n' "$GH_RUN_ID"
    printf 'BACKUP_DIR=%s\n' "$BACKUP_DIR"
    printf 'ACCEPTED_AT_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$receipt_tmp"
  chmod 600 "$receipt_tmp"
  mv -f "$receipt_tmp" "${DEPLOY_DIR}/last-success.env"
}

rollback() {
  [[ "$CUTOVER_STARTED" == "1" && "$DEPLOY_ACCEPTED" != "1" ]] || return 0

  PHASE="rollback"
  if container_exists; then
    docker stop -t 30 "$CONTAINER_NAME" >/dev/null || true
  fi
  if [[ "$DATABASE_RESTORE_SAFE" == "1" ]]; then
    restore_sqlite_databases
  else
    log "preserving the live database because the target may already have accepted requests"
  fi

  [[ -n "$CURRENT_IMAGE_REF" ]] || { log "database was restored but no previous image is available"; return 1; }
  [[ -f "$PREVIOUS_MODEL_FILE" ]] || { log "previous Compose model is unavailable"; return 1; }
  log "restoring previous application image: ${CURRENT_IMAGE_REF}"
  previous_compose up -d --no-deps --force-recreate web
  healthcheck
  database_smoke
  public_healthcheck
  log "application image rollback succeeded; database backup retained at ${BACKUP_DIR}"
}

on_error() {
  local exit_code=$?
  trap - ERR
  if ! rollback; then
    printf 'ERROR [rollback] automatic application rollback failed\n' >&2
  fi
  exit "$exit_code"
}

trap on_error ERR

PHASE="validate"
is_immutable_image "$IMAGE_REF" || fail "IMAGE_REF must be ${IMAGE_NAME}@sha256:<64 lowercase hex>"
is_full_commit "$APP_REVISION" || fail "APP_REVISION must be a full 40-character lowercase commit"
is_safe_run_id "$GH_RUN_ID" || fail "GH_RUN_ID contains unsupported characters"
[[ -d "$PROJECT_DIR/.git" ]] || fail "production Git checkout is missing: ${PROJECT_DIR}"
[[ -f "$ENV_FILE" ]] || fail "production environment file is missing: ${ENV_FILE}"

for command_name in git docker flock curl; do
  command -v "$command_name" >/dev/null 2>&1 || fail "required command is missing: ${command_name}"
done
docker compose version >/dev/null

mkdir -p "$DEPLOY_DIR" "$BACKUP_ROOT"
chmod 700 "$DEPLOY_DIR" "$BACKUP_ROOT"

exec 9>"${DEPLOY_DIR}/production.lock"
log "waiting for production deployment lock"
flock -w "$LOCK_WAIT_SECONDS" 9 || fail "timed out waiting for the production deployment lock"

PHASE="source"
cd "$PROJECT_DIR"
git fetch origin main
git cat-file -e "${APP_REVISION}^{commit}" || fail "APP_REVISION is unavailable in the production checkout"
git merge-base --is-ancestor "$APP_REVISION" origin/main || fail "APP_REVISION is not part of origin/main"

MODEL_FILE="${DEPLOY_DIR}/docker-compose-${APP_REVISION}.yml"
model_tmp="${MODEL_FILE}.tmp.$$"
git show "${APP_REVISION}:docker-compose.yml" > "$model_tmp"
grep -q 'TDKGROUP_IMAGE' "$model_tmp" || fail "target Compose model does not require TDKGROUP_IMAGE"
chmod 600 "$model_tmp"
mv -f "$model_tmp" "$MODEL_FILE"

read_current_state
if target_is_older_than_current; then
  PHASE="stale"
  log "target ${APP_REVISION} is older than deployed ${CURRENT_REVISION}; skipping downgrade"
  exit 0
fi

if [[ "$CURRENT_REVISION" == "$APP_REVISION" && "$CURRENT_IMAGE_REF" == "$IMAGE_REF" ]]; then
  PHASE="verify-existing"
  verify_target_image
  healthcheck
  database_smoke
  public_healthcheck
  fast_forward_checkout
  log "target revision is already healthy in production"
  exit 0
fi

prepare_previous_model

PHASE="pull"
target_compose pull web
target_revision="$(docker image inspect "$IMAGE_REF" --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}')"
[[ "$target_revision" == "$APP_REVISION" ]] || fail "pulled image OCI revision does not match APP_REVISION"

PHASE="maintenance"
CUTOVER_STARTED=1
if container_exists; then
  log "stopping the web container before the final database backup"
  docker stop -t 30 "$CONTAINER_NAME" >/dev/null
fi

PHASE="backup"
backup_sqlite_databases

PHASE="migrate"
target_compose run --rm --no-deps web bin/rails db:prepare

PHASE="preflight"
target_compose run --rm --no-deps web bin/rails runner \
  'value = ActiveRecord::Base.connection.select_value("SELECT 1"); abort "database preflight failed" unless value.to_i == 1'

PHASE="cutover"
# From this point the target can receive real traffic. Never restore the old
# SQLite snapshot automatically after exposure, because that could erase writes.
DATABASE_RESTORE_SAFE=0
target_compose up -d --no-deps --force-recreate web

PHASE="verify"
verify_target_image
healthcheck
database_smoke
public_healthcheck

write_receipt
DEPLOY_ACCEPTED=1
fast_forward_checkout
PHASE="complete"
log "production accepted ${APP_REVISION} using ${IMAGE_REF}"
log "pre-deploy SQLite backup: ${BACKUP_DIR}"
