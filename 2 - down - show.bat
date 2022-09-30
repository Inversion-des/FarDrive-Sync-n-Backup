@echo off
title Down
echo Down...
call run -down ^
	&& echo ----- done ----- ^
	&& goto :end
echo ----- [x] failed -----

:end
echo.
pause
