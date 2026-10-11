# EKS Teleport

Requires a Route 53 hosted zone you control. Teleport's proxy does not become ready until
cert-manager has proved control of a name inside it over a DNS-01 challenge, and there is
no self-signed fallback - the certificate has to be one a browser and a `tsh` client both
accept. Pass `teleport_domain_name`, `teleport_route53_hosted_zone_id` and
`teleport_issuer_email`.

The load balancer is created by Terraform and adopted by the AWS Load Balancer Controller
(`rules.md` G-3), which is what makes the two alias records Terraform resources rather than
a shell script's `route53 change-batch`: the DNS name and hosted zone ID are known from
state.

## After apply

The first Teleport user is created by the operator, from the terminal that ran
`terraform apply` and with the same AWS credentials - not from the VS Code instance. Those
credentials are the cluster creator's, which EKS made a cluster admin, so nothing else has to
be granted, and the single-use invite link the command prints appears only on that screen
rather than in an IDE that has no login of its own. It needs `kubectl` on that machine, and
it switches that machine's current kubectl context to this cluster.

```bash
terraform output -raw add_user_command   # read it first
eval "$(terraform output -raw add_user_command)"
```

Hand the link to whoever will sign in; they continue from step 2 of the README on the VS Code
instance. If the command answers that the user already exists, run `reset_user_command` the
same way: Teleport creates its DynamoDB tables itself, so `terraform destroy` leaves them -
and the users in them - for the next apply.

## References
- [Authenticating to EKS Using GitHub Credentials with Teleport](https://aws.amazon.com/ko/blogs/opensource/authenticating-eks-github-credentials-teleport/)
- [Teleport 애플리케이션 액세스를 통한 AWS 액세스](https://teleport-docs.infograb.net/enroll-resources/application-access/cloud-apis/aws-console/)
- [Securing EKS with Teleport](https://www.youtube.com/watch?v=GlMEnK1yfKo)
- [Teleport EKS Auto-Discovery](https://goteleport.com/docs/enroll-resources/auto-discovery/kubernetes/aws/)
- [Running an HA Teleport cluster using AWS, EKS, and Helm](https://goteleport.com/docs/zero-trust-access/deploy-a-cluster/helm-deployments/aws/)
- [cert-manager DNS-01 with Route 53](https://cert-manager.io/docs/configuration/acme/dns01/route53/)
