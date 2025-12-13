#!/bin/bash

set -e

SETUP_DIR=kube-state/dev/

chmod +x $SETUP_DIR/setup.sh

./$SETUP_DIR/setup.sh

