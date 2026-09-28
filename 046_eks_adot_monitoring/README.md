# EKS ADOT Monitoring

Three variants of the same idea: the AWS Distro for OpenTelemetry EKS add-on, each with a
different collector enabled and a different destination.

| variant | collector | destination |
| --- | --- | --- |
| `cloudwatch_log` | `containerLogs` | CloudWatch Logs |
| `amp_metric` | `prometheusMetrics` | Amazon Managed Prometheus, plus CloudWatch EMF |
| `xray_trace` | `otlpIngest` | AWS X-Ray |

All three need cert-manager in place before the add-on: it installs the OpenTelemetry
Operator, whose admission webhook serves TLS from a certificate cert-manager issues. They
also need the RBAC that lets the `eks:addon-manager` user create that operator, which the
`adot_addon_permissions` module declares rather than fetching from a URL at apply time.

The add-on's configuration schema lives in the EKS API, not in the provider, so `plan`
cannot check it. Read it with:

```bash
aws eks describe-addon-configuration --addon-name adot --addon-version <version>
```

## Notes
- OpenTelemetry Data
  - Logs
  - Metrics
  - Traces

## References
- [One Observability](https://catalog.workshops.aws/observability/ko-KR/aws-native)
- [ADOT add-on configuration](https://docs.aws.amazon.com/eks/latest/userguide/opentelemetry.html)
- [ADOT add-on prerequisites](https://docs.aws.amazon.com/eks/latest/userguide/adot-manage-advanced.html)
