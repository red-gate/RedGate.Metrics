[CmdletBinding()]
param(
  [Parameter(Mandatory = $False)]
  [bool] $IsDefaultBranch = $False,

  [Parameter(Mandatory = $False)]
  [string] $BranchName = "dev",

  # A url to a NuGet feed the package will be published to.
  [Parameter(Mandatory = $False)]
  [string] $NugetFeedToPublishTo,

  # The Api Key that allows pushing to the feed passed in as -NugetFeedToPublishTo.
  [Parameter(Mandatory = $False)]
  [string] $NugetFeedApiKey
)


$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Info($Message) {
    Write-Host "#### $Message ####" -ForegroundColor Yellow
}

Write-Info "Build parameters"
Write-Host "IsDefaultBranch = $IsDefaultBranch"
Write-Host "BranchName = $BranchName"

$RootDir = "$PsScriptRoot\.." | Resolve-Path
$outputDir = "$RootDir\.output"
$NuGetPath = "$PsScriptRoot\packages\NuGet.Commandline\tools\nuget.exe"

task GenerateVersionNumber {
  $versionTxt = $(Get-Content $PsScriptRoot\version.txt);
  $script:Version = [System.Version]"$versionTxt.0"

  if($env:BUILD_COUNTER) {
    # If running as a Teamcity build, load the main version info from Version.txt and append the
    # BUILD_NUMBER value as the revision number
    "Overriding version number using values from Version.txt ($versionTxt) and Revision number ($Env:BUILD_COUNTER)"

    $script:Version = [version]"$versionTxt.$env:BUILD_COUNTER"

    # Let Teamcity know we changed the build number
    TeamCity-SetBuildNumber $script:Version
  }

  $script:NugetPackageVersion = New-NugetPackageVersion -Version $script:Version -BranchName $BranchName -IsDefaultBranch $IsDefaultBranch

  "Version number is $script:Version"
  "Nuget packages Version number is $script:NugetPackageVersion"
}

task Clean {
  Write-Info 'Cleaning any prior build output'
  $script:NuGetPackagePath = ".\RedGate.Metrics.$Version.nupkg"
  if (Test-Path $NuGetPackagePath) {
    Write-Host "Deleting $NuGetPackagePath"
    Remove-Item $NuGetPackagePath
  }
  if (Get-Module 'RedGate.Metrics')
  {
    Write-Host 'Removing RedGate.Metrics module'
    Remove-Module 'RedGate.Metrics'
  }
}

task Pack Clean, GenerateVersionNumber, {
  # Package the RedGate.Metrics module.
  Write-Info 'Creating RedGate.Metrics NuGet package'
  New-Item $outputDir -ItemType Directory -Force | Out-Null
  exec { & $NuGetPath pack "$RootDir\RedGate.Metrics.nuspec" -NoPackageAnalysis -Version $NugetPackageVersion -OutputDirectory $outputDir -NoDefaultExcludes }
  if($LASTEXITCODE -ne 0) {
    throw "Could not nuget pack RedGate.Metrics. nuget returned exit code $LASTEXITCODE"
  }
  Write-Host
  $script:NuGetOutputPath = "$outputDir\RedGate.Metrics.$NugetPackageVersion.nupkg" | Resolve-Path 
  $NuGetOutputPath | Write-TeamCityPublishArtifact
}

# Synopsis: Run Pester tests.
task Tests Pack, {
    powershell.exe -Command "
        Import-Module '$RootDir\.build\packages\Pester\tools\Pester.psd1'
        Import-Module '$RootDir\RedGate.Metrics.psm1'
        `$results = Invoke-Pester -Script $RootDir\Tests\ -OutputFile $outputDir\TestResults.xml -OutputFormat NUnitXml -PassThru
        exit `$results.FailedCount"
    $testsFailed = $LASTEXITCODE
    Resolve-Path $outputDir\TestResults.xml | TeamCity-ImportNUnitReport
    if ($testsFailed) { Write-Error "$testsFailed test(s) failed." }
}

task Publish Pack, {
  if($NugetFeedToPublishTo -and $NugetFeedApiKey) {
    Write-Info 'Publishing RedGate.Metrics NuGet package'
    exec { & $NuGetPath push "$NuGetOutputPath" -Source $NugetFeedToPublishTo -ApiKey $NugetFeedApiKey }
  } else {
    Write-Info 'Skipping - Publishing RedGate.Metrics NuGet package'
  }
}

task . Pack, Tests, Publish
