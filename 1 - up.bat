@echo off
title Up
echo Up...
call run -up >> up.log  ^
	&& echo ----- done ----- ^
	&& goto :end
echo ----- [x] failed -----

echo.
pause
:end
