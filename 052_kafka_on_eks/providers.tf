terraform {
  required_version = ">= 1.9"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    # time_sleep, for the one destroy-time delay in main.tf (ebs_volume_release).
    time = { source = "hashicorp/time", version = "~> 0.14" }
    # alekc/kubectl rather than hashicorp/kubernetes. The cluster is created in this same apply, so its
    # endpoint is unknown at plan time and a typed provider fails with "no client config"; most of what
    # this project applies is also a custom resource - EC2NodeClass, NodePool, Kafka, KafkaNodePool,
    # KafkaTopic, KafkaRebalance, PodMonitor - whose CRD a Helm release installs in the same apply
    # (rules.md E-2/E-3).
    kubectl = { source = "alekc/kubectl", version = "~> 2.4" }
    helm    = { source = "hashicorp/helm", version = "~> 3.0" }
  }
}

# What this configuration is: the data-on-eks streaming/kafka blueprint (awslabs/data-on-eks at commit
# fe0b6390bb4ee76ef45c4ed26743deddb0fa6f93), declared as this project's own modules and applied by one
# terraform apply.
#
# The _monolithic template got the same cluster another way. Its workbench instance cloned the
# repository in user data and ran the blueprint's install.sh, which is a sequence of terraform apply
# -target runs - so there were two Terraform runs, one nested inside the other, the cluster's state lived
# on the instance's disk, and terraform destroy out here left the whole cluster running. Nothing is
# cloned now, and everything below is in this state file.
#
# Where each piece of the blueprint went:
#
#   vpc.tf (terraform-aws-modules/vpc)            modules/network
#   eks.tf (terraform-aws-modules/eks)            modules/eks_cluster, modules/eks_node_group
#   addons.tf eks_addons                          modules/eks_vpc_cni_addon, eks_kube_proxy_addon,
#                                                 eks_coredns_addon, eks_ebs_csi_driver_addon
#   addons.tf gp3 StorageClass                    modules/csi_storage_classes
#   addons.tf metrics-server                      modules/eks_metrics_server_addon (an EKS addon
#                                                 rather than the chart)
#   addons.tf Karpenter (eks-blueprints-addons)   modules/karpenter_interruption_queue, karpenter
#   addons.tf karpenter-resources (data addons)   modules/karpenter_node_pool, once per pool
#   eks.tf aws-auth mapping for Karpenter nodes   an EC2_LINUX access entry inside modules/karpenter
#   addons.tf Strimzi (eks-data-addons)           modules/strimzi_kafka_operator
#   addons.tf kube-prometheus-stack, amp.tf       modules/kube_prometheus_stack
#   kafka-manifests/, examples/kafka-topics.yaml  modules/kafka_cluster
#   monitoring-manifests/                         modules/kafka_monitoring
#
# And what 052 added on top, which used to run from an SSM association on the workbench: the AWS Load
# Balancer Controller (modules/aws_load_balancer_controller) and the Grafana Ingress
# (modules/grafana_ingress), whose ALB keeps its own frontend security group
# (modules/load_balancer_security_group).
#
# Not converted, on purpose:
#
#   - install.sh and cleanup.sh. They exist to order -target applies and to sweep up what a failed
#     destroy left behind; the depends_on edges in main.tf give apply and destroy that order directly.
#   - helper.sh, load-test.sh and examples/kafka-producers-consumers.yaml - demo scripts rather than
#     infrastructure. The README this project writes onto the workbench carries the producer and
#     consumer commands instead.
#   - helm-values/coredns-autoscaler-values.yaml, which nothing in the blueprint referenced.
#   - The gp2 StorageClass annotation. It has nothing to change on this Kubernetes version, and
#     modules/csi_storage_classes records why kubectl_manifest could not express it safely anyway.
#   - The us-east-1 provider and its ECR Public token. The blueprint used the token to pull the Karpenter
#     chart; public.ecr.aws serves the chart anonymously, and the token only raises the pull rate limit.
#   - The eks module's extra security group rules. The nodes and pods here all carry the cluster
#     security group, whose self-referencing rule already allows everything those rules added.
provider "aws" {
  region = var.aws_region
}

# lazy_load is what makes one apply possible: the provider is declared against a host that is unknown at
# plan time, and the REST client is not built until a kubectl_manifest is first used - by which point the
# cluster exists (rules.md E-2).
#
# Declaring this provider at all is legitimate because the cluster keeps a public API server endpoint:
# the provider runs wherever terraform runs. var.endpoint_public_access pins that (rules.md E-9).
provider "kubectl" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
  }
}

# helm needs no equivalent workaround: it only connects during apply, so hashicorp/helm is used as is
# (rules.md E-2).
provider "helm" {
  kubernetes = {
    host                   = module.eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
    }
  }
}
