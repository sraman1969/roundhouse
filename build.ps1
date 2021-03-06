#!/usr/bin/env pwsh

$MSBUILD=msbuild

$root = $PSScriptRoot;

$CODEDROP="$($root)/code_drop";
$LOGDIR="$($CODEDROP)/log";

$TESTOUTDIR="$($root)/product/roundhouse.tests/bin"

$onAppVeyor = $("$($env:APPVEYOR)" -eq "True");

Push-Location $root


"`n"
" * Generating version number"
$gitVersion = (gitversion | ConvertFrom-Json)

If ($onAppVeyor) {
    $newVersion="$($gitVersion.FullSemVer)"
    Write-host "   - Updating appveyor build version to: $newVersion"
    $env:APPVEYOR_BUILD_VERSION="$newVersion"
    appveyor UpdateBuild -Version "$newVersion"
}

" * Restoring nuget packages"
nuget restore -NonInteractive -Verbosity quiet

# Create output and log dirs if they don't exist (don't know why this is necessary - works on my box...)
If (!(Test-Path $CODEDROP)) {
    $null = mkdir $CODEDROP;
}
If (!(Test-Path $LOGDIR)) {
    $null = mkdir $LOGDIR;
}

" * Extracting keywords.txt so that MySql works after ILMerge"

$file = $(Get-ChildItem -Recurse -Include MySql.Data.dll ~/.nuget/packages/mysql.data/ | Select-Object -Last 1)
& "$root/build/Extract-Resource.ps1" -File $file -ResourceName MySql.Data.keywords.txt -OutFile generated/MySql.Data/keywords.txt


" * Building and packaging"
msbuild /t:"Build" /p:DropFolder=$CODEDROP /p:Version="$($gitVersion.FullSemVer)" /p:NoPackageAnalysis=true /nologo /v:q /fl /flp:"LogFile=$LOGDIR/msbuild.log;Verbosity=n" /p:Configuration=Build /p:Platform="Any CPU"

"`n    - Packaging net461 packages`n"

nuget pack product/roundhouse.console/roundhouse.nuspec -OutputDirectory "$CODEDROP/packages" -Properties "mergedExe=$CODEDROP/merge/rh.exe" -Verbosity quiet -NoPackageAnalysis -Version "$($gitVersion.FullSemVer)" 
msbuild /t:"Pack" product/roundhouse.lib.merged/roundhouse.lib.merged.csproj  /p:DropFolder=$CODEDROP /p:Version="$($gitVersion.FullSemVer)" /p:NoPackageAnalysis=true /nologo /v:q /fl /flp:"LogFile=$LOGDIR/msbuild.roundhouse.lib.pack.log;Verbosity=n" /p:Configuration=Build /p:Platform="Any CPU"
msbuild /t:"Pack" product/roundhouse.tasks/roundhouse.tasks.csproj  /p:DropFolder=$CODEDROP /p:Version="$($gitVersion.FullSemVer)" /p:NoPackageAnalysis=true /nologo /v:q /fl /flp:"LogFile=$LOGDIR/msbuild.roundhouse.tasks.pack.log;Verbosity=n" /p:Configuration=Build /p:Platform="Any CPU"

"`n    - Packaging netcoreapp2.1 global tool dotnet-roundhouse`n"

dotnet publish -v q --no-restore product/roundhouse.console -p:Version="$($gitVersion.FullSemVer)" -p:NoPackageAnalysis=true -p:TargetFramework=netcoreapp2.1 -p:Version="$($gitVersion.FullSemVer)" -p:RunILMerge=false -p:Configuration=Build -p:Platform="Any CPU"
dotnet pack -v q --no-restore product/roundhouse.console -p:NoPackageAnalysis=true -p:TargetFramework=netcoreapp2.1 -o $CODEDROP/packages -p:Version="$($gitVersion.FullSemVer)" -p:RunILMerge=false -p:Configuration=Build -p:Platform="Any CPU"


# AppVeyor runs the test automagically, no need to run explicitly with nunit-console.exe. 
# But we want to run the tests on localhost too.
If (! $onAppVeyor) {

    "`n * Running unit tests`n"

    # Find test projects
    $testProjects = $(dir -r -i *.tests.csproj)

    $testProjects | % {
        Push-Location $_.Directory
        dotnet test -v q
        Pop-Location
    }
}

Pop-Location
