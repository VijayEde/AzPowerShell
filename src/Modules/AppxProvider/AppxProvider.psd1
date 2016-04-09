@{
RootModule = 'AppxProvider.psm1'
ModuleVersion = '1.0.0.1'
GUID = '745ff4ea-eaae-46e6-9fdb-f72640652ba3'
PowerShellVersion = '5.0'
Author = 'Microsoft Corporation'
CompanyName = 'Microsoft Corporation'
Copyright = '© Microsoft Corporation. All rights reserved.'
FunctionsToExport = @()
FileList = @('AppxProvider.psm1',
             'AppxProvider.Resource.psd1')
RequiredModules = @('PackageManagement','Appx')
PrivateData = @{
                "PackageManagementProviders" = 'AppxProvider.psm1'                
               }
HelpInfoURI = 'http://go.microsoft.com/fwlink/?LinkId=627236'
}