#!/usr/bin/env bash
set -eu -o pipefail

data='{'\
'  "ref":"master",'\
'  "inputs": {'\
'    "github_ref":"'"${GITHUB_REF}"'",'\
'    "github_sha":"'"${GITHUB_SHA}"'"'\
'  }'\
'}'

curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token ${PAT_TOKEN}" \
  https://api.github.com/repos/"${REPO_USERNAME}"/"${REPO_NAME}"/actions/workflows/build.yml/dispatches \
  -d "${data}"
