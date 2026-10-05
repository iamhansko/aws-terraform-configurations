git clone https://github.com/aws-solutions-library-samples/guidance-for-multi-cluster-application-management-with-karmada-and-amazon-eks.git
cd /home/ec2-user/guidance-for-multi-cluster-application-management-with-karmada-and-amazon-eks/eks-karmada-deploy
# https://etcd.io/docs/v3.6/op-guide/kubernetes/
# https://github.com/etcd-io/etcd/issues/13524
sed -i 's/--etcd-replicas 3/--etcd-replicas 1/' /home/ec2-user/guidance-for-multi-cluster-application-management-with-karmada-and-amazon-eks/eks-karmada-deploy/include/deploy-karmada-functions.sh
chmod +x deploy-karmada-run.sh
./deploy-karmada-run.sh -r ${AWS::Region} -v ${ClusterNamePrefix} -c ${ClusterNamePrefix} -s ${MemberClusterCount} -e ${KubernetesVersion} -k /home/ec2-user -u -t > /home/ec2-user/karmada-deploy.log 2>&1