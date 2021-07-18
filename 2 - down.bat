@echo off
title Down
echo Down...
call run -down >> down.log  2>&1  ^
	&& echo ----- done ----- ^
	&& goto :end
echo ----- [x] failed -----

echo.
pause
:end
