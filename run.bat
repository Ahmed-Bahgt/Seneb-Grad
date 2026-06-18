@echo off
REM Set Java 25 which has better SSL support
set JAVA_HOME=C:\Program Files\Java\jdk-25
REM Run flutter with Java 25
flutter %*
