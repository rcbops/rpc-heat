#!/bin/bash

set -e

CLOUD_CREDS=${CLOUD_CREDS:-"~/.openrc"}
source ${CLOUD_CREDS}

heat stack-delete rpc-${CLUSTER_PREFIX}
