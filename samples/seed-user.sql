USE goosage_local;

-- 기존 있으면 삭제(선택)
DELETE FROM users WHERE email='fresh@test.com';

-- fresh 계정 생성
INSERT INTO users (email, password_hash, created_at)
VALUES (
  'fresh@test.com',
  '$2a$10$.3SioEeHWgLS7TnNdrkZbeBVpQbWxyqMON0MMynkRELNsiCyGQANa',
  NOW()
);

INSERT INTO users (email, password_hash)
VALUES ('goosage@example.com', '$2a$10$QSqPTkDFAZzEgj2ooM71TeHc3UM.OxvSicGr/fHz5OvcaHt9rYSFO')
ON DUPLICATE KEY UPDATE password_hash=VALUES(password_hash);
