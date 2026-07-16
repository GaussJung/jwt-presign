# =============================================================================
# versions.tf — Terraform / Provider 버전 고정
# -----------------------------------------------------------------------------
# 왜 고정하나: 실습자 EC2마다 설치 시점이 달라도 동일한 동작을 보장하기 위해
#              메이저 버전을 고정한다(테라폼 코어 1.x, AWS Provider 6.x).
# =============================================================================
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # 6.x 필수: nodejs24.x 런타임이 provider 허용 목록에 6.x부터 수록됨
      # (5.x는 클라이언트 측 검증에서 nodejs22.x까지만 인정 → apply 전 단계에서 거부)
      version = "~> 6.0"
    }
    # Lambda 코드 zip 패키징용(기존 04 스크립트의 zip 명령을 대체)
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region
}
