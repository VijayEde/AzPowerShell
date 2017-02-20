Describe 'conversion syntax' -Tags "CI" {
    # these test suite covers ([<type>]<expression>).<method>() syntax.
    # it mixes two purposes: casting and super-class method calls.

    It 'converts array of single enum to bool' {
        # This test relies on the fact that [ConsoleColor]::Black is 0 and all other values are non-zero
        [bool]@([ConsoleColor]::Black) | Should Be $false
        [bool]@([ConsoleColor]::Yellow) | Should Be $true
    }

    It 'calls virtual method non-virtually' {
        ([object]"abc").ToString() | Should Be "System.String"

        # generate random string to avoid JIT optimization
        $r = [guid]::NewGuid().Guid
        ([object]($r + "a")).Equals(($r + "a")) | Should Be $false
    }

    It 'calls method on a super-type, when conversion syntax used' {
        # This test relies on the fact that there are overloads (at least 2) for ToString method.
        ([System.Management.Automation.ActionPreference]"Stop").ToString() | Should Be "Stop"
    }

    Context "Cast object[] to more narrow generic collection" {
        BeforeAll {
            $testCases1 = @(
                @{ Command = {$result = [Collections.Generic.List[int]]@(1)};      CollectionType = 'List`1'; ElementType = "Int32";  Elements = @(1) }
                @{ Command = {$result = [Collections.Generic.List[int]]@(1,2)};    CollectionType = 'List`1'; ElementType = "Int32";  Elements = @(1,2) }
                @{ Command = {$result = [Collections.Generic.List[int]]"4"};       CollectionType = 'List`1'; ElementType = "Int32";  Elements = @(4) }
                @{ Command = {$result = [Collections.Generic.List[string]]@(1)};   CollectionType = 'List`1'; ElementType = "String"; Elements = @("1") }
                @{ Command = {$result = [Collections.Generic.List[string]]@(1,2)}; CollectionType = 'List`1'; ElementType = "String"; Elements = @("1","2") }
                @{ Command = {$result = [Collections.Generic.List[string]]1};      CollectionType = 'List`1'; ElementType = "String"; Elements = @("1") }

                @{ Command = {$result = [System.Collections.ObjectModel.Collection[int]]@(1)};   CollectionType = 'Collection`1'; ElementType = "Int32"; Elements = @(1) }
                @{ Command = {$result = [System.Collections.ObjectModel.Collection[int]]@(1,2)}; CollectionType = 'Collection`1'; ElementType = "Int32"; Elements = @(1,2) }
                @{ Command = {$result = [System.Collections.ObjectModel.Collection[int]]"4"};    CollectionType = 'Collection`1'; ElementType = "Int32"; Elements = @(4) }
            )

            $testCases2 = @(
                @{ Command = {$result = [Collections.Generic.List[System.IO.FileInfo]]@('TestFile')};
                   CollectionType = 'List`1'; ElementType = "FileInfo";  Elements = @('TestFile') }

                @{ Command = {$result = [Collections.Generic.List[System.IO.FileInfo]]@('TestFile1', 'TestFile2')};
                   CollectionType = 'List`1'; ElementType = "FileInfo";  Elements = @('TestFile1', 'TestFile2') }

                @{ Command = {$result = [Collections.Generic.List[System.IO.FileInfo]]'TestFile'};
                   CollectionType = 'List`1'; ElementType = "FileInfo";  Elements = @('TestFile') }
            )
        }

        It "<Command>" -TestCases $testCases1 {
            param($Command, $CollectionType, $ElementType, $Elements)

            $result = $null
            . $Command

            $result | Should Not BeNullOrEmpty
            $result.GetType().Name | Should Be $CollectionType

            $genericArgs = $result.GetType().GetGenericArguments()
            $genericArgs.Length | Should Be 1
            $genericArgs[0].Name | Should Be $ElementType

            $result.Count | Should Be $Elements.Length
            for ($i=0; $i -lt $Elements.Length; $i++)
            {
                $result[$i] | Should Be $Elements[$i]
            }
        }

        It "<Command>" -TestCases $testCases2 {
            param($Command, $CollectionType, $ElementType, $Elements)

            $result = $null
            . $Command

            $result | Should Not BeNullOrEmpty
            $result.GetType().Name | Should Be $CollectionType

            $genericArgs = $result.GetType().GetGenericArguments()
            $genericArgs.Length | Should Be 1
            $genericArgs[0].Name | Should Be $ElementType

            $result.Count | Should Be $Elements.Length
            for ($i=0; $i -lt $Elements.Length; $i++)
            {
                $result[$i].Name | Should Be $Elements[$i]
            }
        }
    }
}
