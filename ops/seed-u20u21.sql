INSERT INTO users(id,email,password_hash)
VALUES
(20,'u20@goosage.test','x'),
(21,'u21@goosage.test','x')
ON DUPLICATE KEY UPDATE
email=VALUES(email),
password_hash=VALUES(password_hash);
