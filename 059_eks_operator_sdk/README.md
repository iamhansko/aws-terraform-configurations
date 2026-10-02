# EKS - Operator SDK

Terraform owns the cluster, the nodes and the ECR repository. The operator itself is
scaffolded, built and deployed by SSM Association steps on the bastion, which is a
deliberate exception to `rules.md` E-1: `operator-sdk init` and `create api` generate the
source, `make docker-build` needs a Docker daemon, and `make deploy` applies manifests
that only exist once the generator has run. See the comment at the top of `providers.tf`.

## References
- [Operator SDK - Go Operator Tutorial](https://sdk.operatorframework.io/docs/building-operators/golang/tutorial/)
- [Operator SDK installation](https://sdk.operatorframework.io/docs/installation/)
- [deploy-image plugin](https://sdk.operatorframework.io/docs/overview/cronjob-tutorial/)
