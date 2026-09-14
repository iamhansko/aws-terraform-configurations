---
inclusion: always
---

# AWS Cloud Computing Rules

AWS Credentials는 `.aws/credentials.sh`를 조회하여 획득합니다. `.aws/credentials.sh`로부터 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SECRET_ACCESS_KEY` 각 환경변수 값을 추출합니다. 추출한 환경변수 값으로 AWS 작업을 수행합니다.