# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

@{
    RootModule = 'HelpersDebugger.psm1'

    ModuleVersion = '1.0'

    GUID = '37a454d7-8acd-40e6-8a2c-43c9d46b1b0c'

    CompanyName = 'Microsoft Corporation'

    Copyright = 'Copyright (c) Microsoft Corporation. All rights reserved.'

    Description = 'Helper module for Pester tests that automate the debugger'

    FunctionsToExport = @(
        'Register-DebuggerHandler'
        'ShouldHaveExtent'
        'ShouldHaveSameExtentAs'
        'Test-Debugger'
        'Unregister-DebuggerHandler'
    )

    CmdletsToExport = @()

    AliasesToExport = @()
}
