param(
    # The version of the nuget package.
    [Parameter(Mandatory = $False)]
    [string] $Version = '0.0.1',

    # True when building from master. If False, '-prerelease' is appended to the package version.
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

. "$PSScriptRoot\.build\_init.ps1"
Build -IsDefaultBranch $IsDefaultBranch -BranchName $BranchName -NugetFeedToPublishTo $NugetFeedToPublishTo -NugetFeedApiKey $NugetFeedApiKey