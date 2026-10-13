---
inclusion: always
---

# GitHub Rules

GitHub 사용자 이름과 GitHub Personal Access Token(PAT)은 `.aws/github.sh`를 **source**해서 얻습니다. GitHub 사용자 이름은 `GITHUB_ACTOR` 변수 값, GitHub Personal Access Token(PAT)은 `GITHUB_TOKEN` 변수 값에 기록되어 있습니다.

Git Bash 환경에서는 `MSYS2_ENV_CONV_EXCL`로 `GITHUB_TOKEN` 변수를 변환에서 제외해야 합니다. 그러지 않으면 `/`로 시작하는 값이 Windows 경로로 바뀌어 `SignatureDoesNotMatch` 오류가 발생합니다.

```bash
. .aws/github.sh
export MSYS2_ENV_CONV_EXCL='GITHUB_TOKEN'
```