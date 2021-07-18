@echo off
chcp 1251 >nul
set ruby="platform/Ruby/bin/ruby"
call %ruby% app/app.rb %*
