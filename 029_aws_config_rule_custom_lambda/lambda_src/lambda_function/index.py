import boto3
import json

config_client = boto3.client('config')
iam_client = boto3.client('iam')

def get_attached_policies(role_name):
    """해당 IAM 롤의 모든 AWS 관리형 정책 가져오기"""
    paginator = iam_client.get_paginator('list_attached_role_policies')
    policies = []
    for page in paginator.paginate(RoleName=role_name):
        policies.extend(page['AttachedPolicies'])
    return policies

def update_role_policies(role_name):
    """AmazonS3ReadOnlyAccess만 남기고 나머지 정책 제거. 없으면 추가."""
    s3_policy_arn = 'arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess'
    policies = get_attached_policies(role_name)

    has_s3 = any(p['PolicyArn'] == s3_policy_arn for p in policies)
    other_policies = [p for p in policies if p['PolicyArn'] != s3_policy_arn]

    # AmazonS3ReadOnlyAccess 이외 정책 제거
    for p in other_policies:
        print(f"Detached policy: {p['PolicyName']}")
        iam_client.detach_role_policy(RoleName=role_name, PolicyArn=p['PolicyArn'])
    # AmazonS3ReadOnlyAccess 없으면 추가
    if len(policies) == 0:
        print(f"No policies attached to the role")
    if not has_s3:
        print(f"Attached policy: AmazonS3ReadOnlyAccess")
        iam_client.attach_role_policy(RoleName=role_name, PolicyArn=s3_policy_arn)

def is_applicable(configuration_item, event):
    """평가할 수 있는 항목인지 판단.

    삭제되었거나(ResourceDeleted, ResourceDeletedNotRecorded) 기록되지 않은(ResourceNotRecorded)
    리소스의 configurationItem은 configuration이 None이고, eventLeftScope가 참이면 리소스가 규칙
    범위를 벗어난 것이므로 둘 다 판정할 대상이 없음. AWS Config 규칙 예제가 쓰는 조건과 같음.
    """
    status = configuration_item.get('configurationItemStatus')
    return status in ('OK', 'ResourceDiscovered') and not event.get('eventLeftScope', False)

def lambda_handler(event, context):
    invoking_event = json.loads(event['invokingEvent'])
    configuration_item = invoking_event.get('configurationItem', {})
    instance_id = configuration_item.get('resourceId')
    tags = configuration_item.get('tags', {}) or {}
    instance_name = tags.get('Name', '')

    if configuration_item.get('resourceType') != 'AWS::EC2::Instance':
        return
    if instance_name and instance_name == 'governance-bastion':
        return

    # 인스턴스가 종료되면 configuration이 None인 항목이 오는데, 이 검사가 없으면 아래의
    # .get('configuration', {}).get(...)이 AttributeError로 실패해 아무것도 보고되지 않고,
    # 종료된 인스턴스에 마지막 판정이 그대로 남음. 평가하지 않고 NOT_APPLICABLE로 보고함.
    if not is_applicable(configuration_item, event):
        config_client.put_evaluations(
            Evaluations=[{
                'ComplianceResourceType': configuration_item['resourceType'],
                'ComplianceResourceId': instance_id,
                'ComplianceType': 'NOT_APPLICABLE',
                'OrderingTimestamp': configuration_item['configurationItemCaptureTime']
            }],
            ResultToken=event['resultToken']
        )
        return 'NOT_APPLICABLE'

    compliance = "COMPLIANT"
    annotation = "Only AmazonS3ReadOnlyAccess Attached"

    iam_profile = configuration_item.get('configuration', {}).get('iamInstanceProfile')
    if not iam_profile:
        compliance = "NON_COMPLIANT"
        annotation = "No IAM instance profile attached."
    else:
        arn = iam_profile.get('arn', '')
        profile_name = arn.split('/')[-1] if arn else ''
        try:
            profile = iam_client.get_instance_profile(InstanceProfileName=profile_name)['InstanceProfile']
            roles = profile.get('Roles', [])
            if len(roles) != 1:
                compliance = "NON_COMPLIANT"
                annotation = "Instance profile must have exactly one role."
            else:
                for role in roles:
                    role_name = role['RoleName']
                    policies = get_attached_policies(role_name)
                    s3_policy_arn = 'arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess'
                    # 정책 목록 검사
                    if all(p['PolicyArn'] == s3_policy_arn for p in policies) and policies:
                        compliance = "COMPLIANT"
                    else:
                        compliance = "NON_COMPLIANT"
                        annotation = "AmazonS3ReadOnlyAccess 외 다른 정책이 존재함. 자동으로 제거 및 추가 수행."
                        config_client.put_evaluations(
                            Evaluations=[{
                                'ComplianceResourceType': configuration_item['resourceType'],
                                'ComplianceResourceId': instance_id,
                                'ComplianceType': compliance,
                                'OrderingTimestamp': configuration_item['configurationItemCaptureTime'],
                                'Annotation': annotation
                            }],
                            ResultToken=event['resultToken']
                        )
                        update_role_policies(role_name)
                        compliance = "COMPLIANT"
                        annotation = "Only AmazonS3ReadOnlyAccess Attached"
        except Exception as e:
            compliance = "NON_COMPLIANT"
            annotation = f"Error occurred: {e}"

    # AWS Config로 평가 결과 리포트
    config_client.put_evaluations(
        Evaluations=[{
            'ComplianceResourceType': configuration_item['resourceType'],
            'ComplianceResourceId': instance_id,
            'ComplianceType': compliance,
            'OrderingTimestamp': configuration_item['configurationItemCaptureTime'],
            'Annotation': annotation
        }],
        ResultToken=event['resultToken']
    )
    return compliance
