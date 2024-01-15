<#
.SYNOPSIS
Build and publish a new Four Key Metrics report

.DESCRIPTION
Facade around Get-ReleaseMetricsForCheckout, Get-BucketedReleaseMetricsForReport, New-FourKetMetricsReport, and Publish-FourKeyMetricsReport

#>
function global:Invoke-FourKeyMetricsReportGeneration {
    [CmdletBinding()]
    param(
        # Optional. The API key of the Octopus Deploy server to push packages to. $null means don't publish to Octopus
        [string] $OctopusFeedApiKey,
        # The location of the checked out repository to analyse
        [Parameter(Mandatory=$true)]
        [string] $CheckoutLocation,
        # Name of the product we are reporting on (used as a label in reports)
        [Parameter(Mandatory=$true)]
        [string] $ProductName,
        # The pattern for annotated tags in fnmatch format for git log
        [Parameter(Mandatory=$true)]
        [string] $ReleaseTagPattern,
        # The pattern for fix tags - in powershell wild card format
        [Parameter(Mandatory=$true)]
        [string] $FixTagPattern,
        # Name for the report package we will deploy to Octopus
        [string] $ReportPackageName,
        # Version number to publish the report under
        [string] $ReportVersionNumber,
        # Optional. Filters commits to a particular set of sub directories for the product we are interested in
        [string[]] $RepoSubDirs = (""),
        # Optional. A start date to filter tags.  Only tags after this date will be used.
        [datetime] $StartDate = "01/01/2018",
        # Optional. How many months back to report on
        [int] $LookbackMonths = 12,
        # Optional. The size (in days) of the rolling window used for metric averaging
        [int] $WindowSizeDays = 30,
        # Optional. The interval (in days) between each point in the graph
        [int] $WindowIntervalDays = 7,
        # Optional. Location for report files to be created
        [string] $OutFilePath = ".",
        # Optional. Release/s to exclude from lead time analysis
        [string[]] $ignoreReleases = @(""),
        # Optional. Custom file name for report
        [string] $OutFileName = "index.html"
    )

    $releaseMetrics = Get-ReleaseMetricsForCheckout `
        -checkoutLocation $CheckoutLocation `
        -releaseTagPattern $ReleaseTagPattern `
        -fixTagPattern $FixTagPattern `
        -startDate $StartDate `
        -repoSubDirs $RepoSubDirs `
        -ignoreReleases $ignoreReleases

    $bucketedReleaseMetrics = Get-BucketedReleaseMetricsForReport `
        -lookbackMonths $LookbackMonths `
        -releaseMetrics $releaseMetrics `
        -windowSizeDays $WindowSizeDays `
        -windowIntervalDays $WindowIntervalDays

    $reportFile = New-FourKeyMetricsReport -metrics $bucketedReleaseMetrics -productName $ProductName -outFilePath $OutFilePath -windowSize "$windowSizeDays days" -OutFileName $outFileName

    if (PublishCredentialsProvided($OctopusFeedApiKey, $ReportPackageName, $ReportVersionNumber)) {
        Publish-FourKeyMetricsReport -reportFile $reportFile -packageName $ReportPackageName -octopusFeedApiKey $OctopusFeedApiKey -versionNumber $ReportVersionNumber
    }

    return $reportFile
}

<#
.SYNOPSIS
Calculate the 4 key metrics aka Accelerate metrics for a repo

.DESCRIPTION
Calculate the 4 key metrics aka Accelerate metrics for a repo

#>
function global:Get-ReleaseMetricsForCheckout {
    [CmdletBinding()]
    param(
        # The path to the repo
        [Parameter(Mandatory=$true)]
        [string]$checkoutLocation,
        # The pattern for annotated tags in fnmatch format for git log
        [Parameter(Mandatory=$true)]
        [string]$releaseTagPattern,
        # The pattern for fix tags - in powershell wild card format
        [Parameter(Mandatory=$true)]
        [string]$fixTagPattern,
        # A start date to filter tags.  Only tags after this date will be used.
        [datetime]$startDate,
        # Optional, case sensitive. Filters commits to a particular set of sub directories for use in mono-repos
        [string[]]$repoSubDirs = @(""),
        # Optional. Release/s to exclude from lead time analysis
        [string[]] $ignoreReleases = @("")
    )
    Push-Location $checkoutLocation

    $releases = Get-Releases $releaseTagPattern $fixTagPattern
    Get-ReleaseMetrics $releases $repoSubDirs $startDate $ignoreReleases

    Pop-Location
}

<#
.SYNOPSIS
Identify a list of releases, based on repository data
#>
function global:Get-Releases {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$releaseTagPattern,
        [Parameter(Mandatory=$true)]
        [string]$fixTagPattern
    )
    $gitCommand = "git for-each-ref --sort='-taggerdate' --format='%(taggerdate:iso8601),%(refname),' `"refs/tags/$releaseTagPattern`""
    $rawReleaseTags = Invoke-Expression $gitCommand

    if ($LastExitCode -ne 0) {
        throw "Exit code $LastExitCode returned by: $gitCommand"
    }

    foreach ($tag in $rawReleaseTags) {
        $split = $tag.Split(",")
        if ($split[0] -eq "") {
            Write-Warning "Tag $($split[1]) is a light-weight tag and will be ignored"
            continue
        }

        [PSCustomObject]@{
            TagRef   = $split[1];
            Date  = [DateTime]::ParseExact($split[0], "yyyy-MM-dd HH:mm:ss zzz", $null);
            IsFix = ($split[1] -like "refs/tags/$fixTagPattern")
        }
    }
}

<#
.SYNOPSIS
Calculate a set of release metrics for a given set of releases
#>
function global:Get-ReleaseMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$releases,
        [string[]]$subDirs,
        [Parameter(Mandatory=$true)]
        [string]$startDate,
        [string[]]$ignoreReleases
    )
    $thisRelease = $releases[0]
    for ($i = 1; $i -lt $releases.Count; $i++) {
        $lastRelease = $releases[$i]

        if (Assert-ReleaseShouldBeConsidered $ThisRelease.TagRef $ignoreReleases) {

            $CommitAges = Get-CommitsBetweenTags $lastRelease.TagRef $thisRelease.TagRef $subDirs | Foreach-Object -Process { $thisRelease.Date - $_.Date } 
        }
        else {
            
            $CommitAges = $null;
        }
        
        [PSCustomObject]@{
                From             = $lastRelease.TagRef;
                To               = $thisRelease.TagRef;
                FromDate         = $lastRelease.Date;
                ToDate           = $thisRelease.Date;
                Interval         = $thisRelease.Date - $lastRelease.Date;
                IsFix            = $thisRelease.IsFix;
                CommitAges       = $CommitAges;
        }

        if ($lastRelease.Date -le $startDate) {
            break
        }

        $thisRelease = $lastRelease
    }
}

function Assert-ReleaseShouldBeConsidered($thisReleaseTagRef, $ignoreReleases) {
    return !($ignoreReleases | Where-Object {$thisReleaseTagRef -Like "refs/tags/$_"})
}

<#
.SYNOPSIS
Get a list of all commits added to master between two release tags
#>
function Get-CommitsBetweenTags($start, $end, $subDirs) {
    $gitCommand = "git log --pretty=format:`"%h,%ai`" `"$start..$end`" --no-merges -- $subDirs"
    $rawCommits = Invoke-Expression $gitCommand

    if ($LastExitCode -ne 0) {
        throw "Exit code $LastExitCode returned by: $gitCommand"
    }

    foreach ($commit in $rawCommits) {
        $split = $commit.Split(",")
        [PSCustomObject]@{
            SHA  = $split[0];
            Date = [DateTime]::ParseExact($split[1], "yyyy-MM-dd HH:mm:ss zzz", $null)
        }
    }
}

function global:Get-BucketedReleaseMetricsForReport {
    [CmdletBinding()]
    param(
        # Pre-processed release metrics
        [PSCustomObject[]]$releaseMetrics,
        # Optional. How many months back to report on
        [int]$lookbackMonths = 12,
        # Optional. How large a rolling window to use
        [int]$windowSizeDays = 30,
        # Optional. The interval between windows
        [int]$windowIntervalDays = 7
    )    
    $now = (Get-Date)
    $earliestDate = $now.AddMonths(-$lookbackMonths)

    for ($endDate = $now; $endDate -gt $earliestDate; $endDate = $endDate.AddDays(-$windowIntervalDays)) {
        $startDate = $endDate.AddDays(-$windowSizeDays)
        $lookbackReleases = @($releaseMetrics | Where-Object { $_.ToDate -ge $startDate -AND $_.ToDate -le $endDate })

        Get-MetricsForPeriod $lookbackReleases $endDate
    }
}

<#
.SYNOPSIS
Calculate bucketed values for the Four Key Metrics, based on a provided set of releases
#>
function Get-MetricsForPeriod($releaseMetrics, $endDate) {
    $releaseCount = $releaseMetrics.Count
    $failedReleaseCount = @($releaseMetrics | Where-Object { $_.IsFix }).Count

    if ($releaseCount -gt 0){
        $deploymentFrequencyDays = ($releaseMetrics | ForEach-Object {$_.Interval.TotalDays} | Measure-Object -Average).Average;
        $failRate = $failedreleaseCount / $releaseCount
        $leadTimes = $releaseMetrics | Where-Object {$null -ne $_.CommitAges } | % { $_.CommitAges };
        $leadTimeMedian = Get-Median($leadTimes)       
    }
    else {
        $deploymentFrequencyDays = $null;
        $failRate = $null;
        $leadTimeMedian = $null;
    }

    if ($failedreleaseCount -gt 0){
        $mttrMeasures = $releaseMetrics | Where-Object { $_.IsFix } | ForEach-Object { $_.Interval.TotalHours } | Measure-Object -Average
        $mttrAverage = $mttrMeasures.Average;
    }
    else {
        $mttrAverage = $null;
    }

    [PSCustomObject]@{
        EndDate                 = $endDate
        Releases                = $releaseCount;
        DeploymentFrequencyDays = $deploymentFrequencyDays;
        MttrHours               = $mttrAverage;
        LeadTimeDays            = $leadTimeMedian;
        FailRate                = $failRate;
    }
}

function global:Get-Median($leadTimes){
    
    $orderedLeadTimes = $leadTimes | Sort-Object;       
    $numberOfCommitAges = $orderedLeadTimes.Count

    if ($numberOfCommitAges -gt 0) {

        $isEvenNumberOfCommitAges = $numberOfCommitAges % 2 -eq 0;

        if($isEvenNumberOfCommitAges) {
            $midh = [Math]::Floor($numberOfCommitAges / 2)
            return ($orderedLeadTimes[$midh-1].TotalDays + $orderedLeadTimes[$midh].TotalDays) / 2
        }
        else {
            $mid = [Math]::Floor($numberOfCommitAges / 2)
            return $orderedLeadTimes[$mid].TotalDays

        }
    }

    return $null
}

<#
.SYNOPSIS
Generate an HTML report showing the Four Key Metrics from the result of Get-FourKeyMetrics

.DESCRIPTION
Generate an HTML report showing the Four Key Metrics from the result of Get-FourKeyMetrics

#>
function global:New-FourKeyMetricsReport {
    [CmdletBinding()]
    param(
        # The output of Get-FourKeyMetrics
        [Parameter(Mandatory=$true)]
        $metrics,
        # Product name to show in the report
        [Parameter(Mandatory=$true)]
        [string]$productName,
        # The text to display in the window size caption
        [Parameter(Mandatory=$true)]
        [string]$windowSize,
        # Optional. Location for the output file to be created at
        [string]$outFilePath = ".",
        # Optional. File name for report
        [string]$outFileName = "index.html"
        
    )

    $reportStartDate = $metrics[0].EndDate
    $reportEndDate = $metrics[-1].EndDate
    $report = New-Item -Path $outFilePath -Name $outFileName -Force
    $data = ($metrics | ForEach-Object { ConvertTo-JsonWithJavascript $_ }) -join ",`r`n"
    Get-Content "$PSScriptRoot\FourKeyMetricsTemplate.html" -Raw | 
        ForEach-Object { 
            $_ -replace "DATA_PLACEHOLDER", ($data) `
               -replace "PRODUCTNAME_PLACEHOLDER", $productName `
               -replace "WINDOWSIZE_PLACEHOLDER", $windowSize `
               -replace "REPORTSTARTDATE_PLACEHOLDER", "new Date($(DateTimeToTimestamp($reportStartDate)))" `
               -replace "REPORTENDDATE_PLACEHOLDER", "new Date($(DateTimeToTimestamp($reportEndDate)))"
        } |
        Out-File $report -Encoding ASCII -Force
    return $report
}

function ConvertTo-JsonWithJavascript($period){
    "[new Date($(DateTimeToTimestamp($period.EndDate))), $(ValueOrNull($period.DeploymentFrequencyDays)), $(ValueOrNull($period.LeadTimeDays)), $(ValueOrNull($period.FailRate)), $(ValueOrNull($period.MttrHours))]"
}

function ValueOrNull($value)
{
    if ($null -eq $value) { "null" } else { $value }
}

function DateTimeToTimestamp($datetime){
    [Math]::Floor(1000 * (Get-Date -Date $datetime -UFormat %s))
}

function PublishCredentialsProvided($OctopusFeedApiKey, $ReportPackageName, $ReportVersionNumber)
{
    if ($ReportPackageName -eq '' -Or $OctopusFeedApiKey -eq '' -Or $ReportVersionNumber -eq '') {
        Write-Warning "Publish credentials not provided - skipping publish step"
        $false
    } else { $true }
}

<#
.SYNOPSIS
Creates a zip of the provided HTML report, and optionally uploads it to Octopus Deploy

.DESCRIPTION
Creates a zip file of the provided HTML report, ready to be saved as a TeamCity artefact
(done by consumer build scripts to avoid coupling this part of the system to TeamCity).
If the OctopusFeedApiKey is specified, this file is also uploaded to Octopus Deploy,
enabling ITOps to distibute it to internal systems (including http://acceleratemetrics.red-gate.com/).

#>
function global:Publish-FourKeyMetricsReport {
    [CmdletBinding()]
    param(
        # The output of New-FourKeyMetricsReport
        [Parameter(Mandatory=$true)]
        $reportFile,
        # Name to use for the Octopus Package. Recommend 'FourKeyMetrics-[ProductName]'.
        [Parameter(Mandatory=$true)]
        [string]$packageName,
        # Optional. API key for Octopus Deploy. $null/empty to skip publishing to Octopus
        [string]$OctopusFeedApiKey,
        # Semver-compatible version number for the Octopus package.
        [Parameter(Mandatory=$true)]
        [string]$versionNumber
    )

    $outputZip = "$($packageName -replace '\s', '').$($versionNumber).zip"

    Compress-Archive -Path $reportFile -CompressionLevel Optimal -DestinationPath $outputZip -Force

    if ($OctopusFeedApiKey)
    {
        try {
            $packagePath = Resolve-Path $outputZip
            $wc = new-object System.Net.WebClient
            $wc.UploadFile("https://octopus.red-gate.com/api/packages/raw?apiKey=$($OctopusFeedApiKey)", $packagePath) | Out-Null
        }
        catch {
            Write-Error  $_
            throw
        }
    }
}
