#!/usr/bin/env bash
# Cloud Run job alc-migrations-migrate を 1 回実行し、その execution の stdout から
# 「番号と説明」と「pending:」の行だけを $GITHUB_STEP_SUMMARY に出す。
# 使い方: run-job.sh <見出し> [alc-migrate の引数...]   (PROJECT / REGION は環境変数)
# 接続先・project・execution の URL は summary にもログにも出さない。
set -uo pipefail

JOB=alc-migrations-migrate
title=$1
shift

rc=0
if [ $# -gt 0 ]; then
  gcloud run jobs execute "$JOB" --project "$PROJECT" --region "$REGION" \
    --args="$(IFS=,; echo "$*")" --wait --quiet >/dev/null 2>&1 || rc=$?
else
  gcloud run jobs execute "$JOB" --project "$PROJECT" --region "$REGION" \
    --wait --quiet >/dev/null 2>&1 || rc=$?
fi

# concurrency で 1 本ずつなので、いま終わった execution = 最新の 1 件
exec_name=$(gcloud run jobs executions list --job "$JOB" --project "$PROJECT" --region "$REGION" \
  --limit 1 --format='value(metadata.name)' --quiet 2>/dev/null)

lines=
for _ in 1 2 3 4 5 6; do
  lines=$(gcloud logging read \
    "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"$JOB\" AND labels.\"run.googleapis.com/execution_name\"=\"$exec_name\"" \
    --project "$PROJECT" --freshness=1h --order=asc --format='value(textPayload)' --quiet 2>/dev/null |
    grep -E '^[0-9]+ |^pending: |^Migrations completed successfully$' || true)
  [ -n "$lines" ] && break
  sleep 10
done

{
  echo "### $title (exit $rc)"
  echo '```'
  echo "$lines"
  echo '```'
} >>"$GITHUB_STEP_SUMMARY"
echo "$title: exit $rc"
exit "$rc"
