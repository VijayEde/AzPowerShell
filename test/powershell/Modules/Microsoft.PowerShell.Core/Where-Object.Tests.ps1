# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
Add-TestDynamicType

Describe "Where-Object" -Tags "CI" {
    BeforeAll {
        $Computers = @(
            [PSCustomObject]@{
                ComputerName = "SPC-1234"
                IPAddress = "192.168.0.1"
                NumberOfCores = 1
                Drives = 'C','D'
            },
            [PSCustomObject]@{
                ComputerName = "BGP-5678"
                IPAddress = ""
                NumberOfCores = 2
                Drives = 'C','D','E'
            },
            [PSCustomObject]@{
                ComputerName = "MGC-9101"
                NumberOfCores = 3
                Drives = 'C'
            }
        )

        $NullTestData = @(
            [PSCustomObject]@{
                Value = $null
            }
            [PSCustomObject]@{
                Value = [NullString]::Value
            }
            [PSCustomObject]@{
                Value = [DBNull]::Value
            }
            [PSCustomObject]@{
                Value = [System.Management.Automation.Internal.AutomationNull]::Value
            }
            [PSCustomObject]@{
                Value = @()
            }
            [PSCustomObject]@{
                Value = @($null)
            }
            [PSCustomObject]@{
                Value = @('Some value')
            }
            [PSCustomObject]@{
                Value = @(1, $null, 2, $null, 3)
            }
        )
    }

    It "Where-Object -Not Prop" {
        $Result = $Computers | Where-Object -Not 'IPAddress'
        $Result | Should -HaveCount 2
    }

    It 'Where-Object -FilterScript {$true -ne $_.Prop}' {
        $Result = $Computers | Where-Object -FilterScript {$true -ne $_.IPAddress}
        $Result | Should -HaveCount 2
    }

    It "Where-Object Prop" {
        $Result = $Computers | Where-Object 'IPAddress'
        $Result | Should -HaveCount 1
    }

    It 'Where-Object -FilterScript {$true -eq $_.Prop}' {
        $Result = $Computers | Where-Object -FilterScript {$true -eq $_.IPAddress}
        $Result | Should -HaveCount 1
    }

    It 'Where-Object -FilterScript {$_.Prop -contains Value}' {
        $Result = $Computers | Where-Object -FilterScript {$_.Drives -contains 'D'}
        $Result | Should -HaveCount 2
    }

    It 'Where-Object Prop -contains Value' {
        $Result = $Computers | Where-Object Drives -contains 'D'
        $Result | Should -HaveCount 2
    }

    It 'Where-Object -FilterScript {$_.Prop -in $Array}' {
        $Array = 'SPC-1234','BGP-5678'
        $Result = $Computers | Where-Object -FilterScript {$_.ComputerName -in $Array}
        $Result | Should -HaveCount 2
    }

    It 'Where-Object $Array -in Prop' {
        $Array = 'SPC-1234','BGP-5678'
        $Result = $Computers | Where-Object ComputerName -in $Array
        $Result | Should -HaveCount 2
    }

    It 'Where-Object -FilterScript {$_.Prop -ge 2}' {
        $Result = $Computers | Where-Object -FilterScript {$_.NumberOfCores -ge 2}
        $Result | Should -HaveCount 2
    }

    It 'Where-Object Prop -ge 2' {
        $Result = $Computers | Where-Object NumberOfCores -ge 2
        $Result | Should -HaveCount 2
    }

    It 'Where-Object -FilterScript {$_.Prop -gt 2}' {
        $Result = $Computers | Where-Object -FilterScript {$_.NumberOfCores -gt 2}
        $Result | Should -HaveCount 1
    }

    It 'Where-Object Prop -gt 2' {
        $Result = $Computers | Where-Object NumberOfCores -gt 2
        $Result | Should -HaveCount 1
    }

    It 'Where-Object -FilterScript {$_.Prop -le 2}' {
        $Result = $Computers | Where-Object -FilterScript {$_.NumberOfCores -le 2}
        $Result | Should -HaveCount 2
    }

    It 'Where-Object Prop -le 2' {
        $Result = $Computers | Where-Object NumberOfCores -le 2
        $Result | Should -HaveCount 2
    }

    It 'Where-Object -FilterScript {$_.Prop -lt 2}' {
        $Result = $Computers | Where-Object -FilterScript {$_.NumberOfCores -lt 2}
        $Result | Should -HaveCount 1
    }

    It 'Where-Object Prop -lt 2' {
        $Result = $Computers | Where-Object NumberOfCores -lt 2
        $Result | Should -HaveCount 1
    }

    It 'Where-Object -FilterScript {$_.Prop -Like Value}' {
        $Result = $Computers | Where-Object -FilterScript {$_.ComputerName -like 'MGC-9101'}
        $Result | Should -HaveCount 1
    }

    It 'Where-Object Prop -like Value' {
        $Result = $Computers | Where-Object ComputerName -like 'MGC-9101'
        $Result | Should -HaveCount 1
    }

    It 'Where-Object -FilterScript {$_.Prop -Match Pattern}' {
        $Result = $Computers | Where-Object -FilterScript {$_.ComputerName -match '^MGC.+'}
        $Result | Should -HaveCount 1
    }

    It 'Where-Object Prop -like Value' {
        $Result = $Computers | Where-Object ComputerName -match '^MGC.+'
        $Result | Should -HaveCount 1
    }

    It 'Where-Object should handle dynamic (DLR) objects' {
        $dynObj = [TestDynamic]::new()
        $Result = $dynObj, $dynObj | Where-Object FooProp -eq 123
        $Result | Should -HaveCount 2
        $Result[0] | Should -Be $dynObj
        $Result[1] | Should -Be $dynObj
    }

    It 'Where-Object should handle dynamic (DLR) objects, even without property name hint' {
        $dynObj = [TestDynamic]::new()
        $Result = $dynObj, $dynObj | Where-Object HiddenProp -eq 789
        $Result | Should -HaveCount 2
        $Result[0] | Should -Be $dynObj
        $Result[1] | Should -Be $dynObj
    }

    Context 'Where-Object Prop -is $null' {
        BeforeAll {
            $Result = $NullTestData | Where-Object Value -Is $null
        }

        It 'Should find all null matches' {
            $Result | Should -HaveCount 4
        }

        It 'Should have found a $null match' {
            $Result[0].Value -is $null | Should -BeTrue
            $Result[0].Value | Get-Member -ErrorAction Ignore | Should -BeNullOrEmpty
        }

        It 'Should have found a [NullString]::Value match' {
            $Result[1].Value | Should -BeOfType [NullString]
        }

        It 'Should have found a [DBNull]::Value match' {
            $Result[2].Value | Should -BeOfType [DBNull]
        }

        It 'Should have found a [S.M.A.Internal.AutomationNull]::Value match' {
            $Result[3].Value -is $null | Should -BeTrue
            $Result[3].Value | Get-Member -ErrorAction Ignore | Should -BeNullOrEmpty
        }
    }

    Context 'Where-Object Prop -isnot $null' {
        BeforeAll {
            $Result = $NullTestData | Where-Object Value -IsNot $null
        }

        It 'Should find all non-null matches' {
            $Result | Should -HaveCount 4
        }

        It 'Each non-null match should be of type array' {
            foreach ($item in $Result) {
                ,$item.Value | Should -BeOfType [array]
            }
        }
    }

}
