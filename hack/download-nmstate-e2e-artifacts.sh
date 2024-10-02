#!/bin/bash 
set -xeu -o pipefail

tag=$1
nmstate_dir=$2
output_dir=$3

(
    cd $nmstate_dir
    # Get the SHA from last commit before tag
    sha=$(git rev-list -n 1 $tag~1)
    if [ -z "${sha}" ]; then
        echo "missing last commit before release"
        exit 1
    fi
    # Get the first commit from the PR that generated the tag SHA
    pr_sha=$(gh pr list --state merged --search $sha --json commits  |jq -r .[-1].commits[-1].oid)
    if [ -z "${pr_sha}" ]; then
        echo "missing PR from last commit"
        exit 1
    fi

    # Take the first run from that PR commit
    run_id=$(gh run list -c $pr_sha --json databaseId -q ".[-1].databaseId")
    if [ -z "${run_id}" ]; then
        echo "missing run ID from last PR"
        exit 1
    fi

    # Download artifacts from that run
    if ! gh run download -D $output_dir -p "*dump*" $run_id; then
        echo "failed downloading artifacts"
        gh run view $run_id
        exit 1
    fi
)
