#requires -Version 4 -Modules Pester

. ../Public/FourKeyMetrics.ps1

Describe 'Check median calculations' {
    Context 'Misc Tests' {
            It 'should work for 2 ordered values' {
                $median = Get-Median @(New-TimeSpan -days 1; New-TimeSpan -days 2)
                $median | Should -Be 1.5 
            }
            It 'should work for 2 unordered values' {
                $median = Get-Median @(New-TimeSpan -days 2; New-TimeSpan -days 1)
                $median | Should -Be 1.5 
            }
            It 'should work for 3 ordered values' {
                $median = Get-Median @(New-TimeSpan -D 0; New-TimeSpan -D 2; New-TimeSpan -D 3)
                $median | Should -Be 2
            }
            It 'should work for 3 unordered values' {
                $median = Get-Median @(New-TimeSpan -D 2; New-TimeSpan -D 3; New-TimeSpan -D 0)
                $median | Should -Be 2
            }
            It 'should work for 4 ordered values' {
                $median = Get-Median @(New-TimeSpan -D 1; New-TimeSpan -D 2; New-TimeSpan -D 3; ; New-TimeSpan -D 4)
                $median | Should -Be 2.5
            }
            It 'should work for 4 unordered values' {
                $median = Get-Median @(New-TimeSpan -D 2; New-TimeSpan -D 4; New-TimeSpan -D 3; New-TimeSpan -D 1)
                $median | Should -Be 2.5
            }
    }
}
Describe 'Get-BucketedMetricsForPeriod' {
    Context 'Given no releases' {
        $releases = @()

        $endDate = [DateTime]"2019-05-21";

        $bucketedMetrics = Get-BucketedMetricsForPeriod $releases $endDate

        It 'should return an empty set of metrics' {
            $bucketedMetrics.Releases | Should -Be "0" # Explicitly provide zero releases
            $bucketedMetrics.DeploymentFrequencyDays | Should -Be $null
            $bucketedMetrics.MttrHours | Should -Be $null
            $bucketedMetrics.LeadTimeDays | Should -Be $null
            $bucketedMetrics.FailRate | Should -Be $null
            $bucketedMetrics.EndDate | Should -Be $endDate
        }
    }

    Context 'Given a single release' {
        $release = [PSCustomObject]@{
            From            = "releases/0.1";
            To              = "releases/0.2";
            FromDate        = [DateTime]"2019-05-16";
            ToDate          = [DateTime]"2019-05-17";
            Interval        = New-Timespan -D 14;
            IsFix           = $false;
            CommitAges      = @(New-Timespan -H 24);
        }
    
        $releases = @($release)

        It 'should return bucketed metrics equal to the metrics of that release' {
            $endDate = [DateTime]"2019-05-17"

            $bucketedMetrics = Get-BucketedMetricsForPeriod $releases $endDate

            $bucketedMetrics.Releases | Should -Be "1" # Explicitly provide one release
            $bucketedMetrics.DeploymentFrequencyDays | Should -Be "14" # Only 1 release, so the deployment frequency should be the same as the release interval
            $bucketedMetrics.MttrHours | Should -Be $null # No recoveries in the provided dataset
            $bucketedMetrics.LeadTimeDays | Should -Be "1" # Release has a lead time of one day
            $bucketedMetrics.FailRate | Should -Be "0" # No failures
            $bucketedMetrics.EndDate | Should -Be $endDate
        }

        It 'should not degrade the deployment frequency as time passes' {
            $endDate = [DateTime]"2019-05-21"

            $bucketedMetrics = Get-BucketedMetricsForPeriod $releases $endDate

            $bucketedMetrics.Releases | Should -Be "1" # Explicitly provide one release
            $bucketedMetrics.DeploymentFrequencyDays | Should -Be "14" # Only 1 release, so the deployment frequency should be the same as the release interval
            $bucketedMetrics.MttrHours | Should -Be $null # No recoveries in the provided dataset
            $bucketedMetrics.LeadTimeDays | Should -Be "1" # Release has a lead time of one day
            $bucketedMetrics.FailRate | Should -Be "0" # No failures
            $bucketedMetrics.EndDate | Should -Be $endDate
        }
    }

    Context 'Given a couple of releases' {
        $releaseTwo = [PSCustomObject]@{
            From            = "releases/0.2";
            To              = "releases/0.3/fix";
            FromDate        = [DateTime]"2019-05-17"
            ToDate          = [DateTime]"2019-05-21"
            Interval        = New-Timespan -D 4;
            IsFix           = $true;
            CommitAges      = @(New-Timespan -H 24);
        }
        
        $releaseOne = [PSCustomObject]@{
            From            = "releases/0.1";
            To              = "releases/0.2";
            FromDate        = [DateTime]"2019-05-16"
            ToDate          = [DateTime]"2019-05-17"
            Interval        = New-Timespan -D 1;
            IsFix           = $false;
            CommitAges      = @(New-Timespan -H 24);
        }
    
        $releases = @($releaseTwo, $releaseOne)

        $endDate = [DateTime]"2019-05-21"

        $bucketedMetrics = Get-BucketedMetricsForPeriod $releases $endDate

        It 'should calculate the correct bucketed metrics' {
            $bucketedMetrics.Releases | Should -Be "2" # Explicitly provide two releases
            $bucketedMetrics.DeploymentFrequencyDays | Should -Be "2.5" # Release intervals were 1 and 4, so average is 2.5
            $bucketedMetrics.MttrHours | Should -Be 96 # Single recovery took four whole days
            $bucketedMetrics.LeadTimeDays | Should -Be "1" # Both releases have a lead time of one day
            $bucketedMetrics.FailRate | Should -Be "0.5" # One of two releases was a failure
            $bucketedMetrics.EndDate | Should -Be $endDate
        }
    }
}

Describe 'Get-BucketedReleaseMetricsForReport' {
    Context 'Given multiple releases, a lookback period of 1 month, a window size of 14 days, and a window interval of 7 days' {
        $releases = @(
            [PSCustomObject]@{
                From            = "releases/0.0";
                To              = "releases/0.1";
                FromDate        = [DateTime]"2019-04-01"
                ToDate          = [DateTime]"2019-05-13"
                Interval        = New-Timespan -D 42;
                IsFix           = $false;
                CommitAges      = @(New-Timespan -D 20);},
            [PSCustomObject]@{
                From            = "releases/0.1";
                To              = "releases/0.2";
                FromDate        = [DateTime]"2019-05-13"
                ToDate          = [DateTime]"2019-05-21"
                Interval        = New-Timespan -D 8;
                IsFix           = $false;
                CommitAges      = @(New-Timespan -D 3.5);},
            [PSCustomObject]@{
                From            = "releases/0.2";
                To              = "releases/0.3/fix";
                FromDate        = [DateTime]"2019-05-21"
                ToDate          = [DateTime]"2019-05-22"
                Interval        = New-Timespan -D 1;
                IsFix           = $true;
                CommitAges      = @(New-Timespan -D 0.5);},
            [PSCustomObject]@{
                From            = "releases/0.3/fix";
                To              = "releases/0.4";
                FromDate        = [DateTime]"2019-05-22"
                ToDate          = [DateTime]"2019-05-28"
                Interval        = New-Timespan -D 6;
                IsFix           = $false;
                CommitAges      = @(New-Timespan -D 2);},
            [PSCustomObject]@{
                From            = "releases/0.4";
                To              = "releases/0.5";
                FromDate        = [DateTime]"2019-05-28"
                ToDate          = [DateTime]"2019-06-04"
                Interval        = New-Timespan -D 7;
                IsFix           = $false;
                CommitAges      = @(New-Timespan -D 4);}
            );        

        Mock Get-Date { return [DateTime]"2019-06-07"}

        $metrics = Get-BucketedReleaseMetricsForReport $releases -lookbackMonths 1 -windowSizeDays 14 -windowIntervalDays 7 | Sort-Object -Property EndDate -Descending

        It 'should provide results for windows going back for a month at 7 day intervals starting at the current date' {
            $metrics | ForEach-Object { $_.EndDate } | Should -Be @(
                [DateTime]"2019-06-07", #24-May to 7-Jun
                [DateTime]"2019-05-31", #17-May to 31-May
                [DateTime]"2019-05-24", #10-May to 24-May
                [DateTime]"2019-05-17", # 3-May to 17-May
                [DateTime]"2019-05-10") # 26-Apr to 10-May
        }

        It 'should provide values looking back over the 14 day window' {
            $metrics | ForEach-Object { $_.Releases }                | Should -Be @(2,     3,    3,    1,    0    )
            $metrics | ForEach-Object { $_.DeploymentFrequencyDays } | Should -Be @(6.5,   5,    17,   42,   $null)
            $metrics | ForEach-Object { $_.LeadTimeDays }            | Should -Be @(3,     2,    4,    20,   $null)
            $metrics | ForEach-Object { $_.FailRate }                | Should -Be @(0,    (1/3),(1/3), 0,    $null)
            $metrics | ForEach-Object { $_.MttrHours }               | Should -Be @($null, 24,   24,  $null, $null)
        }
    }
}

Describe 'Assert-ReleaseShouldBeConsidered' {
    Context 'Given no releases should be ignored' {
        $ignoreReleases = @()

        It 'should return true for a given release' {
            $val = Assert-ReleaseShouldBeConsidered "refs/tags/someTag" $ignoreReleases
            $val | Should -Be $true
        }
    }
    Context 'Given one releases should be ignored' {
        $ignoreReleases = @("releaseToIgnore")

        It 'should return false for a the ignored release' {
            $val = Assert-ReleaseShouldBeConsidered "refs/tags/releaseToIgnore" $ignoreReleases
            $val | Should -Be $false
        }

        It 'should return true for another release' {
            $val = Assert-ReleaseShouldBeConsidered "refs/tags/someTag" $ignoreReleases
            $val | Should -Be $true
        }
    }
    Context 'Given two releases should be ignored' {
        $ignoreReleases = @("releaseToIgnore", "anotherReleaseToIgnore")

        It 'should return false for an ignored release' {
            $val = Assert-ReleaseShouldBeConsidered "refs/tags/anotherReleaseToIgnore" $ignoreReleases
            $val | Should -Be $false
        }

        It 'should return true for another release' {
            $val = Assert-ReleaseShouldBeConsidered "refs/tags/someTag" $ignoreReleases
            $val | Should -Be $true
        }
    }
}

Describe 'Get-Releases' {
    Context 'When run outside a git repo' {
        Mock git { $Global:LastExitCode = 128 }

        It 'should warn the user and exit' {
            { Get-Releases 'releaseTagPattern' 'fixtagPattern' } | Should -Throw
        }

        $Global:LastExitCode = 0
    }
    Context 'Given no releases' {
        Mock git { return $null }

        It 'should return an empty list of releases' {
            $releases = Get-Releases 'releaseTagPattern' 'fixtagPattern'
            $releases.Count | Should -Be 0
        }
    }
    Context 'Given a lightweight tag' {
        Mock git { return ",,refs/tags/lightweight-tag"}
        It 'should ignore that tag' {
            $releases = Get-Releases 'releaseTagPattern' 'fixTagPattern'
            $releases.Count | Should -Be 0
        }
    }
    Context 'Given one release' {
        Mock git { return ("2019-06-11 12:11:25 +0100,refs/tags/releases/5.0.3.1680,")}
        $expectedDate = [DateTime]::ParseExact("2019-06-11 12:11:25 +0100", "yyyy-MM-dd HH:mm:ss zzz", $null);

        It 'should return a single release' {
            $releases = Get-Releases 'releaseTagPattern' 'fixtagPattern'
            $releases.TagRef | Should -Be "refs/tags/releases/5.0.3.1680"
            $releases.Date | Should -Be $expectedDate
            $releases.IsFix | Should -Be $false
        }
    }
    Context 'Given a hotfix release' {
        Mock git { return ("2019-06-11 12:11:25 +0100,refs/tags/releases/5.0.3.1680/fix")}
        $expectedDate = [DateTime]::ParseExact("2019-06-11 12:11:25 +0100", "yyyy-MM-dd HH:mm:ss zzz", $null);

        It 'should return a single hotfix release' {
            $releases = Get-Releases 'releaseTagPattern' 'releases/**/fix'
            $releases.TagRef | Should -Be "refs/tags/releases/5.0.3.1680/fix"
            $releases.Date | Should -Be $expectedDate
            $releases.IsFix | Should -Be $true
        }
    }
    Context 'Given two releases' {
        Mock git { return (
            "2019-06-11 12:11:25 +0100,refs/tags/releases/5.0.3.1680,",
            "2019-06-03 10:34:37 +0100,refs/tags/releases/5.0.2.1664,")}
        $firstExpectedDate = [DateTime]::ParseExact("2019-06-11 12:11:25 +0100", "yyyy-MM-dd HH:mm:ss zzz", $null);
        $secondExpectedDate = [DateTime]::ParseExact("2019-06-03 10:34:37 +0100", "yyyy-MM-dd HH:mm:ss zzz", $null);

        It 'should return a two releases, with the newest release first' {
            $releases = Get-Releases 'releaseTagPattern' 'fixtagPattern'
            $releases.Count | Should -Be 2
            $releases[0].TagRef | Should -Be "refs/tags/releases/5.0.3.1680"
            $releases[0].Date | Should -Be $firstExpectedDate
            $releases[0].IsFix | Should -Be $false
            $releases[1].TagRef | Should -Be "refs/tags/releases/5.0.2.1664"
            $releases[1].Date | Should -Be $secondExpectedDate
            $releases[1].IsFix | Should -Be $false
        }
    }
}

Describe 'Get-CommitsBetweenTags' {
    Context 'Given invalid tags' {
        Mock git {$Global:LastExitCode = 128}
        It 'should throw an error' {
            {Get-CommitsBetweenTags 'releases/1' 'releases/2' '.'} | Should -Throw
        }

        $Global:LastExitCode = 0
    }

    Context 'Given 0 commits' {
        Mock git {return $null}
        It 'should return nothing' {
            $commits = Get-CommitsBetweenTags 'releases/1' 'releases/2' '.'
            $commits | Should -BeNullOrEmpty
        }
    }

    Context 'Given 2 commits' {
        Mock git {return (
            "b78adbc2f,2020-08-25 09:15:30 +0000",
            "17d887ea7,2020-08-25 10:54:28 +0100"
        )}

        It 'should return two parsed commit objects' {
            $commits = Get-CommitsBetweenTags 'releases/1' 'releases/2' '.'
            $commits | Should -HaveCount 2
            $commits[0].SHA | Should -Be "b78adbc2f"
            $commits[0].Date | Should -Be ([DateTime]::ParseExact("2020-08-25 09:15:30 +0000", "yyyy-MM-dd HH:mm:ss zzz", $null))
            $commits[1].SHA | Should -Be "17d887ea7"
            $commits[1].Date | Should -Be ([DateTime]::ParseExact("2020-08-25 10:54:28 +0100", "yyyy-MM-dd HH:mm:ss zzz", $null))
        }
    }
}

Describe 'ValueOrNull' {
    Context 'Given a value' {
        It 'should return that value' {
            ValueOrNull(5) | Should -Be 5
        }
    }
    Context 'Given the string "null"' {
        It 'should return that string' {
            ValueOrNull('null') | Should -Be 'null'
        }
    }
    Context 'Given an empty string' {
        It 'should return the empty string'{
            ValueOrNull('') | Should -Be ''
        }
    }
    Context 'Given $null' {
        It 'should return the string "null"' {
            ValueOrNull($null) | Should -Be "null"
        }
    }
}