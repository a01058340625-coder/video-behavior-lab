$date = Get-Date -Format "yyyy-MM-dd"
$today = Get-Date -Format "yyyyMMdd"

& "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe" `
-h 127.0.0.1 -P 3306 -u root -p -D goosage `
-e "select user_id, count(*) cnt from study_events where date(created_at)=curdate() group by user_id order by user_id;"

mkdir ".\logs\$date" -ErrorAction SilentlyContinue
move .\coach.*$today*.json ".\logs\$date\" -ErrorAction SilentlyContinue

dir ".\logs\$date"