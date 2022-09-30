@echo off
title Up
echo Up...
call run -up  ^
	&& echo ----- done ----- ^
	&& goto :end
echo ----- [x] failed -----

:end
echo.
pause
