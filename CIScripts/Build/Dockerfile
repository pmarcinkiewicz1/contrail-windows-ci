# escape=`
FROM microsoft/nanoserver

COPY artifacts.zip C:\
VOLUME C:\artifacts

CMD powershell -Command `
    Expand-Archive -Force -Path C:\artifacts.zip -DestinationPath C:\artifacts\
