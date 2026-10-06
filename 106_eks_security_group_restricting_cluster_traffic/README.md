# EKS Security Group Restricting Cluster Traffic

EKS creates the cluster security group with one egress rule: all protocols, all ports, to
`0.0.0.0/0`. This project removes it and lets the cluster come up without it.

## What the apply does

The rule is not a Terraform resource and cannot be made into one. EKS creates it as part of the
cluster, inside a group EKS also owns, so there is no ID to import and a declared
`aws_vpc_security_group_egress_rule` would add a second identical rule rather than adopt the
existing one. Removing it means a `RevokeSecurityGroupEgress` call against a rule ID that is only
discoverable at apply time, so `aws_ssm_association.revoke_default_cluster_egress` runs that call on
the workbench instance.

Two consequences of that, in order of how much they matter:

- **Nothing on the cluster is created before the revocation.** The addons, the node group, the
  access entry and the controller install are all ordered after the association, so the nodes join
  and the controller installs against the restricted group. A missing egress rule fails the apply
  rather than lying dormant until the next rebuild.
- **The revocation is not in Terraform state.** `terraform plan` never shows the rule, never notices
  it coming back, and never offers to remove it again. The `cluster_security_group_rules_command`
  output is the only thing that reports the group's actual state.

Because the association runs on the workbench, the workbench is now a prerequisite of the data
plane rather than somewhere to go and look afterwards, and `module "vscode_ec2"` sits ahead of the
cluster-dependent modules in `main.tf` for that reason. The node group waits out its bootstrap.

## The rule set afterwards

EKS ships the group with three rules, not two. Only the last is removed.

| Direction | Protocol | Port | Destination / source | Owner |
| --- | --- | --- | --- | --- |
| Inbound | all | all | this group (self) | EKS — recreated if removed |
| Outbound | all | all | this group (self) | EKS — recreated if removed |
| Outbound | TCP | 443 | interface endpoint group | `cluster_to_vpc_endpoints` |
| Outbound | TCP | 443 | S3 gateway endpoint prefix list | `cluster_to_s3` |
| ~~Outbound~~ | ~~all~~ | ~~all~~ | ~~`0.0.0.0/0`~~ | revoked by the SSM Association |

The restriction is therefore on traffic leaving the cluster, not traffic within it: intra-cluster
traffic keeps working on EKS's own outbound self rule, and this configuration never has to decide
which ports to open. Declaring that self rule here is a duplicate and fails the apply with
`InvalidPermission.Duplicate: the specified rule "peer: sg-..., ALL, ALLOW" already exists`.

Leaving it to EKS is also the only version that works. AWS documents the minimum for a restricted
cluster group as TCP 443, TCP 10250 and TCP/UDP 53 to this same group
([security group requirements](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html)),
and that list is not sufficient here — the load balancer controller's admission webhook listens on
9443 and the API server calls it, which would fail a `failurePolicy: Fail` webhook and break Service
creation cluster-wide. EKS's self rule is all protocols and sidesteps the question.

The Amazon-provided DNS resolver needs no rule: "You cannot filter traffic to or from the Amazon DNS
server using network ACLs or security groups"
([Understanding Amazon DNS](https://docs.aws.amazon.com/vpc/latest/userguide/AmazonDNS-concepts.html)).
That is what still lets a node resolve the endpoint hostnames.

## What the revocation took away, and what replaces it

The private subnets still route to a NAT gateway, but the cluster security group no longer permits
using it, so every AWS API the data plane calls has to arrive through a VPC endpoint. Three things
had to move:

| Was reached over NAT | Now |
| --- | --- |
| EKS Auth API, for Pod Identity credentials | `eks-auth` interface endpoint — required per [private clusters](https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html); without it the controller starts and then fails every AWS call |
| elasticloadbalancing API | `elasticloadbalancing` interface endpoint |
| `public.ecr.aws`, the chart's default controller image | ECR pull-through cache in this account, reached through the existing `ecr.api`/`ecr.dkr`/S3 endpoints. ECR Public is not a PrivateLink service, so there is no endpoint to add for it |

Deliberately not added: `eks`. A managed node group is handed its API server endpoint and CA in
generated user data, so nothing in the private subnets calls the EKS API. Self-managed nodes would
need it.

If this project ever grows an `Ingress`, set the controller's `enable-shield`, `enable-waf` and
`enable-wafv2` to false — those APIs have no interface endpoint, and the controller only calls them
while reconciling an Ingress.

## EKS Cluster Updates (Control Plane)

Which cluster updates rewrite the group's rules, and therefore when the revocation has to be
repeated. The `revoke_cluster_egress_command` output is the command to repeat it with.

- VersionUpdate : Inbound / Outbound Rules
    - Inbound Rule : All Ports + Self Source (Allows EFA traffic, which is not matched by CIDR rules.)
    - Outbound Rule : All Ports + Self Destination (Allows EFA traffic, which is not matched by CIDR rules.)
    - Outbound Rule : All Ports + 0.0.0.0/0 Destination (no description)
- VpcConfigUpdate : No Change (Inbound / Outbound Rules)
- EndpointAccessUpdate : No Change (Inbound / Outbound Rules)

The second line was originally recorded against the `0.0.0.0/0` rule. `describe-security-group-rules`
on a live cluster shows otherwise: the EFA description belongs to the two self rules, and the
`0.0.0.0/0` rule carries none. Only that third, undescribed rule is the one revoked here.
