#!/bin/bash

SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd -P)

duckdb "${SCRIPT_PATH}/big.db" -f "${SCRIPT_PATH}/build_big.sql"
