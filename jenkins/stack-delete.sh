#!/bin/bash

set -e

source ~/.openrc

heat stack-delete rpc-${CLUSTER_PREFIX}
