# Set Working Directory
Split-Path $MyInvocation.MyCommand.Path | Push-Location
[Environment]::CurrentDirectory = $PWD

Remove-Item "$env:RELOADEDIIMODS/AccessXI.PolReloaded/*" -Force -Recurse
dotnet publish "./AccessXI.PolReloaded.csproj" -c Release -o "$env:RELOADEDIIMODS/AccessXI.PolReloaded" /p:OutputPath="./bin/Release" /p:ReloadedILLink="true"

# Restore Working Directory
Pop-Location