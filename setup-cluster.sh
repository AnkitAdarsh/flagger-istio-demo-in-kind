#!/bin/bash

set -e

kind create cluster --config=single-node-kind-cluster.yaml --name=flagger --image "kindest/node:v1.22.15"

# Calico
kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml
kubectl apply -f ./istio-installation/calico-config.yaml