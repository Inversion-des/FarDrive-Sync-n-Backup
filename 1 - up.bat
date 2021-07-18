@echo off
title Up
echo Up...
call run -up >> up.log  2>&1  ^
	&& echo ----- done ----- ^
	&& goto :end
echo ----- [x] failed -----

echo.
pause
:end
