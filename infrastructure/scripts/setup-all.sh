#!/bin/bash

set -e

minikube start --cpus=4 --memory=12288

chmod +x install-monitoring.sh
chmod +x install-services.sh

./install-monitoring.sh
./install-services.sh

minikube addons enable ingress
