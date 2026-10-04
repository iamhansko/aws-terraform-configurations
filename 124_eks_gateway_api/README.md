# EKS Gateway API

The Kubernetes Gateway API satisfied by an AWS Application Load Balancer, through the AWS Load Balancer
Controller.

## Chain

```
GatewayClass (controllerName: gateway.k8s.aws/alb)
  -> Gateway                 = one internet-facing ALB, HTTP listener on 80
    -> HTTPRoute             = listener rules + target group
      -> Service (ClusterIP) = target group members, target type ip
        -> Deployment        = 2 pods
```

## CRDs

| Bundle | Supplies |
|:-|:-|
| Gateway API v1.6.0, standard channel | `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`, L4 routes |
| AWS-vended, from the controller release | `LoadBalancerConfiguration`, `TargetGroupConfiguration`, `ListenerRuleConfiguration` |

The controller decides which of its Gateway controllers to run by looking for these CRDs at startup, so they
are installed before the chart. The AWS-vended ones carry what the Gateway API has no field for: the ALB's
scheme (`internal` by default) and the target group's target type (`instance` by default).

L7 routes (`HTTPRoute`, `GRPCRoute`) are satisfied by an ALB, L4 routes (`TCPRoute`, `UDPRoute`, `TLSRoute`) by
an NLB. Mixing the two layers on one Gateway is not supported.

## Private API server

`endpoint_public_access` is `false`, as in the CloudFormation template this was converted from. There is no
`kubectl` or `helm` provider in the root module, because neither could reach the API server from the machine
running `terraform apply`. The CRDs, the controller chart and the demo objects are applied instead by SSM
Associations on the VS Code instance, chained by marker files. See `providers.tf` for what that costs, and the
`teardown` output for the one manual step `terraform destroy` needs.

## References

- [Gateway API - AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway/)
- [AWS Load Balancer Controller adds general availability support for Kubernetes Gateway API](https://aws.amazon.com/blogs/networking-and-content-delivery/aws-load-balancer-controller-adds-general-availability-support-for-kubernetes-gateway-api/)
