@echo off
REM Corre el barrido completo del benchmark y deja los resultados en results\.
REM
REM Godot se busca en este orden:
REM   1. la variable de entorno GODOT, si la tienes puesta
REM   2. "godot" en el PATH
REM Si no aparece por ninguna de las dos vias, avisa y sale en vez de fallar
REM con un error del sistema a mitad de camino.
REM
REM Usa %~dp0 para no depender de rutas con acentos.

setlocal
cd /d "%~dp0"
if not exist results mkdir results

if defined GODOT goto :tengo_godot
where godot >nul 2>&1 && (set "GODOT=godot" & goto :tengo_godot)
echo No encuentro Godot.
echo Pon la ruta del ejecutable en la variable GODOT, por ejemplo:
echo     set GODOT=C:\ruta\a\Godot_v4.7.1-stable_win64_console.exe
echo o deja "godot" accesible desde el PATH.
exit /b 1

:tengo_godot
echo Usando Godot: %GODOT%
echo Esto tarda varias horas. Progreso: type results\barrido.log
"%GODOT%" --headless --path . res://game/benchmark_runner.tscn -- --repeats 5 --parallel 16 --speed 60 --out res://results > results\barrido.log 2>&1
echo TERMINADO_CON_CODIGO_%ERRORLEVEL% >> results\barrido.log
type results\barrido.log | findstr /C:"filas registradas" /C:"TERMINADO_CON_CODIGO"
endlocal
