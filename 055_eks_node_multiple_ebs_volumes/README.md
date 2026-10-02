# EKS Node - Multiple EBS Volumes for Containers

The AWS guidance below is written for Amazon Linux 2 and states the feature is not yet
supported on AL2023. The difference is ordering, not capability: on AL2 the format and
mount commands ran as `preBootstrapCommands`, before the bootstrap script started
containerd, while on AL2023 the node is brought up by `nodeadm` from systemd units and a
user shell script part can run after containerd has already started. This configuration
runs the same work as a cloud-config `bootcmd` instead, in cloud-init's first stage, so
nothing has to be stopped and nothing is deleted.

## References
- [EKS Best Practice](https://docs.aws.amazon.com/ko_kr/eks/latest/best-practices/scale-data-plane.html#_use_multiple_ebs_volumes_for_containers)
- [Device naming on Linux instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/device_naming.html)
- [cloud-init boot stages](https://cloudinit.readthedocs.io/en/latest/explanation/boot.html)
