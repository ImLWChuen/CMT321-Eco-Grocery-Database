@echo off
echo ============================================================
echo Connecting to Docker MySQL (eco_grocery_cmt321) on port 3307...
echo [TIP] End any query with \G instead of ; for neat vertical cards!
echo ============================================================
docker exec -it mysql-local mysql -u root -prootpassword -E --table eco_grocery_cmt321
pause
