Import-Module (Join-Path -Path $PSScriptRoot 'certificateCommon.psm1') -Force
Import-Module $PSScriptRoot\..\..\Common\Test.Helpers.psm1 -Force

$currentUserMyLocations = @(
    @{path = 'Cert:\CurrentUser\my'}
    @{path = 'cert:\currentuser\my'}
    @{path = 'Microsoft.PowerShell.Security\Certificate::CurrentUser\My'}
    @{path = 'Microsoft.PowerShell.Security\certificate::currentuser\my'}        
)

$testLocations = @(
    @{path = 'cert:\'}
    @{path = 'CERT:\'}
    @{path = 'Microsoft.PowerShell.Security\Certificate::'}
)

# Add CurrentUserMyLocations to TestLocations
foreach($location in $currentUserMyLocations)
{
    $testLocations += $location
}

Describe "Certificate Provider tests" -Tags "CI" {
    BeforeAll{
        if(!$IsWindows)
        {
            # Skip for non-Windows platforms
            $defaultParamValues = $PSdefaultParameterValues.Clone()
            $PSdefaultParameterValues = @{ "it:skip" = $true }
        }        
    }

    AfterAll {
        if(!$IsWindows)
        {
            $PSdefaultParameterValues = $defaultParamValues
        }
    }

    Context "Get-Item tests" {
        it "Should be able to get a certificate store, path: <path>" -TestCases $testLocations {
            param([string] $path)
            $expectedResolvedPath = Resolve-Path -LiteralPath $path
            $result = Get-Item -LiteralPath $path
            $result | should not be null
            $result | ForEach-Object {
                $resolvedPath = Resolve-Path $_.PSPath
                $resolvedPath.Provider | should be $expectedResolvedPath.Provider
                $resolvedPath.ProviderPath.TrimStart('\') | should be $expectedResolvedPath.ProviderPath.TrimStart('\')
            }            
        }
        it "Should return two items at the root of the provider" {
            (Get-Item -Path cert:\*).Count | should be 2
        }
        it "Should be able to get multiple items explictly" {
            (get-item cert:\LocalMachine , cert:\CurrentUser).Count | should be 2
        }
        it "Should return PathNotFound when getting a non-existant certificate store" {
            {Get-Item cert:\IDONTEXIST -ErrorAction Stop} | ShouldBeErrorId "PathNotFound,Microsoft.PowerShell.Commands.GetItemCommand"
        }
        it "Should return PathNotFound when getting a non-existant certificate" {
            {Get-Item cert:\currentuser\my\IDONTEXIST -ErrorAction Stop} | ShouldBeErrorId "PathNotFound,Microsoft.PowerShell.Commands.GetItemCommand"
        }
    }
    Context "Get-ChildItem tests"{
        it "should be able to get a container using a wildcard" {
            (Get-ChildItem Cert:\CurrentUser\M?).PSPath | should be 'Microsoft.PowerShell.Security\Certificate::CurrentUser\My'
        }
        it "Should return two items at the root of the provider" {
            (Get-ChildItem -Path cert:\).Count | should be 2
        }
    }
}

Describe "Certificate Provider tests" -Tags "Feature" {
    BeforeAll{
        if($IsWindows)
        {
            Install-TestCertificates
            Push-Location Cert:\
        }
        else
        {
            # Skip for non-Windows platforms
            $defaultParamValues = $PSdefaultParameterValues.Clone()
            $PSdefaultParameterValues = @{ "it:skip" = $true }
        }        
    }
    
    AfterAll {
        if($IsWindows)
        {
            Remove-TestCertificates
            Pop-Location
        }
        else
        {
            $PSdefaultParameterValues = $defaultParamValues
        }
    }

    Context "Get-Item tests" {
        it "Should be able to get certifate by path: <path>" -TestCases $currentUserMyLocations {
            param([string] $path)
            $expectedThumbprint = (Get-GoodCertificateObject).Thumbprint
            $leafPath = Join-Path -Path $path -ChildPath $expectedThumbprint
            $cert = (Get-item -LiteralPath $leafPath)
            $cert | should not be null
            $cert.Thumbprint | should be $expectedThumbprint
        }
        it "Should filter to codesign certificates" {
            $allCerts = get-item cert:\CurrentUser\My\*
            $codeSignCerts = get-item cert:\CurrentUser\My\* -CodeSigningCert
            $codeSignCerts | should not be null
            $allCerts | should not be null
            $nonCodeSignCertCount = $allCerts.Count - $codeSignCerts.Count
            $nonCodeSignCertCount | should not be 0
        }
        it "Should be able to exclude by thumbprint" {
            $allCerts = get-item cert:\CurrentUser\My\*
            $testThumbprint = (Get-GoodCertificateObject).Thumbprint
            $allCertsExceptOne = (Get-Item "cert:\currentuser\my\*" -Exclude $testThumbprint)
            $allCerts | should not be null
            $allCertsExceptOne | should not be null
            $countDifference = $allCerts.Count - $allCertsExceptOne.Count
            $countDifference | should be 1
        }
    }
    Context "Get-ChildItem tests"{
        it "Should filter to codesign certificates" {
            $allCerts = get-ChildItem cert:\CurrentUser\My
            $codeSignCerts = get-ChildItem cert:\CurrentUser\My -CodeSigningCert
            $codeSignCerts | should not be null
            $allCerts | should not be null
            $nonCodeSignCertCount = $allCerts.Count - $codeSignCerts.Count
            $nonCodeSignCertCount | should not be 0
        }
    }
}