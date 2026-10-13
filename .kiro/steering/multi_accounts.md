# Multi-account Architecture

교차 계정 또는 다중 계정으로 구성된 AWS 아키텍처의 경우, `.aws/credentials.sh`와 `.aws/extra.sh` 파일을 사용하여 AWS 계정 2개의 자격증명을 얻습니다. 기본(Primary) AWS 계정의 자격증명을 `.aws/credentials.sh`를 **source**해서 획득하고, 보조(Secondary) AWS 계정의 자격증명을 `.aws/extra.sh`를 **source**해서 획득합니다. 기본 계정과 보조 계정 모두 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_DEFAULT_REGION` 네 변수 값이 필요하며, 임시 자격증명이므로 `AWS_SESSION_TOKEN` 값이 빠지면 모든 호출이 실패합니다.

Git Bash 환경에서는 `MSYS2_ENV_CONV_EXCL`로 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` 세 변수를 변환에서 제외해야 합니다. 그러지 않으면 `/`로 시작하는 값이 Windows 경로로 바뀌어 `SignatureDoesNotMatch` 오류가 발생합니다.

## 기본(Primary) AWS 계정
```bash
. .aws/credentials.sh
export MSYS2_ENV_CONV_EXCL='AWS_ACCESS_KEY_ID;AWS_SECRET_ACCESS_KEY;AWS_SESSION_TOKEN'
aws sts get-caller-identity
```

## 보조(Secondary) AWS 계정
```bash
. .aws/extra.sh
export MSYS2_ENV_CONV_EXCL='AWS_ACCESS_KEY_ID;AWS_SECRET_ACCESS_KEY;AWS_SESSION_TOKEN'
aws sts get-caller-identity
```