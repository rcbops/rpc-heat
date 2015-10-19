#!/bin/bash

cat all_header.sh controller_all.sh controller_primary.sh all_footer.sh > config_controller_primary.sh
cat all_header.sh controller_all.sh all_footer.sh > config_controller_other.sh
cat all_header.sh compute_all.sh all_footer.sh > config_compute_all.sh
cat all_header.sh ceph_all.sh all_footer.sh > config_ceph_all.sh
