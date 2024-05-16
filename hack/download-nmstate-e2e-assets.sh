#!/bin/bash 
set -xeu -o pipefail

tag=$1
nmstate_dir=$2
output_dir=$3
(
    cd $nmstate_dir
    mkdir -p $output_dir
    for dump_asset in $(gh release view $tag --json assets --jq '.assets[] |select(.name | contains("dump")).url'); do 
        curl --output-dir $output_dir -LO $dump_asset
    done

)
(
    cd $output_dir
    for zip in $(ls *.zip); do
        unzip $zip
    done
)
