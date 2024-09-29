@echo off
setlocal enabledelayedexpansion

set "fileName=%1"

if "%fileName%"=="" (
    echo fileName Not Empty!
     exit /b 1
) 


set "articlePath=content\posts\%fileName%.md"

if exist "!articlePath!" (
    echo Article already exists!
) else (
   cd ..
   hugo new content  content/posts/%fileName%.md"
   echo Article created: !articlePath!
)
