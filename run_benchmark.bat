@echo off
REM Corre el benchmark completo y deja los entregables en la carpeta de arriba.
REM Usa %~dp0 para no depender de rutas con acentos.
cd /d "%~dp0"
if not exist results mkdir results
set GODOT="C:\Users\cristian\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
set RAR="C:\Program Files\WinRAR\Rar.exe"

%GODOT% --headless --path . res://game/benchmark_runner.tscn -- --repeats 5 --parallel 16 --speed 60 --out res://results > results\barrido.log 2>&1
echo TERMINADO_CON_CODIGO_%ERRORLEVEL% >> results\barrido.log

REM 1) El Excel del benchmark sube como entregable.
if exist results\benchmark.xlsx copy /Y results\benchmark.xlsx "..\Benchmark Smart Top Down.xlsx" >nul

REM 2) El proyecto se empaqueta con WinRAR, sin la cache de Godot.
REM    NO se usa Compress-Archive de PowerShell: escribe las rutas internas con
REM    backslash, cosa que el formato ZIP no permite, y Godot falla al extraer
REM    con "files failed extraction from package".
cd ..
if exist %RAR% (
  %RAR% a -r -m5 -y -x"Juego Godot\.godot\*" -x"Juego Godot\.godot" -- "Smart Top Down (Godot).rar" "Juego Godot\" >nul
  %RAR% t -- "Smart Top Down (Godot).rar" >nul
  if errorlevel 1 ( echo RAR_CORRUPTO >> "Juego Godot\results\barrido.log" ) else ( echo RAR_VERIFICADO >> "Juego Godot\results\barrido.log" )
) else (
  echo WINRAR_NO_ENCONTRADO_SIN_EMPAQUETAR >> "Juego Godot\results\barrido.log"
)

echo ENTREGABLES_LISTOS >> "Juego Godot\results\barrido.log"
