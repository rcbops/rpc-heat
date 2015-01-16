#!/bin/bash

set -e

source ~/.openrc

heat stack-delete rpc-jenkins-${BUILD_NUMBER}
