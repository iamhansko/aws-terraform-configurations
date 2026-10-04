variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. When null, falls back to the provider default chain (AWS_REGION, profile, etc.)"

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as ap-northeast-2, or null to fall back to the provider default chain."
  }
}
variable "cluster_name" {
  type        = string
  default     = "gateway-api"
  description = "Name of the EKS cluster, and the basis for the key pair and the resource names derived from it. The _monolithic template let CloudFormation generate the cluster name and sliced the key pair's name out of AWS::StackId; naming both from here makes them predictable without being fixed account-wide"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.cluster_name))
    error_message = "cluster_name must be 2-31 characters of lowercase letters, digits and hyphens, short enough to leave room for the per-resource suffixes."
  }
}
variable "kubernetes_version" {
  type        = string
  default     = "1.36"
  description = "Kubernetes version for the EKS cluster, as the _monolithic template's parameter defaulted to"

  validation {
    condition     = can(regex("^1\\.(3[3-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "kubernetes_version must be 1.33 or newer, e.g. 1.36."
  }
}
variable "kubectl_download_version" {
  type        = string
  default     = "1.36.2/2026-07-05"
  description = <<-DESC
    Version path used to download kubectl onto the workbench, in <version>/<release-date> form (rules.md H-1).

    Kept in step with kubernetes_version on purpose. The _monolithic template downloaded 1.33.3 onto a cluster
    its own parameter defaulted to 1.36 - three minor versions of skew, where the supported window is one, and
    the symptoms of being outside it are unserved API versions rather than a clear refusal.
  DESC

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.kubectl_download_version))
    error_message = "kubectl_download_version must look like 1.36.2/2026-07-05."
  }
  validation {
    # The pair is what can be wrong. A client more than one minor off the control plane is outside the
    # supported skew, and nothing reports that - it shows up as a resource type kubectl cannot work with
    # (rules.md B-1).
    condition     = abs(tonumber(split(".", split("/", var.kubectl_download_version)[0])[1]) - tonumber(split(".", var.kubernetes_version)[1])) <= 1
    error_message = "kubectl_download_version must be within one minor version of kubernetes_version, which is the skew Kubernetes supports."
  }
}
variable "endpoint_public_access" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the EKS API server endpoint is reachable from the internet. False, as the _monolithic template had
    it, and the one fact that decides how everything Kubernetes-shaped gets created here.

    With it false there is no provider that can reach the cluster, so the CRDs, the controller chart and the
    demo objects are applied by SSM Associations on the workbench instead (rules.md E-9). Turning it on would
    not make those steps work differently - it would change what the original configuration did, which is a
    different project.
  DESC

  validation {
    condition     = var.endpoint_public_access == false
    error_message = "endpoint_public_access must stay false in this variant, because the _monolithic template set EndpointPublicAccess: false and every Kubernetes object here is applied by an SSM Association on the workbench rather than by a kubectl or helm provider. To run with a public endpoint, declare those providers in providers.tf and move the three SSM steps to kubectl_manifest and helm_release resources, as 008_eks_aws_load_balancer_controller does (rules.md E-9)."
  }
}
variable "vpc_cidr_block" {
  type        = string
  default     = "10.1.0.0/16"
  description = "CIDR block for the VPC, as the _monolithic template had it. It must not overlap service_ipv4_cidr below, which EKS checks and silently works around by picking a different Service range"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid IPv4 CIDR block."
  }
}
variable "service_ipv4_cidr" {
  type        = string
  default     = "172.20.0.0/16"
  description = <<-DESC
    CIDR block the cluster allocates Service IPs from, as the _monolithic template's KubernetesNetworkConfig
    had it. Immutable after cluster creation.

    It must not overlap vpc_cidr_block. That is not validated here, because HCL has no way to test CIDR
    containment, and a condition that only compares the two network addresses would pass on most real
    overlaps - a validation that is wrong in the interesting cases is worse than none (rules.md B-1). The
    cluster's own output reads this value back from the resource rather than echoing the variable, so an
    overlap EKS worked around by picking a different range is visible in terraform output.
  DESC

  validation {
    condition     = can(cidrhost(var.service_ipv4_cidr, 0))
    error_message = "service_ipv4_cidr must be a valid IPv4 CIDR block."
  }
}
variable "availability_zone_suffixes" {
  type        = list(string)
  default     = ["a", "c"]
  description = "Zones the VPC spans, a and c as the _monolithic template's AzMapping had them. Two is the minimum for an EKS control plane and also for an ALB, which is what the Gateway in this project provisions"

  validation {
    condition     = length(var.availability_zone_suffixes) >= 2
    error_message = "availability_zone_suffixes must name at least two zones: an EKS control plane requires subnets in two, and so does an Application Load Balancer."
  }
}
variable "public_subnet_tags" {
  type = map(string)
  default = {
    "kubernetes.io/role/elb" = "1"
  }
  description = <<-DESC
    Tags merged into every public subnet. The kubernetes.io/role/elb tag is how the AWS Load Balancer
    Controller discovers subnets for an internet-facing load balancer; without it the controller falls back to
    classifying subnets by route table and, failing that, reports "couldn't auto-discover subnets" on the
    Gateway (rules.md G-1).

    The _monolithic template tagged no subnets at all, so its Gateway - had it created one - would have been
    relying on that fallback.

    Note the asymmetry this creates and that it is intended: the cluster itself is given private subnets only,
    but the ALB the Gateway provisions lives in these public ones. The API server is what is private here, not
    the application.
  DESC

  validation {
    condition     = alltrue([for key in keys(var.public_subnet_tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "public_subnet_tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}
variable "private_subnet_tags" {
  type = map(string)
  default = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  description = "Tags merged into every private subnet. The internal-elb counterpart of public_subnet_tags, so a Gateway asking for an internal scheme discovers these instead"

  validation {
    condition     = alltrue([for key in keys(var.private_subnet_tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "private_subnet_tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}
variable "key_name" {
  type        = string
  default     = null
  description = "Name of the EC2 key pair created for the workbench and the nodes. Null derives it from cluster_name"

  validation {
    condition     = var.key_name == null || length(var.key_name) > 0
    error_message = "key_name must be a non-empty string, or null to derive it from cluster_name."
  }
}
variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.large"]
  description = "Instance types for the managed node group, t3.large as the _monolithic template had it"

  validation {
    condition     = length(var.node_group_instance_types) > 0
    error_message = "node_group_instance_types must contain at least one instance type."
  }
}
variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count, two as the _monolithic template had it"

  validation {
    condition     = var.node_group_desired_size >= 1
    error_message = "node_group_desired_size must be at least 1. The CoreDNS addon needs schedulable capacity to become ACTIVE, and the controller needs somewhere to run."
  }
}
variable "node_group_min_size" {
  type        = number
  default     = 2
  description = "Minimum node count, two as the _monolithic template had it"

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}
variable "node_group_max_size" {
  type        = number
  default     = 4
  description = "Maximum node count, four as the _monolithic template had it"

  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be greater than or equal to node_group_min_size."
  }
}
variable "vscode_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for the workbench, as the _monolithic template had it. On this project it is not only a convenience: it is the only place kubectl and helm can reach the cluster from"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.vscode_instance_type))
    error_message = "vscode_instance_type must be a valid EC2 instance type, e.g. t3.medium."
  }
}
variable "allow_inbound_from_anywhere" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether the workbench security group accepts traffic from 0.0.0.0/0 on the code-server port, which is
    8000. True, so the vscode_url output is reachable from a browser without any further setup.

    This departs from the _monolithic template, whose InboundFromAnywhere parameter defaulted to "False" - a
    bool here where that template used a string validated against ["True", "False"].

    Worth being clear about what it exposes, because nothing else in this configuration limits it: code-server
    is configured with auth: none, and the instance's role is AdministratorAccess (rules.md A-5 exempts the
    workbench from the least-privilege rule, which is what makes this combination possible). So anyone who
    reaches port 8000 gets an unauthenticated terminal with administrative credentials in this account, and
    with the cluster security group attached, kubectl against the private API server.

    Two narrower options, if that trade is not wanted:
      - set this false and reach code-server through SSM Session Manager port forwarding;
      - set this false and put an office or home prefix in vscode_ingress_cidr_blocks, which opens the same
        port to those CIDRs only.
  DESC
}
variable "vscode_ingress_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDR blocks allowed to reach code-server, in addition to allow_inbound_from_anywhere. Set this to an office or home prefix rather than opening the port to everyone"

  validation {
    condition     = alltrue([for cidr in var.vscode_ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "vscode_ingress_cidr_blocks must contain valid IPv4 CIDR blocks."
  }
}
variable "marker_file_path" {
  type        = string
  default     = "/run/terraform"
  description = "Directory on the workbench where each bootstrap step drops its completion marker. The SSM steps wait on these markers rather than on depends_on, which does not reliably wait for a remote command to finish (rules.md D-5)"

  validation {
    condition     = can(regex("^/", var.marker_file_path))
    error_message = "marker_file_path must be an absolute path starting with '/'."
  }
}
variable "gateway_api_version" {
  type        = string
  default     = "v1.6.0"
  description = <<-DESC
    Gateway API release whose standard-channel CRDs are installed, as the _monolithic template pinned it.

    It has to match what the controller was built against - the controller documents v1.6.0 for the release
    pinned below - because the CRDs are what decides which API versions exist. v1.6.0 is also the release that
    moved TCPRoute and UDPRoute into the standard channel, so the experimental bundle is no longer needed for
    L4 routes.
  DESC

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.gateway_api_version))
    error_message = "gateway_api_version must be a tagged release such as v1.6.0."
  }
}
variable "aws_load_balancer_controller_version" {
  type        = string
  default     = "3.5.0"
  description = <<-DESC
    Version of the AWS Load Balancer Controller, used for three things at once: the Helm chart version, the tag
    the AWS-vended Gateway API CRDs are fetched from, and the controller image the chart pulls.

    One variable rather than three because the eks-charts chart version has tracked the controller's own
    appVersion since 3.0.0, and the CRDs have to come from the same release as the controller that reads them -
    a newer CRD bundle against an older controller is accepted and then ignored (rules.md B-5).

    3.0.0 is the floor, and not an arbitrary one: Gateway API support reached GA there. The L7 path this
    project uses - HTTPRoute satisfied by an ALB - needs at least 2.14.0, and the _monolithic template installed
    the chart with no version at all, so what it got depended on the day.
  DESC

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.aws_load_balancer_controller_version))
    error_message = "aws_load_balancer_controller_version must be a semantic version, e.g. 3.5.0."
  }
  validation {
    condition     = tonumber(split(".", var.aws_load_balancer_controller_version)[0]) >= 3
    error_message = "aws_load_balancer_controller_version must be 3.0.0 or newer. Gateway API support is GA from that release; on older ones the Gateway and HTTPRoute objects are created and nothing reconciles them, which is silent rather than an error."
  }
}
variable "aws_load_balancer_controller_release_name" {
  type        = string
  default     = "aws-load-balancer-controller"
  description = "Helm release name for the controller, as the _monolithic template had it"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.aws_load_balancer_controller_release_name))
    error_message = "aws_load_balancer_controller_release_name must be a valid Helm release name."
  }
}
variable "aws_load_balancer_controller_replica_count" {
  type        = number
  default     = 2
  description = "Controller replicas. Two, which is the chart default, so a node going away does not leave Gateways unreconciled"

  validation {
    condition     = var.aws_load_balancer_controller_replica_count >= 1
    error_message = "aws_load_balancer_controller_replica_count must be at least 1."
  }
}
variable "enable_backend_security_group" {
  type        = bool
  default     = true
  description = <<-DESC
    Whether the controller uses one shared backend security group (k8s-traffic-<cluster>-<hash>) as the source
    of the node-side rules it writes, rather than referencing each load balancer's own frontend group.

    True, which is the controller's own default and the right value here. For Gateway API the controller
    creates and attaches both the frontend and the backend security groups itself, and it writes the pod-side
    rules too - so there is exactly one owner of those rules and Terraform declares none of them
    (rules.md F-2). This is the third row of the table in rules.md G-2, the one where both values are valid,
    which is why no validation pins it.

    Setting it false is supported and costs one rule per load balancer on the cluster security group instead of
    one shared group. Do not set it false while also asking the controller to manage backend rules through a
    LoadBalancerConfiguration - that combination is refused, and refused only in the controller's log.
  DESC
}
variable "enable_service_mutator_webhook" {
  type        = bool
  default     = false
  description = <<-DESC
    Whether the chart installs the mservice.elbv2.k8s.aws mutating webhook, whose only job is to make this
    controller the default for new Services of type LoadBalancer by injecting spec.loadBalancerClass.

    False, because nothing here relies on it: the demo exposes its workload through a Gateway, and the one
    Service in the cluster is a ClusterIP that an HTTPRoute names as a backend. What the webhook would cost is
    out of proportion to that - the chart gives it failurePolicy: Fail, no namespaceSelector, and a rule
    matching every v1/services CREATE in the cluster, so while the controller has no Ready pod the API server
    rejects every Service created anywhere, naming this webhook rather than whatever was being installed
    (rules.md G-4).

    Set it true only after confirming some Service is of type LoadBalancer without the
    aws-load-balancer-type: external annotation - and note that ordering the Services after the controller
    only covers the apply, not a later controller rollout.
  DESC

  validation {
    condition     = var.enable_service_mutator_webhook == false
    error_message = "enable_service_mutator_webhook must stay false in this variant. No Service here relies on the webhook - the workload is fronted by a Gateway - while its failurePolicy: Fail applies to every Service created in the cluster and fails any release installing Services while the controller has no Ready pod (rules.md G-4)."
  }
}
variable "gateway_class_name" {
  type        = string
  default     = "aws-alb-gateway-class"
  description = "Name of the GatewayClass the demo Gateway references. Cluster-scoped, so two copies of this project in one account need different values here"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.gateway_class_name))
    error_message = "gateway_class_name must be a valid Kubernetes object name."
  }
}
variable "gateway_name" {
  type        = string
  default     = "alb-gateway"
  description = "Name of the demo Gateway. The controller provisions one ALB per Gateway, so this is also what the load balancer in the console corresponds to"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.gateway_name))
    error_message = "gateway_name must be a valid Kubernetes object name."
  }
}
variable "gateway_listener_port" {
  type        = number
  default     = 80
  description = "Port the Gateway's HTTP listener accepts traffic on, and therefore the ALB listener port. HTTP rather than HTTPS because a certificate would have to come from somewhere; an HTTPS listener needs a LoadBalancerConfiguration carrying defaultCertificate, since the Gateway API's certificateRefs field is not supported by the ALB implementation"

  validation {
    condition     = var.gateway_listener_port > 0 && var.gateway_listener_port <= 65535
    error_message = "gateway_listener_port must be a valid TCP port."
  }
}
variable "gateway_scheme" {
  type        = string
  default     = "internet-facing"
  description = "Scheme of the ALB the Gateway provisions, carried in a LoadBalancerConfiguration attached to the Gateway's infrastructure.parametersRef. Stated rather than left out: the controller's default for a Gateway is internal, which would produce a load balancer with no public address and no error to say why"

  validation {
    condition     = contains(["internet-facing", "internal"], var.gateway_scheme)
    error_message = "gateway_scheme must be either internet-facing or internal."
  }
}
variable "gateway_target_type" {
  type        = string
  default     = "ip"
  description = <<-DESC
    Target type of the target groups the controller builds for routes attached to this Gateway, carried in a
    TargetGroupConfiguration attached to the Service.

    ip, so traffic goes to the pod's container port and the Service can stay a ClusterIP. The controller's
    default is instance, which registers nodes on the Service's NodePort and therefore requires a NodePort
    Service - the pairing rules.md G-1 tabulates. ip works here because the VPC CNI gives pods addresses the
    VPC routes to directly.
  DESC

  validation {
    condition     = contains(["ip", "instance"], var.gateway_target_type)
    error_message = "gateway_target_type must be either ip or instance."
  }
  validation {
    # The pair is what can be wrong. instance mode sends traffic to a NodePort, and a ClusterIP Service has
    # none - the target group is built and every target fails its health check (rules.md B-1/G-1).
    condition     = var.gateway_target_type == "ip" || var.workload_service_type == "NodePort"
    error_message = "gateway_target_type = \"instance\" requires workload_service_type = \"NodePort\", because instance targets are registered against the Service's node port and a ClusterIP Service does not have one (rules.md G-1)."
  }
}
variable "workload_namespace" {
  type        = string
  default     = "default"
  description = "Namespace holding the demo workload, its Service, the Gateway and the HTTPRoute. One namespace for all of them because the Gateway's listener allows routes from Same, and its LoadBalancerConfiguration reference is namespace-local"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.workload_namespace))
    error_message = "workload_namespace must be a valid Kubernetes namespace name."
  }
}
variable "workload_name" {
  type        = string
  default     = "http-echo"
  description = "Name of the demo Deployment and of the Service in front of it"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.workload_name))
    error_message = "workload_name must be a valid Kubernetes object name."
  }
}
variable "workload_image" {
  type        = string
  default     = "public.ecr.aws/x2j8p8w7/http-server:latest"
  description = "Container image for the demo workload - AWS's own sample HTTP server, which answers with the value of the PodName environment variable, so a response shows which pod handled it. A floating tag, which is tolerable on ECR Public and has no versioned alternative published"

  validation {
    condition     = can(regex(":[a-zA-Z0-9._-]+$|@sha256:[0-9a-f]{64}$", var.workload_image))
    error_message = "workload_image must carry an explicit tag or a digest."
  }
}
variable "workload_replicas" {
  type        = number
  default     = 2
  description = "How many pods the demo runs. Two, so repeated requests through the Gateway come back naming different pods and the target group holding both addresses is visible"

  validation {
    condition     = var.workload_replicas >= 1
    error_message = "workload_replicas must be at least 1."
  }
}
variable "workload_container_port" {
  type        = number
  default     = 8090
  description = <<-DESC
    Port the demo container actually listens on. 8090, which is what the sample server in workload_image
    binds - confirmed against a running pod, and the same value 070_eks_vpc_lattice uses for the same image.

    This has to be the real port, and nothing in Terraform can check that it is. It feeds three places: the
    Deployment's containerPort, the Service's targetPort, and - because gateway_target_type is ip - the port
    the controller registers each pod on, which is also the health check port (traffic-port).

    Only the second and third of those do anything. containerPort is documentation: Kubernetes does not make a
    process listen there, so a wrong value here produces no error from the API server, no error from the
    controller, and a Deployment that reports Running and Ready. What it produces instead is a target group
    whose every member fails its health check, and an ALB that answers 502 - which reads as a networking or a
    security group problem rather than a wrong number.

    The default used to be 80 and that is exactly what happened. The check is one command, and the
    target_health_command output has it: probe the pod's address directly on this port.
  DESC

  validation {
    condition     = var.workload_container_port > 0 && var.workload_container_port <= 65535
    error_message = "workload_container_port must be a valid TCP port."
  }
}
variable "workload_service_port" {
  type        = number
  default     = 80
  description = "Port the Service publishes, which is the port the HTTPRoute's backendRef names"

  validation {
    condition     = var.workload_service_port > 0 && var.workload_service_port <= 65535
    error_message = "workload_service_port must be a valid TCP port."
  }
}
variable "workload_service_type" {
  type        = string
  default     = "ClusterIP"
  description = "Type of the Service the HTTPRoute names as its backend. ClusterIP, which is what target type ip needs - and deliberately not LoadBalancer: the Gateway is what fronts this workload, and a Service of type LoadBalancer would ask the controller for a second load balancer"

  validation {
    condition     = contains(["ClusterIP", "NodePort"], var.workload_service_type)
    error_message = "workload_service_type must be ClusterIP or NodePort. LoadBalancer would provision a second load balancer alongside the Gateway's."
  }
}
variable "route_path_prefix" {
  type        = string
  default     = "/"
  description = "Path prefix the HTTPRoute matches. Everything, so the Gateway's address answers without a path"

  validation {
    condition     = startswith(var.route_path_prefix, "/")
    error_message = "route_path_prefix must start with '/'."
  }
}
variable "crd_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the CRD association may take. It first waits for the instance bootstrap, which installs code-server, kubectl, eksctl, helm and docker"

  validation {
    condition     = var.crd_timeout_seconds > 0
    error_message = "crd_timeout_seconds must be positive."
  }
}
variable "controller_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the controller association may take, end to end. It has to exceed controller_helm_timeout_seconds, or SSM gives up first and reports a bare Failed with none of helm's explanation"

  validation {
    condition     = var.controller_timeout_seconds > 0
    error_message = "controller_timeout_seconds must be positive."
  }
}
variable "controller_helm_timeout_seconds" {
  type        = number
  default     = 600
  description = "Timeout passed to helm's own --wait. Smaller than controller_timeout_seconds on purpose: whichever side gives up first decides what the failure looks like, and helm's message plus the pod listing that follows it is the useful one"

  validation {
    condition     = var.controller_helm_timeout_seconds > 0
    error_message = "controller_helm_timeout_seconds must be positive."
  }
  validation {
    # The pair is what can be wrong, and getting it wrong does not fail - it just discards the diagnosis
    # (rules.md B-1/E-9).
    condition     = var.controller_helm_timeout_seconds < var.controller_timeout_seconds
    error_message = "controller_helm_timeout_seconds must be smaller than controller_timeout_seconds, so helm reports its own failure before SSM abandons the command."
  }
}
variable "workload_rollout_timeout_seconds" {
  type        = number
  default     = 300
  description = "Timeout handed to 'kubectl rollout status' on the demo Deployment. Seconds rather than a kubectl duration string so it can be compared with the association's own timeout below without parsing anything"

  validation {
    condition     = var.workload_rollout_timeout_seconds > 0
    error_message = "workload_rollout_timeout_seconds must be positive."
  }
}
variable "gateway_wait_timeout_seconds" {
  type        = number
  default     = 900
  description = "Timeout handed to 'kubectl wait --for=condition=Programmed' on the Gateway. Programmed means the controller created the ALB and AWS reported it active, which takes minutes - fifteen is generous rather than typical"

  validation {
    condition     = var.gateway_wait_timeout_seconds > 0
    error_message = "gateway_wait_timeout_seconds must be positive."
  }
}
variable "demo_timeout_seconds" {
  type        = number
  default     = 1800
  description = "How long the demo association may take, end to end. It waits for the workload rollout and then for the Gateway to be Programmed, so it has to allow for both"

  validation {
    condition     = var.demo_timeout_seconds > 0
    error_message = "demo_timeout_seconds must be positive."
  }
  validation {
    # The three only make sense as a set, and getting them wrong does not fail - it discards the diagnosis.
    # Whichever side gives up first decides what the failure looks like, and kubectl's message plus the
    # describe output that follows it is the useful one; SSM reports a bare Failed (rules.md B-1/E-9).
    condition     = var.demo_timeout_seconds > var.workload_rollout_timeout_seconds + var.gateway_wait_timeout_seconds
    error_message = "demo_timeout_seconds must exceed workload_rollout_timeout_seconds plus gateway_wait_timeout_seconds, so kubectl reports its own failure before SSM abandons the command and reports only \"unexpected state 'Failed'\"."
  }
}
variable "readme_timeout_seconds" {
  type        = number
  default     = 900
  description = "How long the README association may take. It waits for the demo step before writing anything, so the README it leaves describes a cluster that is already up (rules.md H-2)"

  validation {
    condition     = var.readme_timeout_seconds > 0
    error_message = "readme_timeout_seconds must be positive."
  }
}
