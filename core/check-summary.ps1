docker exec goosage-mysql mysql -uroot -proot123 goosage -e "
SELECT
  user_id,
  COUNT(*) AS events,
  SUM(type = 'JUST_OPEN') AS opens,
  SUM(type = 'QUIZ_SUBMIT') AS quiz,
  SUM(type = 'REVIEW_WRONG') AS wrong,
  SUM(type = 'WRONG_REVIEW_DONE') AS wrong_done
FROM study_events
GROUP BY user_id
ORDER BY user_id;
"