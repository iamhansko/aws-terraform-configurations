# EKS Cilium Networking

Cilium replaces both the VPC CNI and kube-proxy here. That is only real because the
cluster sets `bootstrap_self_managed_addons = false` and this root installs neither the
`vpc-cni` nor the `kube-proxy` addon - without that flag EKS installs both at cluster
creation, and a cluster running two CNIs looks healthy while demonstrating nothing.

## References
- [Deploying Cilium Networking on Amazon EKS Hybrid Nodes](https://repost.aws/articles/ARpKAVyUXgSBW1h9GBhh2JKA/deploying-cilium-networking-on-amazon-eks-hybrid-nodes)
- [Installing using Helm](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Kubernetes Without kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
- [Cilium on AWS ENI](https://docs.cilium.io/en/stable/network/concepts/ipam/eni/)
