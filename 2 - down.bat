@echo off
title Down
echo Down...
call run -down >> down.log  ^
	&& echo ----- done ----- ^
	&& goto :end
echo ----- [x] failed -----

echo.
pause
:end
