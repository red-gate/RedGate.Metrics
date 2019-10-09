#Requires -Version 4.0

$ErrorActionPreference = 'Stop'
# Ignoring progress stream is vital to keep the performance
# of Invoke-WebRequest decent in Teamcity
$ProgressPreference = 'SilentlyContinue'

function global:RestoreBuildLevelPackages {
    # Download paket.exe.
    # Use --prefer-nuget to get it from nuget.org first as it is quicker (compressed .nupkg)
    $paketVersion = "" # Set this to the value of a specific version of paket.exe to download if need be.
    & "$PSScriptRoot\paket.bootstrapper.exe" $paketVersion --prefer-nuget

    Push-Location $PsScriptRoot -verbose
    try {
        & "$PSScriptRoot\paket.exe" install
        if($LASTEXITCODE -ne 0) {
            throw "paket install exited with code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

<#
.SYNOPSIS
Build RedGate.Metrics.

.DESCRIPTION
This is really a wrapper around build.ps1 (build.ps1 is our actual build script. E.g.(the script that tells you how to build this crazy thing)
2 main steps:
    1 - Restore nuget packages that are needed to get our build engine/tools.
    2 - Execute the build. (Invoke-Build build.ps1)

In theory, Teamcity will also use this build command. Probably like this: 'build -Task Build'

.EXAMPLE
build -Task Compile, UnitTests
Run the build script and only execute the 'Compile' and 'UnitTests' tasks.

.EXAMPLE
build
The simplest example! Just execute the build with default values for the -Task parameter.
#>
function global:Build {
    [CmdletBinding()]
    param(
        # The Tasks to execute. '.' means the default task as defined in build.ps1
        [string[]] $Task = @('.'),
        # The Configuration to build. Either Release or Debug
        [ValidateSet('Release', 'Debug')]
        [string] $Configuration = 'Release',
        # The name of the branch we are building (Set by Teamcity).
        # Will be set by Teamcity. Defaults to 'dev' for local developer builds.
        [string] $BranchName = 'dev',
        # Indicates whether or not BranchName represents the default branch for the source control system currently in use.
        # Will be set by Teamcity. Defaults to $false for local developer builds.
        [bool] $IsDefaultBranch = $false,
        # (Optional) URL to the nuget feed to publish nuget packages to.
        # Will be set by Teamcity.
        [string] $NugetFeedToPublishTo,
        # (Optional) Api Key to the nuget feed to be able to publish nuget packages.
        # Will be set by Teamcity.
        [string] $NugetFeedApiKey,
        # (Optional) Signing service url used to sign dll/exe.
        [string] $SigningServiceUrl,
        # (Optional) A GitHub API Access token used for Pushing and PRs
        [string] $GithubAPIToken
    )

    RestoreBuildLevelPackages

    Push-Location $PsScriptRoot -verbose
    try
    {
      Import-Module '.\packages\RedGate.Build\tools\RedGate.Build.psm1' -Force -DisableNameChecking
      
      # Call the actual build script
      & '.\packages\Invoke-Build\tools\Invoke-Build.ps1' `
        -File "$PsScriptRoot\build.ps1" `
        -Task $Task `
        -IsDefaultBranch $IsDefaultBranch `
        -BranchName $BranchName `
        -NugetFeedToPublishTo $NugetFeedToPublishTo `
        -NugetFeedApiKey $NugetFeedApiKey
    }
    finally
    {
      Pop-Location
    }
}

Write-Host "This is the RedGate.Metrics repo. And here are the available commands:" -Fore Magenta
Write-Host "`t build" -Fore Green
Write-Host "For more info, use help <command-name>" -Fore Magenta
