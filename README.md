# k8s-full-native
Kubernetes Cluster for a DevOps setup that doesn't depend on a Cloud Provider, but relies only on Kubernetes-native features for Message/Command Buses, DBs and other persistence, secrets, etc. 

run:

1. `./minikube/setup-minikube.sh` to setup minikube
2. `./bootstrap-fluxcd.sh` to setup the cluster with a basic fluxcd config
    - this also runs all helm charts
3. `for ns in flux-system sys-cert-manager sys-sealed-secrets; do kubectl delete pods --all -n $ns; done` to restart the pods in the namespaces that received pods before linkerd was installed (this initiates sidecar injection for these pods)


## Todos:
- [ ] cnpg
- [ ] redis
- [ ] rabbitmq
- [ ] LGTM stack
- [ ] Sentry (instead of Grafana-Tempo) (maybe)
- [ ] More: https://github.com/remikeat/cluster
  - [ ] minio or rook/ceph
  - [ ] knative
  - [ ] harbor
  - [ ] Someting something datalake + querying (flink/spark)
