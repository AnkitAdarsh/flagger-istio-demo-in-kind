# Flagger Demo with Istio in a Kind K8s Cluster

Below are the steps to setup a Local Kind k8s Cluster with Istio to demo Canary Deployments using Flagger.

## Prequisites

1. Docker

2. Kind - To Setup Cluster
    ```shell
    brew install kind
    ```
3. Istioctl - To Install Istio
    ```
    https://istio.io/latest/docs/setup/getting-started/#download
    ````
4. Helm3
5. Kuberenetes Version: 1.22.15 - kubectl


## Installation Steps

1. Install a Kind Cluster with mertics server

Use the script, setup-cluster.sh to create a local kind cluster. 

```shell
./setup-cluster.sh
````

The configuration for the kind cluster also contains port mappings as below.
```
extraPortMappings:
      - containerPort: 30000
        hostPort: 80
        listenAddress: "127.0.0.1"
        protocol: TCP
      - containerPort: 30001
        hostPort: 443
        listenAddress: "127.0.0.1"
        protocol: TCP
      - containerPort: 30002
        hostPort: 15021
        listenAddress: "127.0.0.1"
        protocol: TCP
```

This will also install metrics-server in the kube-system namespace. 


2. Install Istio

We will use istioctl and IstioOperator Resource to perform istio insallation. To install Istio use the below command:

```shell
istioctl install -f istio-installation/install-istio.yaml
```

Verify Istio Installation is complete using the below command from your machine:
```shell
curl -sI http://localhost:15021/healthz/ready
```

3. Configure Public Gateway

Once instio is installed, configure an ingress gateway to expose the demo app outside of the mesh.

```shell
kubectl create -f public-gateway-istio.yaml
```

4. Install and configure Prometheus, Grafana and Kiali

To install Prometheus use:
```shell
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.15/samples/addons/prometheus.yaml
```

To port forward Prometheus use:
```shell
kubectl -n istio-system port-forward svc/prometheus 9090:9090
```

To install Grafana use:
```shell
helm upgrade -i flagger-grafana flagger/grafana \
--namespace=istio-system \
--set url=http://prometheus.istio-system:9090 \
--set user=admin \
--set password=change-me
```

To port forward Grafana use:
```shell
kubectl -n istio-system port-forward svc/flagger-grafana 3100:80
```

To install Kiali use:
```shell
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.15/samples/addons/kiali.yaml
```

To port forward Kiali use:
```shell
kubectl port-forward svc/kiali 20001:20001 -n istio-system
```


5. Install Flagger

Create CRD's for Flagger to work:
```shell
kubectl apply -f https://raw.githubusercontent.com/fluxcd/flagger/main/artifacts/flagger/crd.yaml
```

Create Flagger Namespace
```shell
kubectl create ns flagger-system
```

Install Flagger using Helm
``` shell
helm upgrade -i flagger flagger/flagger \
--namespace=flagger-system \
--set crd.create=false \
--set meshProvider=istio \
--set metricsServer=http://prometheus.istio-system:9090
```


6. Setup Sample Application for Demo

Create a Test Namespace and Enable Istio Sidecar Injection
```shell
kubectl create ns test
kubectl label namespace test istio-injection=enabled
```

Install the PodInfo Deployment:
```shell
kubectl apply -k https://github.com/fluxcd/flagger//kustomize/podinfo?ref=main
```
Install the PodInfor Load Test Deployment to Generate Sample Traffic:
```shell
kubectl apply -k https://github.com/fluxcd/flagger//kustomize/tester?ref=main
```

Lets create a Metric Template to Count the Number of 500 Errors to simulate this rollback situation:
```shell
kubectl apply -f error-rollback-metric-template.yaml
```

Create the Canary Resourse to perform the Canary Deployments:
```shell
kubectl apply -f podinfo-canary.yaml
```

Verify that the Canary has been sucessfully create using:
```shell
kubectl get canaries -n test
```
Ensure the Canary is in "Initialized" Status before proceeding further.

Ensure you are able to access the application from your local browser using app.example.com as specified in the Canary Configuration. In case not working, make an entry as below in /etc/hosts file and verify again.
```shell
127.0.0.1       app.example.com
```

Hence, above we manually applied the following resources:
```
deployment.apps/podinfo
horizontalpodautoscaler.autoscaling/podinfo
canary.flagger.app/podinfo
```

And once the canary was created it created the following resources with it:
```
deployment.apps/podinfo-primary
horizontalpodautoscaler.autoscaling/podinfo-primary
service/podinfo
service/podinfo-canary
service/podinfo-primary
destinationrule.networking.istio.io/podinfo-canary
destinationrule.networking.istio.io/podinfo-primary
virtualservice.networking.istio.io/podinfo
```


## Demo Canary Deployments and Rollback on Failures

#### Success Scenario
1. Trigger a Canary Deployment by Updating the Image
    ```shell
    kubectl -n test set image deployment/podinfo \
    podinfod=ghcr.io/stefanprodan/podinfo:6.0.1
    ```

2. Flagger detects that the deployment revision changed and starts a new rollout:
    ```shell
    kubectl -n test describe canary/podinfo
    ```

    Monitor the status of Canaries using below command:
    ```shell
    watch kubectl get canaries --all-namespaces
    ```

    Montior the Configuration of the Virtual Service using:
    ```shell
    watch kubectl get vs podinfo -oyaml
    ```

#### Automated rollback
1. Trigger a Canary Deployment by Updating the Image
    ```shell
    kubectl -n test set image deployment/podinfo \
    podinfod=ghcr.io/stefanprodan/podinfo:6.0.2
    ``` 
2. Generate False Error Traffic and 500 to make it seem the deployment is failing.

    Exec into the LoadTester Pod:
    ```shell
    kubectl -n test exec -it flagger-loadtester-xx-xx sh
    ```

    Generate Fake Error Traffic with 500 Status:
    ```shell
    hey -z 1m -q 10 -c 2 http://podinfo-canary.test:9898/status/500
    ```

3. We can notice that the Canary Deployment comes to a Halt as the failure metric condition is met and Deployment is rolled back after retry.


## Uninstalling the Demo

To delete the local demo kind k8s cluster:

```console
kind delete cluster --name flagger
```