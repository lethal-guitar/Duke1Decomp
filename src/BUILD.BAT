@echo off

set TCROOT=C:\TC20

TASM /d__LARGE__ /i%TCROOT%\STARTUP /ml C0.ASM
if errorlevel 1 goto err

TCC -ml -Z -G -O -1- -f- -K -c GAME.C
if errorlevel 1 goto err

TLINK /c /d /s C0.OBJ GAME.OBJ, DNDECOMP.EXE, , %TCROOT%\LIB\CL.LIB

:err
