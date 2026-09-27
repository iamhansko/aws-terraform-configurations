---
inclusion: always
---

# AWS Cloud Computing Rules

AWS 자격증명은 `.aws/credentials.sh`를 **source**해서 얻습니다. `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_DEFAULT_REGION` 네 변수 값이 모두 필요하며, 임시 자격증명이므로 `AWS_SESSION_TOKEN` 값이 빠지면 모든 호출이 실패합니다. 

Git Bash 환경에서는 `MSYS2_ENV_CONV_EXCL`로 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` 세 변수를 변환에서 제외해야 합니다. 그러지 않으면 `/`로 시작하는 값이 Windows 경로로 바뀌어 `SignatureDoesNotMatch` 오류가 발생합니다.

```bash
. .aws/credentials.sh
export MSYS2_ENV_CONV_EXCL='AWS_ACCESS_KEY_ID;AWS_SECRET_ACCESS_KEY;AWS_SESSION_TOKEN'
aws sts get-caller-identity
```