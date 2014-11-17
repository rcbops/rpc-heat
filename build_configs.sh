#!/bin/bash

cat all.sh controller_all.sh controller_primary.sh > config_controller_primary.sh
cat all.sh controller_all.sh > config_controller_other.sh
cat all.sh compute_all.sh > config_compute_all.sh
