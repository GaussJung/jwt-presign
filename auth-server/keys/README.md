# keys/ — 개인키를 여기에 둔다

이 디렉토리는 **비어 있는 채로** 리포에 올라간다. 개인키는 공개 리포에 포함되지 않는다.

## 할 일
폐쇄 커뮤니티에서 받은 `jwt_private_key.pem` 을 이 폴더에 **그대로** 복사한다.

```
auth-server/keys/jwt_private_key.pem   ← 여기
```

- `jwt_private_key.pem` 은 `.gitignore` 로 커밋이 차단되어 있다(`*.pem`).
- 교육 전용 일회용 키이며 수업 후 폐기한다.
