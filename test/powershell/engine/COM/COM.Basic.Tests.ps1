
try {
    $defaultParamValues = $PSdefaultParameterValues.Clone()
    $PSDefaultParameterValues["it:skip"] = ![System.Management.Automation.Platform]::IsWindowsDesktop

    Describe 'Basic COM Tests' -Tags "CI" {
        BeforeAll {
            $null = New-Item -Path $TESTDRIVE/file1 -ItemType File
            $null = New-Item -Path $TESTDRIVE/file2 -ItemType File
            $null = New-Item -Path $TESTDRIVE/file3 -ItemType File
        }

        It "Should enumerate files from a folder" {
            $shell = New-Object -ComObject "Shell.Application"
            $folder = $shell.Namespace("$TESTDRIVE")
            $items = $folder.Items()

            ## $items is a collection of all items belong to the folder, and it should be enumerated.
            $items.Count | Should Be 3
            $items | Measure-Object | ForEach-Object Count | Should Be $items.Count

            $names = $items | ForEach-Object { $_.Name }
            $names -join "," | Should Be "file1,file2,file3"
        }

        It "Should enumerate IEnumVariant interface object without exception" {
            $shell = New-Object -ComObject "Shell.Application"
            $folder = $shell.Namespace("$TESTDRIVE")
            $items = $folder.Items()

            ## $enumVariant is an IEnumVariant interface of all items belong to the folder, and it should be enumerated.
            $enumVariant = $items._NewEnum()
            $items.Count | Should Be 3
            $enumVariant | Measure-Object | ForEach-Object Count | Should Be $items.Count
        }

        It "Should enumerate drives" {
            $fileSystem = New-Object -ComObject scripting.filesystemobject
            $drives = $fileSystem.Drives

            ## $drives is a read-only collection of all available drives, and it should be enumerated.
            $drives | Measure-Object | ForEach-Object Count | Should Be $drives.Count
            ## $element should be the first drive from the enumeration. It shouldn't be the same as $drives,
            ## but it should be the same as '$drives.Item($element.DriveLetter)'
            $element = $drives | Select-Object -First 1
            [System.Object]::ReferenceEquals($element, $drives) | Should Be $false
            $element | Should Be $drives.Item($element.DriveLetter)
        }
    }

    Describe 'GetMember/SetMember/InvokeMember binders should have more restricted rule for COM object' -Tags "CI" {
        BeforeAll {
            $null = New-Item -Path $TESTDRIVE/bar -ItemType Directory -Force

            $shell = New-Object -ComObject "Shell.Application"
            $folder = $shell.Namespace("$TESTDRIVE")
            $item = $folder.Items().Item(0)

            ## Create a PSObject that has an instance member 'Name' and a script method 'Windows'
            $str = Add-Member -InputObject "abc" -MemberType NoteProperty -Name Name -Value "Hello" -PassThru
            $str = Add-Member -InputObject $str -MemberType ScriptMethod -Name Windows -Value { "Windows" } -PassThru
        }

        It "GetMember binder should differentiate PSObject that wraps COM object from other PSObjects" {
            ## GetMember on the member name 'Name'.
            ## '$_' here is a PSObject that wraps a COM object
            $item | ForEach-Object { $_.Name } > $null

            ## '$str' is a PSObject that wraps a string, but with NoteProperty 'Name'
            $str.Name | Should Be "Hello"
        }

        It "SetMember binder should differentiate PSObject that wraps COM object from other PSObjects" {
            ## SetMember on the member name 'Name'
            ## '$_' here is a PSObject that wraps a COM object
            $item | ForEach-Object { $_.Name = "foo" } > $null

            ## '$str' is a PSObject that wraps a string, but with NoteProperty 'Name'
            $str.Name = "World"
            $str.Name | Should Be "World"
        }

        It "InvokeMember binder should differentiate PSObject that wraps COM object from other PSObjects" {
            ## InvokeMember on the member name 'Windows'
            $shell | % { $_.Windows() } > $null

            ## '$str' is a PSObject that wraps a string, but with ScriptMethod 'Windows'
            $str.Windows() | Should Be "Windows"
        }
    }

} finally {
    $global:PSdefaultParameterValues = $defaultParamValues
}
