#!/bin/bash

log()
{
    local MESSAGE_LEVEL=$1
    local MESSAGE_CONTENT=$2
    local TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S")

    echo "${TIMESTAMP} - ${MESSAGE_LEVEL} - ${MESSAGE_CONTENT}"
}

METADATA_FILE=$1

if [ ! -f "${METADATA_FILE}" ]; then
    log "ERROR" "Configuration file not found"
    exit -1
fi

SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd -P)

. ${SCRIPT_PATH}/.env

# Remove the comments from the metadata
# Supported comments: Only one-line comments /* ... */ and //
METADATA_JQ=$(cat "${METADATA_FILE}" | grep --extended-regexp --invert-match '^\s*/\*.*\*/\s*$' | grep --extended-regexp --invert-match '^\s*//.*$' | jq --compact-output)

if [[ ${DRY_RUN} -eq "1" ]]
then
    log "DEBUG" "HTTP_PROXY=${HTTP_PROXY}"
    log "DEBUG" "TOKEN=${TOKEN}"
    log "DEBUG" "NODES_LIVE_DELAY=${NODES_LIVE_DELAY}"
    log "DEBUG" "METADATA_JQ=${METADATA_JQ}"
fi

##############
# Data nodes #
##############

NODES_DATA_COUNT=$(echo "${METADATA_JQ}" | jq '[.nodes[] | select(.roles | test("d"))] | length')

if [[ ${NODES_DATA_COUNT} -lt 1 ]]
then
    log "ERROR" "There must be at least 1 data node"
    exit -1
fi

for NODE in $(seq 1 ${NODES_DATA_COUNT})
do
    log "INFO" "Start data node ${NODE}"
    SQL_CMD=$(minijinja-cli "${SCRIPT_PATH}/node_data.sql2" ${METADATA_FILE} --format json --define node_num=${NODE} --define base_path="${SCRIPT_PATH}/.." --define token=${TOKEN} --define http_proxy="${HTTP_PROXY}" | tr '\n' ' ')

    DATA_SOURCE_TYPE=$(echo "${METADATA_JQ}" | jq --raw-output ".nodes[${NODE}-1].data_source_type//\"csv\"")

    if [[ "${DATA_SOURCE_TYPE}" == "db" ]]
    then
        # The DuckDB database must be located under the folder `data`
        DATABASE="${SCRIPT_PATH}/../data/"$(echo "${METADATA_JQ}" | jq --raw-output ".nodes[${NODE}-1].data_source")
    fi

    CMD="duckdb ${DATABASE} -cmd \"${SQL_CMD}\""

    if [[ ${DRY_RUN} -eq "1" ]]
    then
        log "DEBUG" "${CMD}"
    else
        screen -dmS "Data Node ${NODE}" bash -c "${CMD}"
    fi
done

#####################
# Coordination node #
#####################

NODES_COUNT=$(echo "${METADATA_JQ}" | jq '.nodes | length')

if [[ ${NODES_COUNT} -gt 1 ]]
then
    log "INFO" "Start coordination node"
    SQL_CMD=$(minijinja-cli "${SCRIPT_PATH}/node_coord.sql2" ${METADATA_FILE} --format json --define base_path="${SCRIPT_PATH}/.." --define token=${TOKEN} --define http_proxy="${HTTP_PROXY}" | tr '\n' ' ')

    if [[ ${DRY_RUN} -eq "1" ]]
    then
        log "DEBUG" "${SQL_CMD}"
    else
        screen -dmS "Coord Node" bash -c "duckdb -cmd \"${SQL_CMD}\""
    fi
else
    log "INFO" "Single node mode (no coordination node required)"
fi

###############
# Client node #
###############

log "INFO" "Start client node"

if [[ ${DRY_RUN} -ne "1" ]]
then
    # Wait few seconds to let the nodes to be up and listening
    sleep ${NODES_LIVE_DELAY}
fi

SQL_CMD=$(minijinja-cli "${SCRIPT_PATH}/node_client.sql2" ${METADATA_FILE} --format json --define base_path="${SCRIPT_PATH}/.." --define token=${TOKEN} --define http_proxy="${HTTP_PROXY}" | tr '\n' ' ')

if [[ ${DRY_RUN} -eq "1" ]]
then
    log "DEBUG" "${SQL_CMD}"
else
    duckdb -cmd "${SQL_CMD}"
fi
