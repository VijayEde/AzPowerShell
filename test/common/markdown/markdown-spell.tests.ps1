# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

Describe "Verify Markdown Spelling" {
    BeforeAll {
        if(!(Get-Command -Name 'mdspell' -ErrorAction SilentlyContinue))
        {
            start-nativeExecution {
                sudo npm install -g mdspell@latest
            }
        }

        # Cleanup jobs for reliability
        get-job | remove-job -force
    }

    AfterAll {
        # Cleanup jobs to leave the process the same
        get-job | remove-job -force
    }

    $groups = Get-ChildItem -Path "$PSScriptRoot\..\..\..\*.md" -Recurse | Where-Object {$_.DirectoryName -notlike '*node_modules*'} | Group-Object -Property directory

    $jobs = @{}
    # Start all spelling verification in parallel
    Foreach($group in $groups)
    {
        Write-Verbose -verbose "starting jobs for $($group.Name) ..."
        $job = Start-ThreadJob {
            param([object] $group)
            foreach($file in $group.Group)
            {
                $results = mdspell --en-us --ignore-numbers --ignore-acronyms --report $file 2>&1
                Write-Output ([PSCustomObject]@{
                    file = $file
                    results = $results
                })
            }
        } -ArgumentList @($group)
        $jobs.add($group.name,$job)
    }

    # Get the results and verify
    foreach($key in $jobs.keys)
    {
        $job = $jobs.$key
        $results = Receive-Job -Job $job -Wait
        Remove-job -job $Job
        foreach($jobResult in $results)
        {
            $file = $jobResult.file
            $result = $jobResult.results
            Context "Verify spelling in $file" {
                $failures = $result -like 'spelling errors found in'
                $passes = $result -like '*free of spelling*' | ForEach-Object {
                    @{spell=$_.Substring(4).Trim() }
                }
                $trueFailures = @()
                foreach ($failure in $failures) {
                    $trueFailures += @{spell = $failure}
                }

                # must have some code in the test for it to pass
                function noop {}

                if($passes)
                {
                    it "<spell> should work" -TestCases $passes {
                        noop
                    }
                }

                if($trueFailures)
                {
                    it "<spell> should work" -TestCases $trueFailures  {
                        param($spell)
                        throw "Tool reported spelling as wrong."
                    }
                }
            }
        }
    }
}
