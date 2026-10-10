# Step Functions

## Overview
입력 데이터를 Lambda로 검증·처리하고 결과를 SNS로 알리는 Step Functions(STANDARD) 상태 머신 데모입니다.

- `ValidateData`(Lambda) → `IsValid`(Choice) → `ProcessData`(Lambda) → `NotifySucceeded`(SNS), 검증에 실패하면 `NotifyFailed`(SNS)
- 실행 시작용 Lambda를 `aws_lambda_invocation`으로 호출해서, `terraform apply` 중에 데모 실행 2개(유효한 입력 / `age = 0`인 무효 입력)를 시작합니다
- 무효 입력도 실행 자체는 `SUCCEEDED`로 끝나고 `NotifyFailed` 분기를 탑니다. 검증 실패와 실행 실패가 다르다는 것이 이 데모의 요점입니다
- Lambda 3개와 상태 머신의 로그 그룹을 보존 기간과 함께 선언합니다(`log_retention_days`, 기본 14일)

## Apply
```bash
terraform init
terraform apply
# 알림 메일을 받으려면
terraform apply -var 'notification_email_addresses=["me@example.com"]'
```

- 이메일 구독은 확인 링크를 클릭하기 전까지 `PendingConfirmation` 상태이고 아무것도 전달하지 않습니다. 기본값(구독 없음)에서는 알림 상태가 성공해도 메시지는 버려집니다
- 데모 실행은 `demo_executions`(또는 상태 머신 ARN)가 바뀔 때만 다시 시작되고, 변경 없는 apply에서는 반복되지 않습니다
- 실행 결과는 `terraform output`의 `list_executions_command`, `describe_execution_commands`, `execution_history_commands`로 확인합니다

## Destroy
```bash
terraform destroy
```

- destroy는 실행 시작용 Lambda를 다시 호출하지 않습니다. 상태 머신, 함수 3개, 토픽, IAM 역할, 로그 그룹이 함께 삭제됩니다
