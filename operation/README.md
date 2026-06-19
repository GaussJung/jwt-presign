# operation/

auth-server 생명주기 관리 스크립트.

| 스크립트 | 역할 |
|---|---|
| `startup.sh` | auth-server 백그라운드 기동 (nohup · PID 기록) |
| `stop.sh` | auth-server 정지 (멱등) |

런타임 파일(`operation/.run/`)은 `.gitignore` 처리 — 리포에 포함되지 않습니다.

운영/유지보수 전체 절차: [docs/5_operation_maintenance_manual.md](../docs/5_operation_maintenance_manual.md)
