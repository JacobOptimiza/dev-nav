#!/bin/bash
set -euo pipefail

cd "$SRC/dev-nav"
cargo fuzz build -O --sanitizer address
cp fuzz/target/x86_64-unknown-linux-gnu/release/config_tsv_parser "$OUT/"
