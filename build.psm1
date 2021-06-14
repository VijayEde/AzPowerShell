# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

param(
    # Skips a check that prevents building PowerShell on unsupported Linux distributions
    [parameter(Mandatory = $false)][switch]$SkipLinuxDistroCheck = $false
)

Set-StrictMode -Version 3.0

# On Unix paths is separated by colon
# On Windows paths is separated by semicolon
$script:TestModulePathSeparator = [System.IO.Path]::PathSeparator
$script:Options = $null

$dotnetCLIChannel = $(Get-Content $PSScriptRoot/DotnetRuntimeMetadata.json | ConvertFrom-Json).Sdk.Channel
$dotnetCLIRequiredVersion = $(Get-Content $PSScriptRoot/global.json | ConvertFrom-Json).Sdk.Version

# Track if tags have been sync'ed
$tagsUpToDate = $false

# Sync Tags
# When not using a branch in PowerShell/PowerShell, tags will not be fetched automatically
# Since code that uses Get-PSCommitID and Get-PSLatestTag assume that tags are fetched,
# This function can ensure that tags have been fetched.
# This function is used during the setup phase in tools/ci.psm1
function Sync-PSTags
{
    param(
        [Switch]
        $AddRemoteIfMissing
    )

    $PowerShellRemoteUrl = "https://github.com/PowerShell/PowerShell.git"
    $upstreamRemoteDefaultName = 'upstream'
    $remotes = Start-NativeExecution {git --git-dir="$PSScriptRoot/.git" remote}
    $upstreamRemote = $null
    foreach($remote in $remotes)
    {
        $url = Start-NativeExecution {git --git-dir="$PSScriptRoot/.git" remote get-url $remote}
        if($url -eq $PowerShellRemoteUrl)
        {
            $upstreamRemote = $remote
            break
        }
    }

    if(!$upstreamRemote -and $AddRemoteIfMissing.IsPresent -and $remotes -notcontains $upstreamRemoteDefaultName)
    {
        $null = Start-NativeExecution {git --git-dir="$PSScriptRoot/.git" remote add $upstreamRemoteDefaultName $PowerShellRemoteUrl}
        $upstreamRemote = $upstreamRemoteDefaultName
    }
    elseif(!$upstreamRemote)
    {
        Write-Error "Please add a remote to PowerShell\PowerShell.  Example:  git remote add $upstreamRemoteDefaultName $PowerShellRemoteUrl" -ErrorAction Stop
    }

    $null = Start-NativeExecution {git --git-dir="$PSScriptRoot/.git" fetch --tags --quiet $upstreamRemote}
    $script:tagsUpToDate=$true
}

# Gets the latest tag for the current branch
function Get-PSLatestTag
{
    [CmdletBinding()]
    param()
    # This function won't always return the correct value unless tags have been sync'ed
    # So, Write a warning to run Sync-PSTags
    if(!$tagsUpToDate)
    {
        Write-Warning "Run Sync-PSTags to update tags"
    }

    return (Start-NativeExecution {git --git-dir="$PSScriptRoot/.git" describe --abbrev=0})
}

function Get-PSVersion
{
    [CmdletBinding()]
    param(
        [switch]
        $OmitCommitId
    )
    if($OmitCommitId.IsPresent)
    {
        return (Get-PSLatestTag) -replace '^v'
    }
    else
    {
        return (Get-PSCommitId) -replace '^v'
    }
}

function Get-PSCommitId
{
    [CmdletBinding()]
    param()
    # This function won't always return the correct value unless tags have been sync'ed
    # So, Write a warning to run Sync-PSTags
    if(!$tagsUpToDate)
    {
        Write-Warning "Run Sync-PSTags to update tags"
    }

    return (Start-NativeExecution {git --git-dir="$PSScriptRoot/.git" describe --dirty --abbrev=60})
}

function Get-EnvironmentInformation
{
    $environment = @{'IsWindows' = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT}
    # PowerShell will likely not be built on pre-1709 nanoserver
    if ('System.Management.Automation.Platform' -as [type]) {
        $environment += @{'IsCoreCLR' = [System.Management.Automation.Platform]::IsCoreCLR}
        $environment += @{'IsLinux' = [System.Management.Automation.Platform]::IsLinux}
        $environment += @{'IsMacOS' = [System.Management.Automation.Platform]::IsMacOS}
    } else {
        $environment += @{'IsCoreCLR' = $false}
        $environment += @{'IsLinux' = $false}
        $environment += @{'IsMacOS' = $false}
    }

    if ($environment.IsWindows)
    {
        $environment += @{'IsAdmin' = (New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)}
        $environment += @{'nugetPackagesRoot' = "${env:USERPROFILE}\.nuget\packages"}
    }
    else
    {
        $environment += @{'nugetPackagesRoot' = "${env:HOME}/.nuget/packages"}
    }

    if ($environment.IsMacOS) {
        $environment += @{'UsingHomebrew' = [bool](Get-Command brew -ErrorAction ignore)}
        $environment += @{'UsingMacports' = [bool](Get-Command port -ErrorAction ignore)}

        if (-not($environment.UsingHomebrew -or $environment.UsingMacports)) {
            throw "Neither Homebrew nor MacPorts is installed on this system, visit https://brew.sh/ or https://www.macports.org/ to continue"
        }
    }

    if ($environment.IsLinux) {
        $LinuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
        $lsb_release = Get-Command lsb_release -Type Application -ErrorAction Ignore | Select-Object -First 1
        if ($lsb_release) {
            $LinuxID = & $lsb_release -is
        }
        else {
            $LinuxID = ""
        }

        $environment += @{'LinuxInfo' = $LinuxInfo}
        $environment += @{'IsDebian' = $LinuxInfo.ID -match 'debian' -or $LinuxInfo.ID -match 'kali'}
        $environment += @{'IsDebian9' = $environment.IsDebian -and $LinuxInfo.VERSION_ID -match '9'}
        $environment += @{'IsDebian10' = $environment.IsDebian -and $LinuxInfo.VERSION_ID -match '10'}
        $environment += @{'IsDebian11' = $environment.IsDebian -and $LinuxInfo.PRETTY_NAME -match 'bullseye'}
        $environment += @{'IsUbuntu' = $LinuxInfo.ID -match 'ubuntu' -or $LinuxID -match 'Ubuntu'}
        $environment += @{'IsUbuntu16' = $environment.IsUbuntu -and $LinuxInfo.VERSION_ID -match '16.04'}
        $environment += @{'IsUbuntu18' = $environment.IsUbuntu -and $LinuxInfo.VERSION_ID -match '18.04'}
        $environment += @{'IsUbuntu20' = $environment.IsUbuntu -and $LinuxInfo.VERSION_ID -match '20.04'}
        $environment += @{'IsCentOS' = $LinuxInfo.ID -match 'centos' -and $LinuxInfo.VERSION_ID -match '7'}
        $environment += @{'IsFedora' = $LinuxInfo.ID -match 'fedora' -and $LinuxInfo.VERSION_ID -ge 24}
        $environment += @{'IsOpenSUSE' = $LinuxInfo.ID -match 'opensuse'}
        $environment += @{'IsSLES' = $LinuxInfo.ID -match 'sles'}
        $environment += @{'IsRedHat' = $LinuxInfo.ID -match 'rhel'}
        $environment += @{'IsRedHat7' = $environment.IsRedHat -and $LinuxInfo.VERSION_ID -match '7' }
        $environment += @{'IsOpenSUSE13' = $environment.IsOpenSUSE -and $LinuxInfo.VERSION_ID  -match '13'}
        $environment += @{'IsOpenSUSE42.1' = $environment.IsOpenSUSE -and $LinuxInfo.VERSION_ID  -match '42.1'}
        $environment += @{'IsDebianFamily' = $environment.IsDebian -or $environment.IsUbuntu}
        $environment += @{'IsRedHatFamily' = $environment.IsCentOS -or $environment.IsFedora -or $environment.IsRedHat}
        $environment += @{'IsSUSEFamily' = $environment.IsSLES -or $environment.IsOpenSUSE}
        $environment += @{'IsAlpine' = $LinuxInfo.ID -match 'alpine'}

        # Workaround for temporary LD_LIBRARY_PATH hack for Fedora 24
        # https://github.com/PowerShell/PowerShell/issues/2511
        if ($environment.IsFedora -and (Test-Path ENV:\LD_LIBRARY_PATH)) {
            Remove-Item -Force ENV:\LD_LIBRARY_PATH
            Get-ChildItem ENV:
        }

        if( -not(
            $environment.IsDebian -or
            $environment.IsUbuntu -or
            $environment.IsRedHatFamily -or
            $environment.IsSUSEFamily -or
            $environment.IsAlpine)
        ) {
            if ($SkipLinuxDistroCheck) {
                Write-Warning "The current OS : $($LinuxInfo.ID) is not supported for building PowerShell."
            } else {
                throw "The current OS : $($LinuxInfo.ID) is not supported for building PowerShell. Import this module with '-ArgumentList `$true' to bypass this check."
            }
        }
    }

    return [PSCustomObject] $environment
}

$environment = Get-EnvironmentInformation

# Autoload (in current session) temporary modules used in our tests
$TestModulePath = Join-Path $PSScriptRoot "test/tools/Modules"
if ( -not $env:PSModulePath.Contains($TestModulePath) ) {
    $env:PSModulePath = $TestModulePath+$TestModulePathSeparator+$($env:PSModulePath)
}

<#
    .Synopsis
        Tests if a version is preview
    .EXAMPLE
        Test-IsPreview -version '6.1.0-sometthing' # returns true
        Test-IsPreview -version '6.1.0' # returns false
#>
function Test-IsPreview
{
    param(
        [parameter(Mandatory)]
        [string]
        $Version,

        [switch]$IsLTS
    )

    if ($IsLTS.IsPresent) {
        ## If we are building a LTS package, then never consider it preview.
        return $false
    }

    return $Version -like '*-*'
}

<#
    .Synopsis
        Tests if a version is a Release Candidate
    .EXAMPLE
        Test-IsReleaseCandidate -version '6.1.0-sometthing' # returns false
        Test-IsReleaseCandidate -version '6.1.0-rc.1' # returns true
        Test-IsReleaseCandidate -version '6.1.0' # returns false
#>
function Test-IsReleaseCandidate
{
    param(
        [parameter(Mandatory)]
        [string]
        $Version
    )

    if ($Version -like '*-rc.*')
    {
        return $true
    }

    return $false
}

function Start-PSBuild {
    [CmdletBinding(DefaultParameterSetName="Default")]
    param(
        # When specified this switch will stops running dev powershell
        # to help avoid compilation error, because file are in use.
        [switch]$StopDevPowerShell,

        [switch]$Restore,
        # Accept a path to the output directory
        # When specified, --output <path> will be passed to dotnet
        [string]$Output,
        [switch]$ResGen,
        [switch]$TypeGen,
        [switch]$Clean,
        [Parameter(ParameterSetName="Legacy")]
        [switch]$PSModuleRestore,
        [Parameter(ParameterSetName="Default")]
        [switch]$NoPSModuleRestore,
        [switch]$CI,
        [switch]$ForMinimalSize,

        # Skips the step where the pwsh that's been built is used to create a configuration
        # Useful when changing parsing/compilation, since bugs there can mean we can't get past this step
        [switch]$SkipExperimentalFeatureGeneration,

        # this switch will re-build only System.Management.Automation.dll
        # it's useful for development, to do a quick changes in the engine
        [switch]$SMAOnly,

        # These runtimes must match those in project.json
        # We do not use ValidateScript since we want tab completion
        # If this parameter is not provided it will get determined automatically.
        [ValidateSet("alpine-x64",
                     "fxdependent",
                     "fxdependent-win-desktop",
                     "linux-arm",
                     "linux-arm64",
                     "linux-x64",
                     "osx-arm64",
                     "osx-x64",
                     "win-arm",
                     "win-arm64",
                     "win7-x64",
                     "win7-x86")]
        [string]$Runtime,

        [ValidateSet('Debug', 'Release', 'CodeCoverage', '')] # We might need "Checked" as well
        [string]$Configuration,

        [switch]$CrossGen,

        [ValidatePattern("^v\d+\.\d+\.\d+(-\w+(\.\d{1,2})?)?$")]
        [ValidateNotNullOrEmpty()]
        [string]$ReleaseTag,
        [switch]$Detailed,
        [switch]$InteractiveAuth
    )

    if ($ReleaseTag -and $ReleaseTag -notmatch "^v\d+\.\d+\.\d+(-(preview|rc)(\.\d{1,2})?)?$") {
        Write-Warning "Only preview or rc are supported for releasing pre-release version of PowerShell"
    }

    if ($PSCmdlet.ParameterSetName -eq "Default" -and !$NoPSModuleRestore)
    {
        $PSModuleRestore = $true
    }

    if ($Runtime -eq "linux-arm" -and $environment.IsLinux -and -not $environment.IsUbuntu) {
        throw "Cross compiling for linux-arm is only supported on Ubuntu environment"
    }

    if ("win-arm","win-arm64" -contains $Runtime -and -not $environment.IsWindows) {
        throw "Cross compiling for win-arm or win-arm64 is only supported on Windows environment"
    }

    if ($ForMinimalSize) {
        if ($CrossGen) {
            throw "Build for the minimal size requires the minimal disk footprint, so `CrossGen` is not allowed"
        }

        if ($Runtime -and "linux-x64", "win7-x64", "osx-x64" -notcontains $Runtime) {
            throw "Build for the minimal size is enabled only for following runtimes: 'linux-x64', 'win7-x64', 'osx-x64'"
        }
    }

    function Stop-DevPowerShell {
        Get-Process pwsh* |
            Where-Object {
                $_.Modules |
                Where-Object {
                    $_.FileName -eq (Resolve-Path $script:Options.Output).Path
                }
            } |
        Stop-Process -Verbose
    }

    if ($Clean) {
        Write-Log -message "Cleaning your working directory. You can also do it with 'git clean -fdX --exclude .vs/PowerShell/v16/Server/sqlite3'"
        Push-Location $PSScriptRoot
        try {
            # Excluded sqlite3 folder is due to this Roslyn issue: https://github.com/dotnet/roslyn/issues/23060
            # Excluded src/Modules/nuget.config as this is required for release build.
            # Excluded nuget.config as this is required for release build.
            git clean -fdX --exclude .vs/PowerShell/v16/Server/sqlite3 --exclude src/Modules/nuget.config  --exclude nuget.config
        } finally {
            Pop-Location
        }
    }

    # Add .NET CLI tools to PATH
    Find-Dotnet

    # Verify we have git in place to do the build, and abort if the precheck failed
    $precheck = precheck 'git' "Build dependency 'git' not found in PATH. See <URL: https://docs.github.com/en/github/getting-started-with-github/set-up-git#setting-up-git >"
    if (-not $precheck) {
        return
    }

    # Verify we have .NET SDK in place to do the build, and abort if the precheck failed
    $precheck = precheck 'dotnet' "Build dependency 'dotnet' not found in PATH. Run Start-PSBootstrap. Also see <URL: https://dotnet.github.io/getting-started/ >"
    if (-not $precheck) {
        return
    }

    # Verify if the dotnet in-use is the required version
    $dotnetCLIInstalledVersion = Start-NativeExecution -sb { dotnet --version } -IgnoreExitcode
    If ($dotnetCLIInstalledVersion -ne $dotnetCLIRequiredVersion) {
        Write-Warning @"
The currently installed .NET Command Line Tools is not the required version.

Installed version: $dotnetCLIInstalledVersion
Required version: $dotnetCLIRequiredVersion

Fix steps:

1. Remove the installed version from:
    - on windows '`$env:LOCALAPPDATA\Microsoft\dotnet'
    - on macOS and linux '`$env:HOME/.dotnet'
2. Run Start-PSBootstrap or Install-Dotnet
3. Start-PSBuild -Clean
`n
"@
        return
    }

    # set output options
    $OptionsArguments = @{
        CrossGen=$CrossGen
        Output=$Output
        Runtime=$Runtime
        Configuration=$Configuration
        Verbose=$true
        SMAOnly=[bool]$SMAOnly
        PSModuleRestore=$PSModuleRestore
        ForMinimalSize=$ForMinimalSize
    }
    $script:Options = New-PSOptions @OptionsArguments

    if ($StopDevPowerShell) {
        Stop-DevPowerShell
    }

    # setup arguments
    # adding ErrorOnDuplicatePublishOutputFiles=false due to .NET SDk issue: https://github.com/dotnet/sdk/issues/15748
    $Arguments = @("publish","--no-restore","/property:GenerateFullPaths=true", "/property:ErrorOnDuplicatePublishOutputFiles=false")
    if ($Output -or $SMAOnly) {
        $Arguments += "--output", (Split-Path $Options.Output)
    }

    if ($Options.Runtime -like 'win*' -or ($Options.Runtime -like 'fxdependent*' -and $environment.IsWindows)) {
        $Arguments += "/property:IsWindows=true"
    }
    else {
        $Arguments += "/property:IsWindows=false"
    }

    # Framework Dependent builds do not support ReadyToRun as it needs a specific runtime to optimize for.
    # The property is set in Powershell.Common.props file.
    # We override the property through the build command line.
    if($Options.Runtime -like 'fxdependent*' -or $ForMinimalSize) {
        $Arguments += "/property:PublishReadyToRun=false"
    }

    $Arguments += "--configuration", $Options.Configuration
    $Arguments += "--framework", $Options.Framework

    if ($Detailed.IsPresent)
    {
        $Arguments += '--verbosity', 'd'
    }

    if (-not $SMAOnly -and $Options.Runtime -notlike 'fxdependent*') {
        # libraries should not have runtime
        $Arguments += "--runtime", $Options.Runtime
    }

    if ($ReleaseTag) {
        $ReleaseTagToUse = $ReleaseTag -Replace '^v'
        $Arguments += "/property:ReleaseTag=$ReleaseTagToUse"
    }

    # handle Restore
    Restore-PSPackage -Options $Options -Force:$Restore -InteractiveAuth:$InteractiveAuth

    # handle ResGen
    # Heuristic to run ResGen on the fresh machine
    if ($ResGen -or -not (Test-Path "$PSScriptRoot/src/Microsoft.PowerShell.ConsoleHost/gen")) {
        Write-Log -message "Run ResGen (generating C# bindings for resx files)"
        Start-ResGen
    }

    # Handle TypeGen
    # .inc file name must be different for Windows and Linux to allow build on Windows and WSL.
    $incFileName = "powershell_$($Options.Runtime).inc"
    if ($TypeGen -or -not (Test-Path "$PSScriptRoot/src/TypeCatalogGen/$incFileName")) {
        Write-Log -message "Run TypeGen (generating CorePsTypeCatalog.cs)"
        Start-TypeGen -IncFileName $incFileName
    }

    # Get the folder path where pwsh.exe is located.
    if ((Split-Path $Options.Output -Leaf) -like "pwsh*") {
        $publishPath = Split-Path $Options.Output -Parent
    }
    else {
        $publishPath = $Options.Output
    }

    try {
        # Relative paths do not work well if cwd is not changed to project
        Push-Location $Options.Top

        if ($Options.Runtime -notlike 'fxdependent*') {
            $sdkToUse = 'Microsoft.NET.Sdk'
            if ($Options.Runtime -like 'win7-*' -and !$ForMinimalSize) {
                ## WPF/WinForm and the PowerShell GraphicalHost assemblies are included
                ## when 'Microsoft.NET.Sdk.WindowsDesktop' is used.
                $sdkToUse = 'Microsoft.NET.Sdk.WindowsDesktop'
            }

            $Arguments += "/property:SDKToUse=$sdkToUse"

            Write-Log -message "Run dotnet $Arguments from $PWD"
            Start-NativeExecution { dotnet $Arguments }
            Write-Log -message "PowerShell output: $($Options.Output)"

            if ($CrossGen) {
                # fxdependent package cannot be CrossGen'ed
                Start-CrossGen -PublishPath $publishPath -Runtime $script:Options.Runtime
                Write-Log -message "pwsh.exe with ngen binaries is available at: $($Options.Output)"
            }
        } else {
            $globalToolSrcFolder = Resolve-Path (Join-Path $Options.Top "../Microsoft.PowerShell.GlobalTool.Shim") | Select-Object -ExpandProperty Path

            if ($Options.Runtime -eq 'fxdependent') {
                $Arguments += "/property:SDKToUse=Microsoft.NET.Sdk"
            } elseif ($Options.Runtime -eq 'fxdependent-win-desktop') {
                $Arguments += "/property:SDKToUse=Microsoft.NET.Sdk.WindowsDesktop"
            }

            Write-Log -message "Run dotnet $Arguments from $PWD"
            Start-NativeExecution { dotnet $Arguments }
            Write-Log -message "PowerShell output: $($Options.Output)"

            try {
                Push-Location $globalToolSrcFolder
                $Arguments += "--output", $publishPath
                Write-Log -message "Run dotnet $Arguments from $PWD to build global tool entry point"
                Start-NativeExecution { dotnet $Arguments }
            }
            finally {
                Pop-Location
            }
        }
    } finally {
        Pop-Location
    }

    # No extra post-building task will run if '-SMAOnly' is specified, because its purpose is for a quick update of S.M.A.dll after full build.
    if ($SMAOnly) {
        return
    }

    # publish reference assemblies
    try {
        Push-Location "$PSScriptRoot/src/TypeCatalogGen"
        $refAssemblies = Get-Content -Path $incFileName | Where-Object { $_ -like "*microsoft.netcore.app*" } | ForEach-Object { $_.TrimEnd(';') }
        $refDestFolder = Join-Path -Path $publishPath -ChildPath "ref"

        if (Test-Path $refDestFolder -PathType Container) {
            Remove-Item $refDestFolder -Force -Recurse -ErrorAction Stop
        }
        New-Item -Path $refDestFolder -ItemType Directory -Force -ErrorAction Stop > $null
        Copy-Item -Path $refAssemblies -Destination $refDestFolder -Force -ErrorAction Stop
    } finally {
        Pop-Location
    }

    if ($ReleaseTag) {
        $psVersion = $ReleaseTag
    }
    else {
        $psVersion = git --git-dir="$PSScriptRoot/.git" describe
    }

    if ($environment.IsLinux) {
        if ($environment.IsRedHatFamily -or $environment.IsDebian) {
            # Symbolic links added here do NOT affect packaging as we do not build on Debian.
            # add two symbolic links to system shared libraries that libmi.so is dependent on to handle
            # platform specific changes. This is the only set of platforms needed for this currently
            # as Ubuntu has these specific library files in the platform and macOS builds for itself
            # against the correct versions.

            if ($environment.IsDebian10 -or $environment.IsDebian11){
                $sslTarget = "/usr/lib/x86_64-linux-gnu/libssl.so.1.1"
                $cryptoTarget = "/usr/lib/x86_64-linux-gnu/libcrypto.so.1.1"
            }
            elseif ($environment.IsDebian9){
                # NOTE: Debian 8 doesn't need these symlinks
                $sslTarget = "/usr/lib/x86_64-linux-gnu/libssl.so.1.0.2"
                $cryptoTarget = "/usr/lib/x86_64-linux-gnu/libcrypto.so.1.0.2"
            }
            else { #IsRedHatFamily
                $sslTarget = "/lib64/libssl.so.10"
                $cryptoTarget = "/lib64/libcrypto.so.10"
            }

            if ( ! (Test-Path "$publishPath/libssl.so.1.0.0")) {
                $null = New-Item -Force -ItemType SymbolicLink -Target $sslTarget -Path "$publishPath/libssl.so.1.0.0" -ErrorAction Stop
            }
            if ( ! (Test-Path "$publishPath/libcrypto.so.1.0.0")) {
                $null = New-Item -Force -ItemType SymbolicLink -Target $cryptoTarget -Path "$publishPath/libcrypto.so.1.0.0" -ErrorAction Stop
            }
        }
    }

    # download modules from powershell gallery.
    #   - PowerShellGet, PackageManagement, Microsoft.PowerShell.Archive
    if ($PSModuleRestore) {
        Restore-PSModuleToBuild -PublishPath $publishPath
    }

    # publish powershell.config.json
    $config = @{}
    if ($environment.IsWindows) {
        $config = @{ "Microsoft.PowerShell:ExecutionPolicy" = "RemoteSigned";
                     "WindowsPowerShellCompatibilityModuleDenyList" = @("PSScheduledJob","BestPractices","UpdateServices") }
    }

    # When building preview, we want the configuration to enable all experiemental features by default
    # ARM is cross compiled, so we can't run pwsh to enumerate Experimental Features
    if (-not $SkipExperimentalFeatureGeneration -and
        (Test-IsPreview $psVersion) -and
        -not (Test-IsReleaseCandidate $psVersion) -and
        -not $Runtime.Contains("arm") -and
        -not ($Runtime -like 'fxdependent*')) {

        $json = & $publishPath\pwsh -noprofile -command {
            # Special case for DSC code in PS;
            # this experimental feature requires new DSC module that is not inbox,
            # so we don't want default DSC use case be broken
            [System.Collections.ArrayList] $expFeatures = Get-ExperimentalFeature | Where-Object Name -NE PS7DscSupport | ForEach-Object -MemberName Name

            $expFeatures | Out-String | Write-Verbose -Verbose

            # Make sure ExperimentalFeatures from modules in PSHome are added
            # https://github.com/PowerShell/PowerShell/issues/10550
            $ExperimentalFeaturesFromGalleryModulesInPSHome = @()
            $ExperimentalFeaturesFromGalleryModulesInPSHome | ForEach-Object {
                if (!$expFeatures.Contains($_)) {
                    $null = $expFeatures.Add($_)
                }
            }

            ConvertTo-Json $expFeatures
        }

        $config += @{ ExperimentalFeatures = ([string[]] ($json | ConvertFrom-Json)) }
    }

    if ($config.Count -gt 0) {
        $configPublishPath = Join-Path -Path $publishPath -ChildPath "powershell.config.json"
        Set-Content -Path $configPublishPath -Value ($config | ConvertTo-Json) -Force -ErrorAction Stop
    }

    # Restore the Pester module
    if ($CI) {
        Restore-PSPester -Destination (Join-Path $publishPath "Modules")
    }
}

function Restore-PSPackage
{
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter()]
        [string[]] $ProjectDirs,

        [ValidateNotNullOrEmpty()]
        [Parameter()]
        $Options = (Get-PSOptions -DefaultToNew),

        [switch] $Force,

        [switch] $InteractiveAuth,

        [switch] $PSModule
    )

    if (-not $ProjectDirs)
    {
        $ProjectDirs = @($Options.Top, "$PSScriptRoot/src/TypeCatalogGen", "$PSScriptRoot/src/ResGen", "$PSScriptRoot/src/Modules")

        if ($Options.Runtime -like 'fxdependent*') {
            $ProjectDirs += "$PSScriptRoot/src/Microsoft.PowerShell.GlobalTool.Shim"
        }
    }

    if ($Force -or (-not (Test-Path "$($Options.Top)/obj/project.assets.json"))) {

        if ($Options.Runtime -eq 'fxdependent-win-desktop') {
            $sdkToUse = 'Microsoft.NET.Sdk.WindowsDesktop'
        }
        else {
            $sdkToUse = 'Microsoft.NET.Sdk'
            if ($Options.Runtime -like 'win7-*' -and !$Options.ForMinimalSize) {
                $sdkToUse = 'Microsoft.NET.Sdk.WindowsDesktop'
            }
        }

        if ($PSModule.IsPresent) {
            $RestoreArguments = @("--verbosity")
        }
        elseif ($Options.Runtime -notlike 'fxdependent*') {
            $RestoreArguments = @("--runtime", $Options.Runtime, "/property:SDKToUse=$sdkToUse", "--verbosity")
        } else {
            $RestoreArguments = @("/property:SDKToUse=$sdkToUse", "--verbosity")
        }

        if ($VerbosePreference -eq 'Continue') {
            $RestoreArguments += "detailed"
        } else {
            $RestoreArguments += "quiet"
        }

        if ($InteractiveAuth) {
            $RestoreArguments += "--interactive"
        }

        $ProjectDirs | ForEach-Object {
            $project = $_
            Write-Log -message "Run dotnet restore $project $RestoreArguments"
            $retryCount = 0
            $maxTries = 5
            while($retryCount -lt $maxTries)
            {
                try
                {
                    Start-NativeExecution { dotnet restore $project $RestoreArguments }
                }
                catch
                {
                    Write-Log -message "Failed to restore $project, retrying..."
                    $retryCount++
                    if($retryCount -ge $maxTries)
                    {
                        throw
                    }
                    continue
                }

                Write-Log -message "Done restoring $project"
                break
            }
        }
    }
}

function Restore-PSModuleToBuild
{
    param(
        [Parameter(Mandatory)]
        [string]
        $PublishPath
    )

    Write-Log -message "Restore PowerShell modules to $publishPath"
    $modulesDir = Join-Path -Path $publishPath -ChildPath "Modules"
    Copy-PSGalleryModules -Destination $modulesDir -CsProjPath "$PSScriptRoot\src\Modules\PSGalleryModules.csproj"

    # Remove .nupkg.metadata files
    Get-ChildItem $PublishPath -Filter '.nupkg.metadata' -Recurse | ForEach-Object { Remove-Item $_.FullName -ErrorAction SilentlyContinue -Force }
}

function Restore-PSPester
{
    param(
        [ValidateNotNullOrEmpty()]
        [string] $Destination = ([IO.Path]::Combine((Split-Path (Get-PSOptions -DefaultToNew).Output), "Modules"))
    )
    Save-Module -Name Pester -Path $Destination -Repository PSGallery -MaximumVersion 4.99
}

function Compress-TestContent {
    [CmdletBinding()]
    param(
        $Destination
    )

    $null = Publish-PSTestTools
    $powerShellTestRoot =  Join-Path $PSScriptRoot 'test'
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    [System.IO.Compression.ZipFile]::CreateFromDirectory($powerShellTestRoot, $resolvedPath)
}

function New-PSOptions {
    [CmdletBinding()]
    param(
        [ValidateSet("Debug", "Release", "CodeCoverage", '')]
        [string]$Configuration,

        [ValidateSet("net6.0")]
        [string]$Framework = "net6.0",

        # These are duplicated from Start-PSBuild
        # We do not use ValidateScript since we want tab completion
        [ValidateSet("",
                     "alpine-x64",
                     "fxdependent",
                     "fxdependent-win-desktop",
                     "linux-arm",
                     "linux-arm64",
                     "linux-x64",
                     "osx-arm64",
                     "osx-x64",
                     "win-arm",
                     "win-arm64",
                     "win7-x64",
                     "win7-x86")]
        [string]$Runtime,

        [switch]$CrossGen,

        # Accept a path to the output directory
        # If not null or empty, name of the executable will be appended to
        # this path, otherwise, to the default path, and then the full path
        # of the output executable will be assigned to the Output property
        [string]$Output,

        [switch]$SMAOnly,

        [switch]$PSModuleRestore,

        [switch]$ForMinimalSize
    )

    # Add .NET CLI tools to PATH
    Find-Dotnet

    if (-not $Configuration) {
        $Configuration = 'Debug'
    }

    Write-Verbose "Using configuration '$Configuration'"
    Write-Verbose "Using framework '$Framework'"

    if (-not $Runtime) {
        if ($environment.IsLinux) {
            $Runtime = "linux-x64"
        } elseif ($environment.IsMacOS) {
            if ($PSVersionTable.OS.Contains('ARM64')) {
                $Runtime = "osx-arm64"
            }
            else {
                $Runtime = "osx-x64"
            }
        } else {
            $RID = dotnet --info | ForEach-Object {
                if ($_ -match "RID") {
                    $_ -split "\s+" | Select-Object -Last 1
                }
            }

            # We plan to release packages targetting win7-x64 and win7-x86 RIDs,
            # which supports all supported windows platforms.
            # So we, will change the RID to win7-<arch>
            $Runtime = $RID -replace "win\d+", "win7"
        }

        if (-not $Runtime) {
            Throw "Could not determine Runtime Identifier, please update dotnet"
        } else {
            Write-Verbose "Using runtime '$Runtime'"
        }
    }

    $PowerShellDir = if ($Runtime -like 'win*' -or ($Runtime -like 'fxdependent*' -and $environment.IsWindows)) {
        "powershell-win-core"
    } else {
        "powershell-unix"
    }

    $Top = [IO.Path]::Combine($PSScriptRoot, "src", $PowerShellDir)
    Write-Verbose "Top project directory is $Top"

    $Executable = if ($Runtime -like 'fxdependent*') {
        "pwsh.dll"
    } elseif ($environment.IsLinux -or $environment.IsMacOS) {
        "pwsh"
    } elseif ($environment.IsWindows) {
        "pwsh.exe"
    }

    # Build the Output path
    if (!$Output) {
        if ($Runtime -like 'fxdependent*') {
            $Output = [IO.Path]::Combine($Top, "bin", $Configuration, $Framework, "publish", $Executable)
        } else {
            $Output = [IO.Path]::Combine($Top, "bin", $Configuration, $Framework, $Runtime, "publish", $Executable)
        }
    } else {
        $Output = [IO.Path]::Combine($Output, $Executable)
    }

    if ($SMAOnly)
    {
        $Top = [IO.Path]::Combine($PSScriptRoot, "src", "System.Management.Automation")
    }

    $RootInfo = @{RepoPath = $PSScriptRoot}

    # the valid root is the root of the filesystem and the folder PowerShell
    $RootInfo['ValidPath'] = Join-Path -Path ([system.io.path]::GetPathRoot($RootInfo.RepoPath)) -ChildPath 'PowerShell'

    if($RootInfo.RepoPath -ne $RootInfo.ValidPath)
    {
        $RootInfo['Warning'] = "Please ensure your repo is at the root of the file system and named 'PowerShell' (example: '$($RootInfo.ValidPath)'), when building and packaging for release!"
        $RootInfo['IsValid'] = $false
    }
    else
    {
        $RootInfo['IsValid'] = $true
    }

    return New-PSOptionsObject `
                -RootInfo ([PSCustomObject]$RootInfo) `
                -Top $Top `
                -Runtime $Runtime `
                -Crossgen $Crossgen.IsPresent `
                -Configuration $Configuration `
                -PSModuleRestore $PSModuleRestore.IsPresent `
                -Framework $Framework `
                -Output $Output `
                -ForMinimalSize $ForMinimalSize
}

# Get the Options of the last build
function Get-PSOptions {
    param(
        [Parameter(HelpMessage='Defaults to New-PSOption if a build has not occurred.')]
        [switch]
        $DefaultToNew
    )

    if (!$script:Options -and $DefaultToNew.IsPresent)
    {
        return New-PSOptions
    }

    return $script:Options
}

function Set-PSOptions {
    param(
        [PSObject]
        $Options
    )

    $script:Options = $Options
}

function Get-PSOutput {
    [CmdletBinding()]param(
        [hashtable]$Options
    )
    if ($Options) {
        return $Options.Output
    } elseif ($script:Options) {
        return $script:Options.Output
    } else {
        return (New-PSOptions).Output
    }
}

function Get-PesterTag {
    param ( [Parameter(Position=0)][string]$testbase = "$PSScriptRoot/test/powershell" )
    $alltags = @{}
    $warnings = @()

    Get-ChildItem -Recurse $testbase -File | Where-Object {$_.name -match "tests.ps1"}| ForEach-Object {
        $fullname = $_.fullname
        $tok = $err = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($FullName, [ref]$tok,[ref]$err)
        $des = $ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.CommandAst] `
                -and $args[0].CommandElements.GetType() -in @(
                    [System.Management.Automation.Language.StringConstantExpressionAst],
                    [System.Management.Automation.Language.ExpandableStringExpressionAst]
                ) `
                -and $args[0].CommandElements[0].Value -eq "Describe"
        }, $true)
        foreach( $describe in $des) {
            $elements = $describe.CommandElements
            $lineno = $elements[0].Extent.StartLineNumber
            $foundPriorityTags = @()
            for ( $i = 0; $i -lt $elements.Count; $i++) {
                if ( $elements[$i].extent.text -match "^-t" ) {
                    $vAst = $elements[$i+1]
                    if ( $vAst.FindAll({$args[0] -is "System.Management.Automation.Language.VariableExpressionAst"},$true) ) {
                        $warnings += "TAGS must be static strings, error in ${fullname}, line $lineno"
                    }
                    $values = $vAst.FindAll({$args[0] -is "System.Management.Automation.Language.StringConstantExpressionAst"},$true).Value
                    $values | ForEach-Object {
                        if (@('REQUIREADMINONWINDOWS', 'REQUIRESUDOONUNIX', 'SLOW') -contains $_) {
                            # These are valid tags also, but they are not the priority tags
                        }
                        elseif (@('CI', 'FEATURE', 'SCENARIO') -contains $_) {
                            $foundPriorityTags += $_
                        }
                        else {
                            $warnings += "${fullname} includes improper tag '$_', line '$lineno'"
                        }

                        $alltags[$_]++
                    }
                }
            }
            if ( $foundPriorityTags.Count -eq 0 ) {
                $warnings += "${fullname}:$lineno does not include -Tag in Describe"
            }
            elseif ( $foundPriorityTags.Count -gt 1 ) {
                $warnings += "${fullname}:$lineno includes more then one scope -Tag: $foundPriorityTags"
            }
        }
    }
    if ( $Warnings.Count -gt 0 ) {
        $alltags['Result'] = "Fail"
    }
    else {
        $alltags['Result'] = "Pass"
    }
    $alltags['Warnings'] = $warnings
    $o = [pscustomobject]$alltags
    $o.psobject.TypeNames.Add("DescribeTagsInUse")
    $o
}

function Publish-PSTestTools {
    [CmdletBinding()]
    param(
        [string]
        $runtime
    )

    Find-Dotnet

    $tools = @(
        @{Path="${PSScriptRoot}/test/tools/TestExe";Output="testexe"}
        @{Path="${PSScriptRoot}/test/tools/WebListener";Output="WebListener"}
        @{Path="${PSScriptRoot}/test/tools/TestService";Output="TestService"}
    )

    $Options = Get-PSOptions -DefaultToNew

    # Publish tools so it can be run by tests
    foreach ($tool in $tools)
    {
        Push-Location $tool.Path
        try {
            $toolPath = Join-Path -Path $tool.Path -ChildPath "bin"
            $objPath = Join-Path -Path $tool.Path -ChildPath "obj"

            if (Test-Path $toolPath) {
                Remove-Item -Path $toolPath -Recurse -Force
            }

            if (Test-Path $objPath) {
                Remove-Item -Path $objPath -Recurse -Force
            }

            if (-not $runtime) {
                dotnet publish --output bin --configuration $Options.Configuration --framework $Options.Framework --runtime $Options.Runtime
            } else {
                dotnet publish --output bin --configuration $Options.Configuration --framework $Options.Framework --runtime $runtime
            }

            if ( -not $env:PATH.Contains($toolPath) ) {
                $env:PATH = $toolPath+$TestModulePathSeparator+$($env:PATH)
            }
        } finally {
            Pop-Location
        }
    }

    # `dotnet restore` on test project is not called if product projects have been restored unless -Force is specified.
    Copy-PSGalleryModules -Destination "${PSScriptRoot}/test/tools/Modules" -CsProjPath "$PSScriptRoot/test/tools/Modules/PSGalleryTestModules.csproj" -Force
}

function Get-ExperimentalFeatureTests {
    $testMetadataFile = Join-Path $PSScriptRoot "test/tools/TestMetadata.json"
    $metadata = Get-Content -Path $testMetadataFile -Raw | ConvertFrom-Json | ForEach-Object -MemberName ExperimentalFeatures
    $features = $metadata | Get-Member -MemberType NoteProperty | ForEach-Object -MemberName Name

    $featureTests = @{}
    foreach ($featureName in $features) {
        $featureTests[$featureName] = $metadata.$featureName
    }
    $featureTests
}

function Start-PSPester {
    [CmdletBinding(DefaultParameterSetName='default')]
    param(
        [Parameter(Position=0)]
        [string[]]$Path = @("$PSScriptRoot/test/powershell"),
        [string]$OutputFormat = "NUnitXml",
        [string]$OutputFile = "pester-tests.xml",
        [string[]]$ExcludeTag = 'Slow',
        [string[]]$Tag = @("CI","Feature"),
        [switch]$ThrowOnFailure,
        [string]$BinDir = (Split-Path (Get-PSOptions -DefaultToNew).Output),
        [string]$powershell = (Join-Path $BinDir 'pwsh'),
        [string]$Pester = ([IO.Path]::Combine($BinDir, "Modules", "Pester")),
        [Parameter(ParameterSetName='Unelevate',Mandatory=$true)]
        [switch]$Unelevate,
        [switch]$Quiet,
        [switch]$Terse,
        [Parameter(ParameterSetName='PassThru',Mandatory=$true)]
        [switch]$PassThru,
        [Parameter(ParameterSetName='PassThru',HelpMessage='Run commands on Linux with sudo.')]
        [switch]$Sudo,
        [switch]$IncludeFailingTest,
        [switch]$IncludeCommonTests,
        [string]$ExperimentalFeatureName,
        [Parameter(HelpMessage='Title to publish the results as.')]
        [string]$Title = 'PowerShell 7 Tests',
        [Parameter(ParameterSetName='Wait', Mandatory=$true,
            HelpMessage='Wait for the debugger to attach to PowerShell before Pester starts.  Debug builds only!')]
        [switch]$Wait,
        [switch]$SkipTestToolBuild
    )

    if (-not (Get-Module -ListAvailable -Name $Pester -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge "4.2" } ))
    {
        Restore-PSPester
    }

    if ($IncludeFailingTest.IsPresent)
    {
        $Path += "$PSScriptRoot/tools/failingTests"
    }

    if($IncludeCommonTests.IsPresent)
    {
        $path = += "$PSScriptRoot/test/common"
    }

    # we need to do few checks and if user didn't provide $ExcludeTag explicitly, we should alternate the default
    if ($Unelevate)
    {
        if (-not $environment.IsWindows)
        {
            throw '-Unelevate is currently not supported on non-Windows platforms'
        }

        if (-not $environment.IsAdmin)
        {
            throw '-Unelevate cannot be applied because the current user is not Administrator'
        }

        if (-not $PSBoundParameters.ContainsKey('ExcludeTag'))
        {
            $ExcludeTag += 'RequireAdminOnWindows'
        }
    }
    elseif ($environment.IsWindows -and (-not $environment.IsAdmin))
    {
        if (-not $PSBoundParameters.ContainsKey('ExcludeTag'))
        {
            $ExcludeTag += 'RequireAdminOnWindows'
        }
    }
    elseif (-not $environment.IsWindows -and (-not $Sudo.IsPresent))
    {
        if (-not $PSBoundParameters.ContainsKey('ExcludeTag'))
        {
            $ExcludeTag += 'RequireSudoOnUnix'
        }
    }
    elseif (-not $environment.IsWindows -and $Sudo.IsPresent)
    {
        if (-not $PSBoundParameters.ContainsKey('Tag'))
        {
            $Tag = 'RequireSudoOnUnix'
        }
    }

    Write-Verbose "Running pester tests at '$path' with tag '$($Tag -join ''', ''')' and ExcludeTag '$($ExcludeTag -join ''', ''')'" -Verbose
    if(!$SkipTestToolBuild.IsPresent)
    {
        $publishArgs = @{ }
        # if we are building for Alpine, we must include the runtime as linux-x64
        # will not build runnable test tools
        if ( $environment.IsLinux -and $environment.IsAlpine ) {
            $publishArgs['runtime'] = 'alpine-x64'
        }
        Publish-PSTestTools @publishArgs | ForEach-Object {Write-Host $_}
    }

    # All concatenated commands/arguments are suffixed with the delimiter (space)

    # Disable telemetry for all startups of pwsh in tests
    $command = "`$env:POWERSHELL_TELEMETRY_OPTOUT = 'yes';"
    if ($Terse)
    {
        $command += "`$ProgressPreference = 'silentlyContinue'; "
    }

    # Autoload (in subprocess) temporary modules used in our tests
    $newPathFragment = $TestModulePath + $TestModulePathSeparator
    $command += '$env:PSModulePath = '+"'$newPathFragment'" + '+$env:PSModulePath;'

    # Windows needs the execution policy adjusted
    if ($environment.IsWindows) {
        $command += "Set-ExecutionPolicy -Scope Process Unrestricted; "
    }

    $command += "Import-Module '$Pester'; "

    if ($Unelevate)
    {
        $outputBufferFilePath = [System.IO.Path]::GetTempFileName()
    }

    $command += "Invoke-Pester "

    $command += "-OutputFormat ${OutputFormat} -OutputFile ${OutputFile} "
    if ($ExcludeTag -and ($ExcludeTag -ne "")) {
        $command += "-ExcludeTag @('" + (${ExcludeTag} -join "','") + "') "
    }
    if ($Tag) {
        $command += "-Tag @('" + (${Tag} -join "','") + "') "
    }
    # sometimes we need to eliminate Pester output, especially when we're
    # doing a daily build as the log file is too large
    if ( $Quiet ) {
        $command += "-Quiet "
    }
    if ( $PassThru ) {
        $command += "-PassThru "
    }

    $command += "'" + ($Path -join "','") + "'"
    if ($Unelevate)
    {
        $command += " *> $outputBufferFilePath; '__UNELEVATED_TESTS_THE_END__' >> $outputBufferFilePath"
    }

    Write-Verbose $command

    $script:nonewline = $true
    $script:inerror = $false
    function Write-Terse([string] $line)
    {
        $trimmedline = $line.Trim()
        if ($trimmedline.StartsWith("[+]")) {
            Write-Host "+" -NoNewline -ForegroundColor Green
            $script:nonewline = $true
            $script:inerror = $false
        }
        elseif ($trimmedline.StartsWith("[?]")) {
            Write-Host "?" -NoNewline -ForegroundColor Cyan
            $script:nonewline = $true
            $script:inerror = $false
        }
        elseif ($trimmedline.StartsWith("[!]")) {
            Write-Host "!" -NoNewline -ForegroundColor Gray
            $script:nonewline = $true
            $script:inerror = $false
        }
        elseif ($trimmedline.StartsWith("Executing script ")) {
            # Skip lines where Pester reports that is executing a test script
            return
        }
        elseif ($trimmedline -match "^\d+(\.\d+)?m?s$") {
            # Skip the time elapse like '12ms', '1ms', '1.2s' and '12.53s'
            return
        }
        else {
            if ($script:nonewline) {
                Write-Host "`n" -NoNewline
            }
            if ($trimmedline.StartsWith("[-]") -or $script:inerror) {
                Write-Host $line -ForegroundColor Red
                $script:inerror = $true
            }
            elseif ($trimmedline.StartsWith("VERBOSE:")) {
                Write-Host $line -ForegroundColor Yellow
                $script:inerror = $false
            }
            elseif ($trimmedline.StartsWith("Describing") -or $trimmedline.StartsWith("Context")) {
                Write-Host $line -ForegroundColor Magenta
                $script:inerror = $false
            }
            else {
                Write-Host $line -ForegroundColor Gray
            }
            $script:nonewline = $false
        }
    }

    $PSFlags = @("-noprofile")
    if (-not [string]::IsNullOrEmpty($ExperimentalFeatureName)) {
        $configFile = [System.IO.Path]::GetTempFileName()
        $configFile = [System.IO.Path]::ChangeExtension($configFile, ".json")

        ## Create the config.json file to enable the given experimental feature.
        ## On Windows, we need to have 'RemoteSigned' declared for ExecutionPolicy because the ExecutionPolicy is 'Restricted' by default.
        ## On Unix, ExecutionPolicy is not supported, so we don't need to declare it.
        if ($environment.IsWindows) {
            $content = @"
{
    "Microsoft.PowerShell:ExecutionPolicy":"RemoteSigned",
    "ExperimentalFeatures": [
        "$ExperimentalFeatureName"
    ]
}
"@
        } else {
            $content = @"
{
    "ExperimentalFeatures": [
        "$ExperimentalFeatureName"
    ]
}
"@
        }

        Set-Content -Path $configFile -Value $content -Encoding Ascii -Force
        $PSFlags = @("-settings", $configFile, "-noprofile")
    }

	# -Wait is only available on Debug builds
	# It is used to allow the debugger to attach before PowerShell
	# runs pester in this case
    if($Wait.IsPresent){
        $PSFlags += '-wait'
    }

    # To ensure proper testing, the module path must not be inherited by the spawned process
    try {
        $originalModulePath = $env:PSModulePath
        $originalTelemetry = $env:POWERSHELL_TELEMETRY_OPTOUT
        $env:POWERSHELL_TELEMETRY_OPTOUT = 'yes'
        if ($Unelevate)
        {
            Start-UnelevatedProcess -process $powershell -arguments ($PSFlags + "-c $Command")
            $currentLines = 0
            while ($true)
            {
                $lines = Get-Content $outputBufferFilePath | Select-Object -Skip $currentLines
                if ($Terse)
                {
                    foreach ($line in $lines)
                    {
                        Write-Terse -line $line
                    }
                }
                else
                {
                    $lines | Write-Host
                }
                if ($lines | Where-Object { $_ -eq '__UNELEVATED_TESTS_THE_END__'})
                {
                    break
                }

                $count = ($lines | Measure-Object).Count
                if ($count -eq 0)
                {
                    Start-Sleep -Seconds 1
                }
                else
                {
                    $currentLines += $count
                }
            }
        }
        else
        {
            if ($PassThru.IsPresent)
            {
                $passThruFile = [System.IO.Path]::GetTempFileName()
                try
                {
                    $command += "| Export-Clixml -Path '$passThruFile' -Force"

                    $passThruCommand = { & $powershell $PSFlags -c $command }
                    if ($Sudo.IsPresent) {
                        # -E says to preserve the environment
                        $passThruCommand =  { & sudo -E $powershell $PSFlags -c $command }
                    }

                    $writeCommand = { Write-Host $_ }
                    if ($Terse)
                    {
                        $writeCommand = { Write-Terse $_ }
                    }

                    Start-NativeExecution -sb $passThruCommand | ForEach-Object $writeCommand
                    Import-Clixml -Path $passThruFile | Where-Object {$_.TotalCount -is [Int32]}
                }
                finally
                {
                    Remove-Item $passThruFile -ErrorAction SilentlyContinue -Force
                }
            }
            else
            {
                if ($Terse)
                {
                    Start-NativeExecution -sb {& $powershell $PSFlags -c $command} | ForEach-Object { Write-Terse -line $_ }
                }
                else
                {
                    Start-NativeExecution -sb {& $powershell $PSFlags -c $command}
                }
            }
        }
    } finally {
        $env:PSModulePath = $originalModulePath
        $env:POWERSHELL_TELEMETRY_OPTOUT = $originalTelemetry
        if ($Unelevate)
        {
            Remove-Item $outputBufferFilePath
        }
    }

    Publish-TestResults -Path $OutputFile -Title $Title

    if($ThrowOnFailure)
    {
        Test-PSPesterResults -TestResultsFile $OutputFile
    }
}

function Publish-TestResults
{
    param(
        [Parameter(Mandatory)]
        [string]
        $Title,

        [Parameter(Mandatory)]
        [ValidateScript({Test-Path -Path $_})]
        [string]
        $Path,

        [ValidateSet('NUnit','XUnit')]
        [string]
        $Type='NUnit'
    )

    # In VSTS publish Test Results
    if($env:TF_BUILD)
    {
        $fileName = Split-Path -Leaf -Path $Path
        $tempPath = $env:BUILD_ARTIFACTSTAGINGDIRECTORY
        if (! $tempPath)
        {
            $tempPath = [system.io.path]::GetTempPath()
        }
        $tempFilePath = Join-Path -Path $tempPath -ChildPath $fileName

        # NUnit allowed values are: Passed, Failed, Inconclusive or Ignored (the spec says Skipped but it doesn' work with Azure DevOps)
        # https://github.com/nunit/docs/wiki/Test-Result-XML-Format
        # Azure DevOps Reporting is so messed up for NUnit V2 and doesn't follow their own spec
        # https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/test/publish-test-results?view=azure-devops&tabs=yaml
        # So, we will map skipped to the actual value in the NUnit spec and they will ignore all results for tests which were not executed
        Get-Content $Path | ForEach-Object {
            $_ -replace 'result="Ignored"', 'result="Skipped"'
        } | Out-File -FilePath $tempFilePath -Encoding ascii -Force

        # If we attempt to upload a result file which has no test cases in it, then vsts will produce a warning
        # so check to be sure we actually have a result file that contains test cases to upload.
        # If the the "test-case" count is greater than 0, then we have results.
        # Regardless, we want to upload this as an artifact, so this logic doesn't pertain to that.
        if ( @(([xml](Get-Content $Path)).SelectNodes(".//test-case")).Count -gt 0 -or $Type -eq 'XUnit' ) {
            Write-Host "##vso[results.publish type=$Type;mergeResults=true;runTitle=$Title;publishRunAttachments=true;resultFiles=$tempFilePath;failTaskOnFailedTests=true]"
        }

        $resolvedPath = (Resolve-Path -Path $Path).ProviderPath
        Write-Host "##vso[artifact.upload containerfolder=testResults;artifactname=testResults]$resolvedPath"
    }
}

function script:Start-UnelevatedProcess
{
    param(
        [string]$process,
        [string[]]$arguments
    )
    if (-not $environment.IsWindows)
    {
        throw "Start-UnelevatedProcess is currently not supported on non-Windows platforms"
    }

    runas.exe /trustlevel:0x20000 "$process $arguments"
}

function Show-PSPesterError
{
    [CmdletBinding(DefaultParameterSetName='xml')]
    param (
        [Parameter(ParameterSetName='xml',Mandatory)]
        [Xml.XmlElement]$testFailure,
        [Parameter(ParameterSetName='object',Mandatory)]
        [PSCustomObject]$testFailureObject
        )

    if ($PSCmdlet.ParameterSetName -eq 'xml')
    {
        $description = $testFailure.description
        $name = $testFailure.name
        $message = $testFailure.failure.message
        $StackTrace = $testFailure.failure."stack-trace"
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'object')
    {
        $description = $testFailureObject.Describe + '/' + $testFailureObject.Context
        $name = $testFailureObject.Name
        $message = $testFailureObject.FailureMessage
        $StackTrace = $testFailureObject.StackTrace
    }
    else
    {
        throw 'Unknown Show-PSPester parameter set'
    }

    Write-Log -isError -message ("Description: " + $description)
    Write-Log -isError -message ("Name:        " + $name)
    Write-Log -isError -message "message:"
    Write-Log -isError -message $message
    Write-Log -isError -message "stack-trace:"
    Write-Log -isError -message $StackTrace

}

function Test-XUnitTestResults
{
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TestResultsFile
    )

    if(-not (Test-Path $TestResultsFile))
    {
        throw "File not found $TestResultsFile"
    }

    try
    {
        $results = [xml] (Get-Content $TestResultsFile)
    }
    catch
    {
        throw "Cannot convert $TestResultsFile to xml : $($_.message)"
    }

    $failedTests = $results.assemblies.assembly.collection.test | Where-Object result -eq "fail"

    if(-not $failedTests)
    {
        return $true
    }

    foreach($failure in $failedTests)
    {
        $description = $failure.type
        $name = $failure.method
        $message = $failure.failure.message
        $StackTrace = $failure.failure.'stack-trace'

        Write-Log -isError -message ("Description: " + $description)
        Write-Log -isError -message ("Name:        " + $name)
        Write-Log -isError -message "message:"
        Write-Log -isError -message $message
        Write-Log -isError -message "stack-trace:"
        Write-Log -isError -message $StackTrace
        Write-Log -isError -message " "
    }

    throw "$($results.assemblies.assembly.failed) tests failed"
}

#
# Read the test result file and
# Throw if a test failed
function Test-PSPesterResults
{
    [CmdletBinding(DefaultParameterSetName='file')]
    param(
        [Parameter(ParameterSetName='file')]
        [string] $TestResultsFile = "pester-tests.xml",

        [Parameter(ParameterSetName='file')]
        [string] $TestArea = 'test/powershell',

        [Parameter(ParameterSetName='PesterPassThruObject', Mandatory)]
        [pscustomobject] $ResultObject,

        [Parameter(ParameterSetName='PesterPassThruObject')]
        [switch] $CanHaveNoResult
    )

    if($PSCmdlet.ParameterSetName -eq 'file')
    {
        if(!(Test-Path $TestResultsFile))
        {
            throw "Test result file '$testResultsFile' not found for $TestArea."
        }

        $x = [xml](Get-Content -Raw $testResultsFile)
        if ([int]$x.'test-results'.failures -gt 0)
        {
            Write-Log -isError -message "TEST FAILURES"
            # switch between methods, SelectNode is not available on dotnet core
            if ( "System.Xml.XmlDocumentXPathExtensions" -as [Type] )
            {
                $failures = [System.Xml.XmlDocumentXPathExtensions]::SelectNodes($x."test-results",'.//test-case[@result = "Failure"]')
            }
            else
            {
                $failures = $x.SelectNodes('.//test-case[@result = "Failure"]')
            }
            foreach ( $testfail in $failures )
            {
                Show-PSPesterError -testFailure $testfail
            }
            throw "$($x.'test-results'.failures) tests in $TestArea failed"
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'PesterPassThruObject')
    {
        if ($ResultObject.TotalCount -le 0 -and -not $CanHaveNoResult)
        {
            throw 'NO TESTS RUN'
        }
        elseif ($ResultObject.FailedCount -gt 0)
        {
            Write-Log -isError -message 'TEST FAILURES'

            $ResultObject.TestResult | Where-Object {$_.Passed -eq $false} | ForEach-Object {
                Show-PSPesterError -testFailureObject $_
            }

            throw "$($ResultObject.FailedCount) tests in $TestArea failed"
        }
    }
}

function Start-PSxUnit {
    [CmdletBinding()]param(
        [string] $xUnitTestResultsFile = "xUnitResults.xml"
    )

    # Add .NET CLI tools to PATH
    Find-Dotnet

    $Content = Split-Path -Parent (Get-PSOutput)
    if (-not (Test-Path $Content)) {
        throw "PowerShell must be built before running tests!"
    }

    try {
        Push-Location $PSScriptRoot/test/xUnit

        # Path manipulation to obtain test project output directory

        if(-not $environment.IsWindows)
        {
            if($environment.IsMacOS)
            {
                $nativeLib = "$Content/libpsl-native.dylib"
            }
            else
            {
                $nativeLib = "$Content/libpsl-native.so"
            }

            $requiredDependencies = @(
                $nativeLib,
                "$Content/Microsoft.Management.Infrastructure.dll",
                "$Content/System.Text.Encoding.CodePages.dll"
            )

            if((Test-Path $requiredDependencies) -notcontains $false)
            {
                $options = Get-PSOptions -DefaultToNew
                $Destination = "bin/$($options.configuration)/$($options.framework)"
                New-Item $Destination -ItemType Directory -Force > $null
                Copy-Item -Path $requiredDependencies -Destination $Destination -Force
            }
            else
            {
                throw "Dependencies $requiredDependencies not met."
            }
        }

        if (Test-Path $xUnitTestResultsFile) {
            Remove-Item $xUnitTestResultsFile -Force -ErrorAction SilentlyContinue
        }

        # We run the xUnit tests sequentially to avoid race conditions caused by manipulating the config.json file.
        # xUnit tests run in parallel by default. To make them run sequentially, we need to define the 'xunit.runner.json' file.
        dotnet test --configuration $Options.configuration --test-adapter-path:. "--logger:xunit;LogFilePath=$xUnitTestResultsFile"

        Publish-TestResults -Path $xUnitTestResultsFile -Type 'XUnit' -Title 'Xunit Sequential'
    }
    finally {
        Pop-Location
    }
}
Install-Dotnet {
function
    [CmdletBinding()]
    param(
        [string]$Channel = $dotnetCLIChannel,
        [string]$Version = $dotnetCLIRequiredVersion,
        [switch]$NoSudo,
        [string]$InstallDir,
        [string]$AzureFeed,
        [string]$FeedCredential
    )

    # This allows sudo install to be optional; needed when running in containers / as root
    # Note that when it is null, Invoke-Expression (but not &) must be used to interpolate properly
    $sudo = if (!$NoSudo) { "sudo" }

    $installObtainUrl = "https://dotnet.microsoft.com/download/dotnet-core/scripts/v1"
    $uninstallObtainUrl = "https://raw.githubusercontent.com/dotnet/cli/master/scripts/obtain"

    # Install for Linux and OS X
    if ($environment.IsLinux -or $environment.IsMacOS) {
        $wget = Get-Command -Name wget -CommandType Application -TotalCount 1 -ErrorAction Stop

        # Uninstall all previous dotnet packages
        $uninstallScript = if ($environment.IsLinux -and $environment.IsUbuntu) {
            "dotnet-uninstall-debian-packages.sh"
        } elseif ($environment.IsMacOS) {
            "dotnet-uninstall-pkgs.sh"
        }

        if ($uninstallScript) {
            Start-NativeExecution {
                & $wget $uninstallObtainUrl/uninstall/$uninstallScript
                Invoke-Expression "$sudo bash ./$uninstallScript"
            }
        } else {
            Write-Warning "This script only removes prior versions of dotnet for Ubuntu and OS X"
        }

        # Install new dotnet 1.1.0 preview packages
        $installScript = "dotnet-install.sh"
        Start-NativeExecution {
            Write-Verbose -Message "downloading install script from $installObtainUrl/$installScript ..." -Verbose
            & $wget $installObtainUrl/$installScript

            if ((Get-ChildItem "./$installScript").Length -eq 0) {
                throw "./$installScript was 0 length"
            }

            $bashArgs = @("./$installScript", '-c', $Channel, '-v', $Version)

            if ($InstallDir) {
                $bashArgs += @('-i', $InstallDir)
            }

            if ($AzureFeed) {
                $bashArgs += @('-AzureFeed', $AzureFeed, '-FeedCredential', $FeedCredential)
            }

            bash @bashArgs
        }
    } elseif ($environment.IsWindows) {
        Remove-Item -ErrorAction SilentlyContinue -Recurse -Force ~\AppData\Local\Microsoft\dotnet
        $installScript = "dotnet-install.ps1"
        Invoke-WebRequest -Uri $installObtainUrl/$installScript -OutFile $installScript
        if (-not $environment.IsCoreCLR) {
            $installArgs = @{
                Channel = $Channel
                Version = $Version
            }

            if ($InstallDir) {
                $installArgs += @{ InstallDir = $InstallDir }
            }

            if ($AzureFeed) {
                $installArgs += @{
                    AzureFeed       = $AzureFeed
                    $FeedCredential = $FeedCredential
                }
            }

            & ./$installScript @installArgs
        }
        else {
            # dotnet-install.ps1 uses APIs that are not supported in .NET Core, so we run it with Windows PowerShell
            $fullPSPath = Join-Path -Path $env:windir -ChildPath "System32\WindowsPowerShell\v1.0\powershell.exe"
            $fullDotnetInstallPath = Join-Path -Path $PWD.Path -ChildPath $installScript
            Start-NativeExecution {
                $psArgs = @('-NoLogo', '-NoProfile', '-File', $fullDotnetInstallPath, '-Channel', $Channel, '-Version', $Version)

                if ($InstallDir) {
                    $psArgs += @('-InstallDir', $InstallDir)
                }

                if ($AzureFeed) {
                    $psArgs += @('-AzureFeed', $AzureFeed, '-FeedCredential', $FeedCredential)
                }

                & $fullPSPath @psArgs
            }
        }
    }
}

function Get-RedHatPackageManager {
    if ($environment.IsCentOS) {
        "yum install -y -q"
    } elseif ($environment.IsFedora) {
        "dnf install -y -q"
    } else {
        throw "Error determining package manager for this distribution."
    }
}

function Start-PSBootstrap {
    [CmdletBinding(
        SupportsShouldProcess=$true,
        ConfirmImpact="High")]
    param(
        [string]$Channel = $dotnetCLIChannel,
        # we currently pin dotnet-cli version, and will
        # update it when more stable version comes out.
        [string]$Version = $dotnetCLIRequiredVersion,
        [switch]$Package,
        [switch]$NoSudo,
        [switch]$BuildLinuxArm,
        [switch]$Force
    )

    Write-Log -message "Installing PowerShell build dependencies"

    Push-Location $PSScriptRoot/tools

    try {
        if ($environment.IsLinux -or $environment.IsMacOS) {
            # This allows sudo install to be optional; needed when running in containers / as root
            # Note that when it is null, Invoke-Expression (but not &) must be used to interpolate properly
            $sudo = if (!$NoSudo) { "sudo" }

            if ($BuildLinuxArm -and $environment.IsLinux -and -not $environment.IsUbuntu) {
                Write-Error "Cross compiling for linux-arm is only supported on Ubuntu environment"
                return
            }

            # Install ours and .NET's dependencies
            $Deps = @()
            if ($environment.IsLinux -and $environment.IsUbuntu) {
                # Build tools
                $Deps += "curl", "g++", "cmake", "make"

                if ($BuildLinuxArm) {
                    $Deps += "gcc-arm-linux-gnueabihf", "g++-arm-linux-gnueabihf"
                }

                # .NET Core required runtime libraries
                $Deps += "libunwind8"
                if ($environment.IsUbuntu16) { $Deps += "libicu55" }
                elseif ($environment.IsUbuntu18) { $Deps += "libicu60"}

                # Packaging tools
                if ($Package) { $Deps += "ruby-dev", "groff", "libffi-dev" }

                # Install dependencies
                # change the fontend from apt-get to noninteractive
                $originalDebianFrontEnd=$env:DEBIAN_FRONTEND
                $env:DEBIAN_FRONTEND='noninteractive'
                try {
                    Start-NativeExecution {
                        Invoke-Expression "$sudo apt-get update -qq"
                        Invoke-Expression "$sudo apt-get install -y -qq $Deps"
                    }
                }
                finally {
                    # change the apt frontend back to the original
                    $env:DEBIAN_FRONTEND=$originalDebianFrontEnd
                }
            } elseif ($environment.IsLinux -and $environment.IsRedHatFamily) {
                # Build tools
                $Deps += "which", "curl", "gcc-c++", "cmake", "make"

                # .NET Core required runtime libraries
                $Deps += "libicu", "libunwind"

                # Packaging tools
                if ($Package) { $Deps += "ruby-devel", "rpm-build", "groff", 'libffi-devel' }

                $PackageManager = Get-RedHatPackageManager

                $baseCommand = "$sudo $PackageManager"

                # On OpenSUSE 13.2 container, sudo does not exist, so don't use it if not needed
                if($NoSudo)
                {
                    $baseCommand = $PackageManager
                }

                # Install dependencies
                Start-NativeExecution {
                    Invoke-Expression "$baseCommand $Deps"
                }
            } elseif ($environment.IsLinux -and $environment.IsSUSEFamily) {
                # Build tools
                $Deps += "gcc", "cmake", "make"

                # Packaging tools
                if ($Package) { $Deps += "ruby-devel", "rpmbuild", "groff", 'libffi-devel' }

                $PackageManager = "zypper --non-interactive install"
                $baseCommand = "$sudo $PackageManager"

                # On OpenSUSE 13.2 container, sudo does not exist, so don't use it if not needed
                if($NoSudo)
                {
                    $baseCommand = $PackageManager
                }

                # Install dependencies
                Start-NativeExecution {
                    Invoke-Expression "$baseCommand $Deps"
                }
            } elseif ($environment.IsMacOS) {
                if ($environment.UsingHomebrew) {
                    $PackageManager = "brew"
                } elseif ($environment.UsingMacports) {
                    $PackageManager = "$sudo port"
                }

                # Build tools
                $Deps += "cmake"

                # .NET Core required runtime libraries
                $Deps += "openssl"

                # Install dependencies
                # ignore exitcode, because they may be already installed
                Start-NativeExecution ([ScriptBlock]::Create("$PackageManager install $Deps")) -IgnoreExitcode
            } elseif ($environment.IsLinux -and $environment.IsAlpine) {
                $Deps += 'libunwind', 'libcurl', 'bash', 'cmake', 'clang', 'build-base', 'git', 'curl'

                Start-NativeExecution {
                    Invoke-Expression "apk add $Deps"
                }
            }

            # Install [fpm](https://github.com/jordansissel/fpm) and [ronn](https://github.com/rtomayko/ronn)
            if ($Package) {
                try {
                    # We cannot guess if the user wants to run gem install as root on linux and windows,
                    # but macOs usually requires sudo
                    $gemsudo = ''
                    if($environment.IsMacOS -or $env:TF_BUILD) {
                        $gemsudo = $sudo
                    }
                    Start-NativeExecution ([ScriptBlock]::Create("$gemsudo gem install ffi -v 1.12.0 --no-document"))
                    Start-NativeExecution ([ScriptBlock]::Create("$gemsudo gem install fpm -v 1.11.0 --no-document"))
                    Start-NativeExecution ([ScriptBlock]::Create("$gemsudo gem install ronn -v 0.7.3 --no-document"))
                } catch {
                    Write-Warning "Installation of fpm and ronn gems failed! Must resolve manually."
                }
            }
        }

        # Try to locate dotnet-SDK before installing it
        Find-Dotnet

        # Install dotnet-SDK
        $dotNetExists = precheck 'dotnet' $null
        $dotNetVersion = [string]::Empty
        if($dotNetExists) {
            $dotNetVersion = Start-NativeExecution -sb { dotnet --version } -IgnoreExitcode
        }

        if(!$dotNetExists -or $dotNetVersion -ne $dotnetCLIRequiredVersion -or $Force.IsPresent) {
            if($Force.IsPresent) {
                Write-Log -message "Installing dotnet due to -Force."
            }
            elseif(!$dotNetExists) {
                Write-Log -message "dotnet not present.  Installing dotnet."
            }
            else {
                Write-Log -message "dotnet out of date ($dotNetVersion).  Updating dotnet."
            }

            $DotnetArguments = @{ Channel=$Channel; Version=$Version; NoSudo=$NoSudo }
            Install-Dotnet @DotnetArguments
        }
        else {
            Write-Log -message "dotnet is already installed.  Skipping installation."
        }

        # Install Windows dependencies if `-Package` or `-BuildWindowsNative` is specified
        if ($environment.IsWindows) {
            ## The VSCode build task requires 'pwsh.exe' to be found in Path
            if (-not (Get-Command -Name pwsh.exe -CommandType Application -ErrorAction Ignore))
            {
                Write-Log -message "pwsh.exe not found. Install latest PowerShell release and add it to Path"
                $psInstallFile = [System.IO.Path]::Combine($PSScriptRoot, "tools", "install-powershell.ps1")
                & $psInstallFile -AddToPath
            }
        }
    } finally {
        Pop-Location
    }
}

function Start-DevPowerShell {
    [CmdletBinding(DefaultParameterSetName='ConfigurationParamSet')]
    param(
        [string[]]$ArgumentList = @(),
        [switch]$LoadProfile,
        [Parameter(ParameterSetName='ConfigurationParamSet')]
        [ValidateSet("Debug", "Release", "CodeCoverage", '')] # should match New-PSOptions -Configuration values
        [string]$Configuration,
        [Parameter(ParameterSetName='BinDirParamSet')]
        [string]$BinDir,
        [switch]$NoNewWindow,
        [string]$Command,
        [switch]$KeepPSModulePath
    )

    try {
        if (-not $BinDir) {
            $BinDir = Split-Path (New-PSOptions -Configuration $Configuration).Output
        }

        if ((-not $NoNewWindow) -and ($environment.IsCoreCLR)) {
            Write-Warning "Start-DevPowerShell -NoNewWindow is currently implied in PowerShellCore edition https://github.com/PowerShell/PowerShell/issues/1543"
            $NoNewWindow = $true
        }

        if (-not $LoadProfile) {
            $ArgumentList = @('-noprofile') + $ArgumentList
        }

        if (-not $KeepPSModulePath) {
            if (-not $Command) {
                $ArgumentList = @('-NoExit') + $ArgumentList
            }
            $Command = '$env:PSModulePath = Join-Path $env:DEVPATH Modules; ' + $Command
        }

        if ($Command) {
            $ArgumentList = $ArgumentList + @("-command $Command")
        }

        $env:DEVPATH = $BinDir


        # splatting for the win
        $startProcessArgs = @{
            FilePath = "$BinDir\pwsh"
        }

        if ($ArgumentList) {
            $startProcessArgs.ArgumentList = $ArgumentList
        }

        if ($NoNewWindow) {
            $startProcessArgs.NoNewWindow = $true
            $startProcessArgs.Wait = $true
        }

        Start-Process @startProcessArgs
    } finally {
        if($env:DevPath)
        {
            Remove-Item env:DEVPATH
        }
    }
}

function Start-TypeGen
{
    [CmdletBinding()]
    param
    (
        [ValidateNotNullOrEmpty()]
        $IncFileName = 'powershell.inc'
    )

    # Add .NET CLI tools to PATH
    Find-Dotnet

    # This custom target depends on 'ResolveAssemblyReferencesDesignTime', whose definition can be found in the sdk folder.
    # To find the available properties of '_ReferencesFromRAR' when switching to a new dotnet sdk, follow the steps below:
    #   1. create a dummy project using the new dotnet sdk.
    #   2. build the dummy project with this command:
    #      dotnet msbuild .\dummy.csproj /t:ResolveAssemblyReferencesDesignTime /fileLogger /noconsolelogger /v:diag
    #   3. search '_ReferencesFromRAR' in the produced 'msbuild.log' file. You will find the properties there.
    $GetDependenciesTargetPath = "$PSScriptRoot/src/Microsoft.PowerShell.SDK/obj/Microsoft.PowerShell.SDK.csproj.TypeCatalog.targets"
    $GetDependenciesTargetValue = @'
<Project>
    <Target Name="_GetDependencies"
            DependsOnTargets="ResolveAssemblyReferencesDesignTime">
        <ItemGroup>
            <_RefAssemblyPath Include="%(_ReferencesFromRAR.OriginalItemSpec)%3B" Condition=" '%(_ReferencesFromRAR.NuGetPackageId)' != 'Microsoft.Management.Infrastructure' "/>
        </ItemGroup>
        <WriteLinesToFile File="$(_DependencyFile)" Lines="@(_RefAssemblyPath)" Overwrite="true" />
    </Target>
</Project>
'@
    New-Item -ItemType Directory -Path (Split-Path -Path $GetDependenciesTargetPath -Parent) -Force > $null
    Set-Content -Path $GetDependenciesTargetPath -Value $GetDependenciesTargetValue -Force -Encoding Ascii

    Push-Location "$PSScriptRoot/src/Microsoft.PowerShell.SDK"
    try {
        $ps_inc_file = "$PSScriptRoot/src/TypeCatalogGen/$IncFileName"
        dotnet msbuild .\Microsoft.PowerShell.SDK.csproj /t:_GetDependencies "/property:DesignTimeBuild=true;_DependencyFile=$ps_inc_file" /nologo
    } finally {
        Pop-Location
    }

    Push-Location "$PSScriptRoot/src/TypeCatalogGen"
    try {
        dotnet run ../System.Management.Automation/CoreCLR/CorePsTypeCatalog.cs $IncFileName
    } finally {
        Pop-Location
    }
}

function Start-ResGen
{
    [CmdletBinding()]
    param()

    # Add .NET CLI tools to PATH
    Find-Dotnet

    Push-Location "$PSScriptRoot/src/ResGen"
    try {
        Start-NativeExecution { dotnet run } | Write-Verbose
    } finally {
        Pop-Location
    }
}

function Find-Dotnet() {
    $originalPath = $env:PATH
    $dotnetPath = if ($environment.IsWindows) { "$env:LocalAppData\Microsoft\dotnet" } else { "$env:HOME/.dotnet" }

    # If there dotnet is already in the PATH, check to see if that version of dotnet can find the required SDK
    # This is "typically" the globally installed dotnet
    if (precheck dotnet) {
        # Must run from within repo to ensure global.json can specify the required SDK version
        Push-Location $PSScriptRoot
        $dotnetCLIInstalledVersion = Start-NativeExecution -sb { dotnet --version } -IgnoreExitcode 2> $null
        Pop-Location
        if ($dotnetCLIInstalledVersion -ne $dotnetCLIRequiredVersion) {
            Write-Warning "The 'dotnet' in the current path can't find SDK version ${dotnetCLIRequiredVersion}, prepending $dotnetPath to PATH."
            # Globally installed dotnet doesn't have the required SDK version, prepend the user local dotnet location
            $env:PATH = $dotnetPath + [IO.Path]::PathSeparator + $env:PATH
        }
    }
    else {
        Write-Warning "Could not find 'dotnet', appending $dotnetPath to PATH."
        $env:PATH += [IO.Path]::PathSeparator + $dotnetPath
    }

    if (-not (precheck 'dotnet' "Still could not find 'dotnet', restoring PATH.")) {
        $env:PATH = $originalPath
    }
}

<#
    This is one-time conversion. We use it for to turn GetEventResources.txt into GetEventResources.resx

    .EXAMPLE Convert-TxtResourceToXml -Path Microsoft.PowerShell.Commands.Diagnostics\resources
#>
function Convert-TxtResourceToXml
{
    param(
        [string[]]$Path
    )

    process {
        $Path | ForEach-Object {
            Get-ChildItem $_ -Filter "*.txt" | ForEach-Object {
                $txtFile = $_.FullName
                $resxFile = Join-Path (Split-Path $txtFile) "$($_.BaseName).resx"
                $resourceHashtable = ConvertFrom-StringData (Get-Content -Raw $txtFile)
                $resxContent = $resourceHashtable.GetEnumerator() | ForEach-Object {
@'
  <data name="{0}" xml:space="preserve">
    <value>{1}</value>
  </data>
'@ -f $_.Key, $_.Value
                } | Out-String
                Set-Content -Path $resxFile -Value ($script:RESX_TEMPLATE -f $resxContent)
            }
        }
    }
}

function script:Use-MSBuild {
    # TODO: we probably should require a particular version of msbuild, if we are taking this dependency
    # msbuild v14 and msbuild v4 behaviors are different for XAML generation
    $frameworkMsBuildLocation = "${env:SystemRoot}\Microsoft.Net\Framework\v4.0.30319\msbuild"

    $msbuild = Get-Command msbuild -ErrorAction Ignore
    if ($msbuild) {
        # all good, nothing to do
        return
    }

    if (-not (Test-Path $frameworkMsBuildLocation)) {
        throw "msbuild not found in '$frameworkMsBuildLocation'. Install Visual Studio 2015."
    }

    Set-Alias msbuild $frameworkMsBuildLocation -Scope Script
}

function script:Write-Log
{
    param
    (
        [Parameter(Position=0, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $message,

        [switch] $isError
    )
    if ($isError)
    {
        Write-Host -Foreground Red $message
    }
    else
    {
        Write-Host -Foreground Green $message
    }
    #reset colors for older package to at return to default after error message on a compilation error
    [console]::ResetColor()
}
function script:precheck([string]$command, [string]$missedMessage) {
    $c = Get-Command $command -ErrorAction Ignore
    if (-not $c) {
        if (-not [string]::IsNullOrEmpty($missedMessage))
        {
            Write-Warning $missedMessage
        }
        return $false
    } else {
        return $true
    }
}

# this function wraps native command Execution
# for more information, read https://mnaoumov.wordpress.com/2015/01/11/execution-of-external-commands-in-powershell-done-right/
function script:Start-NativeExecution
{
    param(
        [scriptblock]$sb,
        [switch]$IgnoreExitcode,
        [switch]$VerboseOutputOnError
    )
    $backupEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        if($VerboseOutputOnError.IsPresent)
        {
            $output = & $sb 2>&1
        }
        else
        {
            & $sb
        }

        # note, if $sb doesn't have a native invocation, $LASTEXITCODE will
        # point to the obsolete value
        if ($LASTEXITCODE -ne 0 -and -not $IgnoreExitcode) {
            if($VerboseOutputOnError.IsPresent -and $output)
            {
                $output | Out-String | Write-Verbose -Verbose
            }

            # Get caller location for easier debugging
            $caller = Get-PSCallStack -ErrorAction SilentlyContinue
            if($caller)
            {
                $callerLocationParts = $caller[1].Location -split ":\s*line\s*"
                $callerFile = $callerLocationParts[0]
                $callerLine = $callerLocationParts[1]

                $errorMessage = "Execution of {$sb} by ${callerFile}: line $callerLine failed with exit code $LASTEXITCODE"
                throw $errorMessage
            }
            throw "Execution of {$sb} failed with exit code $LASTEXITCODE"
        }
    } finally {
        $ErrorActionPreference = $backupEAP
    }
}

function Start-CrossGen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory= $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $PublishPath,

        [Parameter(Mandatory=$true)]
        [ValidateSet("alpine-x64",
                     "linux-arm",
                     "linux-arm64",
                     "linux-x64",
                     "osx-arm64",
                     "osx-x64",
                     "win-arm",
                     "win-arm64",
                     "win7-x64",
                     "win7-x86")]
        [string]
        $Runtime
    )

    function New-CrossGenAssembly {
        param (
            [Parameter(Mandatory= $true)]
            [ValidateNotNullOrEmpty()]
            [String]
            $AssemblyPath,
            [Parameter(Mandatory= $true)]
            [ValidateNotNullOrEmpty()]
            [String]
            $CrossgenPath
        )

        $outputAssembly = $AssemblyPath.Replace(".dll", ".ni.dll")
        $platformAssembliesPath = Split-Path $AssemblyPath -Parent
        $crossgenFolder = Split-Path $CrossgenPath
        $niAssemblyName = Split-Path $outputAssembly -Leaf

        try {
            Push-Location $crossgenFolder

            # Generate the ngen assembly
            Write-Verbose "Generating assembly $niAssemblyName"
            Start-NativeExecution {
                & $CrossgenPath /ReadyToRun /MissingDependenciesOK /in $AssemblyPath /out $outputAssembly /Platform_Assemblies_Paths $platformAssembliesPath
            } | Write-Verbose
        } finally {
            Pop-Location
        }
    }

    function New-CrossGenSymbol {
        param (
            [Parameter(Mandatory= $true)]
            [ValidateNotNullOrEmpty()]
            [String]
            $AssemblyPath,
            [Parameter(Mandatory= $true)]
            [ValidateNotNullOrEmpty()]
            [String]
            $CrossgenPath
        )


        $platformAssembliesPath = Split-Path $AssemblyPath -Parent
        $crossgenFolder = Split-Path $CrossgenPath

        try {
            Push-Location $crossgenFolder

            $symbolsPath = [System.IO.Path]::ChangeExtension($assemblyPath, ".pdb")

            $createSymbolOptionName = $null
            if($Environment.IsWindows)
            {
                $createSymbolOptionName = '-CreatePDB'

            }
            elseif ($Environment.IsLinux)
            {
                $createSymbolOptionName = '-CreatePerfMap'
            }

            if($createSymbolOptionName)
            {
                Start-NativeExecution {
                    & $CrossgenPath -readytorun -platform_assemblies_paths $platformAssembliesPath $createSymbolOptionName $platformAssembliesPath $AssemblyPath
                } | Write-Verbose
            }

            # Rename the corresponding ni.dll assembly to be the same as the IL assembly
            $niSymbolsPath = [System.IO.Path]::ChangeExtension($symbolsPath, "ni.pdb")
            Rename-Item $niSymbolsPath $symbolsPath -Force -ErrorAction Stop
        } finally {
            Pop-Location
        }
    }

    if (-not (Test-Path $PublishPath)) {
        throw "Path '$PublishPath' does not exist."
    }

    # Get the path to crossgen
    $crossGenExe = if ($environment.IsWindows) { "crossgen.exe" } else { "crossgen" }
    $generateSymbols = $false

    # The crossgen tool is only published for these particular runtimes
    $crossGenRuntime = if ($environment.IsWindows) {
        if ($Runtime -match "-x86") {
            "win-x86"
        } elseif ($Runtime -match "-x64") {
            "win-x64"
            $generateSymbols = $true
        } elseif (!($env:PROCESSOR_ARCHITECTURE -match "arm")) {
            throw "crossgen for 'win-arm' and 'win-arm64' must be run on that platform"
        }
    } elseif ($Runtime -eq "linux-arm") {
        throw "crossgen is not available for 'linux-arm'"
    } elseif ($Runtime -eq "linux-x64") {
        $Runtime
        # We should set $generateSymbols = $true, but the code needs to be adjusted for different extension on Linux
    } else {
        $Runtime
    }

    if (-not $crossGenRuntime) {
        throw "crossgen is not available for this platform"
    }

    $dotnetRuntimeVersion = $script:Options.Framework -replace 'net'

    # Get the CrossGen.exe for the correct runtime with the latest version
    $crossGenPath = Get-ChildItem $script:Environment.nugetPackagesRoot $crossGenExe -Recurse | `
                        Where-Object { $_.FullName -match $crossGenRuntime } | `
                        Where-Object { $_.FullName -match $dotnetRuntimeVersion } | `
                        Where-Object { (Split-Path $_.FullName -Parent).EndsWith('tools') } | `
                        Sort-Object -Property FullName -Descending | `
                        Select-Object -First 1 | `
                        ForEach-Object { $_.FullName }
    if (-not $crossGenPath) {
        throw "Unable to find latest version of crossgen.exe. 'Please run Start-PSBuild -Clean' first, and then try again."
    }
    Write-Verbose "Matched CrossGen.exe: $crossGenPath" -Verbose

    # Crossgen.exe requires the following assemblies:
    # mscorlib.dll
    # System.Private.CoreLib.dll
    # clrjit.dll on Windows or libclrjit.so/dylib on Linux/OS X
    $crossGenRequiredAssemblies = @("mscorlib.dll", "System.Private.CoreLib.dll")

    $crossGenRequiredAssemblies += if ($environment.IsWindows) {
        "clrjit.dll"
    } elseif ($environment.IsLinux) {
        "libclrjit.so"
    } elseif ($environment.IsMacOS) {
        "libclrjit.dylib"
    }

    # Make sure that all dependencies required by crossgen are at the directory.
    $crossGenFolder = Split-Path $crossGenPath
    foreach ($assemblyName in $crossGenRequiredAssemblies) {
        if (-not (Test-Path "$crossGenFolder\$assemblyName")) {
            Copy-Item -Path "$PublishPath\$assemblyName" -Destination $crossGenFolder -Force -ErrorAction Stop
        }
    }

    # Common assemblies used by Add-Type or assemblies with high JIT and no pdbs to crossgen
    $commonAssembliesForAddType = @(
        "Microsoft.CodeAnalysis.CSharp.dll"
        "Microsoft.CodeAnalysis.dll"
        "System.Linq.Expressions.dll"
        "Microsoft.CSharp.dll"
        "System.Runtime.Extensions.dll"
        "System.Linq.dll"
        "System.Collections.Concurrent.dll"
        "System.Collections.dll"
        "Newtonsoft.Json.dll"
        "System.IO.FileSystem.dll"
        "System.Diagnostics.Process.dll"
        "System.Threading.Tasks.Parallel.dll"
        "System.Security.AccessControl.dll"
        "System.Text.Encoding.CodePages.dll"
        "System.Private.Uri.dll"
        "System.Threading.dll"
        "System.Security.Principal.Windows.dll"
        "System.Console.dll"
        "Microsoft.Win32.Registry.dll"
        "System.IO.Pipes.dll"
        "System.Diagnostics.FileVersionInfo.dll"
        "System.Collections.Specialized.dll"
        "Microsoft.ApplicationInsights.dll"
    )

    $fullAssemblyList = $commonAssembliesForAddType

    foreach ($assemblyName in $fullAssemblyList) {
        $assemblyPath = Join-Path $PublishPath $assemblyName
        New-CrossGenAssembly -CrossgenPath $crossGenPath -AssemblyPath $assemblyPath
    }

    #
    # With the latest dotnet.exe, the default load context is only able to load TPAs, and TPA
    # only contains IL assembly names. In order to make the default load context able to load
    # the NI PS assemblies, we need to replace the IL PS assemblies with the corresponding NI
    # PS assemblies, but with the same IL assembly names.
    #
    Write-Verbose "PowerShell Ngen assemblies have been generated. Deploying ..." -Verbose
    foreach ($assemblyName in $fullAssemblyList) {

        # Remove the IL assembly and its symbols.
        $assemblyPath = Join-Path $PublishPath $assemblyName
        $symbolsPath = [System.IO.Path]::ChangeExtension($assemblyPath, ".pdb")

        Remove-Item $assemblyPath -Force -ErrorAction Stop

        # Rename the corresponding ni.dll assembly to be the same as the IL assembly
        $niAssemblyPath = [System.IO.Path]::ChangeExtension($assemblyPath, "ni.dll")
        Rename-Item $niAssemblyPath $assemblyPath -Force -ErrorAction Stop

        # No symbols are available for Microsoft.CodeAnalysis.CSharp.dll, Microsoft.CodeAnalysis.dll,
        # Microsoft.CodeAnalysis.VisualBasic.dll, and Microsoft.CSharp.dll.
        if ($commonAssembliesForAddType -notcontains $assemblyName) {
            Remove-Item $symbolsPath -Force -ErrorAction Stop

            if($generateSymbols)
            {
                Write-Verbose "Generating Symbols for $assemblyPath"
                New-CrossGenSymbol -CrossgenPath $crossGenPath -AssemblyPath $assemblyPath
            }
        }
    }
}

# Cleans the PowerShell repo - everything but the root folder
function Clear-PSRepo
{
    [CmdletBinding()]
    param()

    Get-ChildItem $PSScriptRoot\* -Directory | ForEach-Object {
        Write-Verbose "Cleaning $_ ..."
        git clean -fdX $_
    }
}

# Install PowerShell modules such as PackageManagement, PowerShellGet
function Copy-PSGalleryModules
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CsProjPath,

        [Parameter(Mandatory=$true)]
        [string]$Destination,

        [Parameter()]
        [switch]$Force
    )

    if (!$Destination.EndsWith("Modules")) {
        throw "Installing to an unexpected location"
    }

    Find-DotNet

    Restore-PSPackage -ProjectDirs (Split-Path $CsProjPath) -Force:$Force.IsPresent -PSModule

    $cache = dotnet nuget locals global-packages -l
    if ($cache -match "global-packages: (.*)") {
        $nugetCache = $Matches[1]
    }
    else {
        throw "Can't find nuget global cache"
    }

    $psGalleryProj = [xml](Get-Content -Raw $CsProjPath)

    foreach ($m in $psGalleryProj.Project.ItemGroup.PackageReference) {
        $name = $m.Include
        $version = $m.Version
        Write-Log -message "Name='$Name', Version='$version', Destination='$Destination'"

        # Remove the build revision from the src (nuget drops it).
        $srcVer = if ($version -match "(\d+.\d+.\d+).0") {
            $Matches[1]
        } elseif ($version -match "^\d+.\d+$") {
            # Two digit versions are stored as three digit versions
            "$version.0"
        } else {
            $version
        }

        # Nuget seems to always use lowercase in the cache
        $src = "$nugetCache/$($name.ToLower())/$srcVer"
        $dest = "$Destination/$name"

        Remove-Item -Force -ErrorAction Ignore -Recurse "$Destination/$name"
        New-Item -Path $dest -ItemType Directory -Force -ErrorAction Stop > $null
        # Exclude files/folders that are not needed. The fullclr folder is coming from the PackageManagement module
        $dontCopy = '*.nupkg', '*.nupkg.metadata', '*.nupkg.sha512', '*.nuspec', 'System.Runtime.InteropServices.RuntimeInformation.dll', 'fullclr'
        Copy-Item -Exclude $dontCopy -Recurse $src/* $dest -ErrorAction Stop
    }
}

function Merge-TestLogs
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_})]
        [string]$XUnitLogPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_})]
        [string[]]$NUnitLogPath,

        [Parameter()]
        [ValidateScript({Test-Path $_})]
        [string[]]$AdditionalXUnitLogPath,

        [Parameter()]
        [string]$OutputLogPath
    )

    # Convert all the NUnit logs into single object
    $convertedNUnit = ConvertFrom-PesterLog -logFile $NUnitLogPath

    $xunit = [xml] (Get-Content $XUnitLogPath -ReadCount 0 -Raw)

    $strBld = [System.Text.StringBuilder]::new($xunit.assemblies.InnerXml)

    foreach($assembly in $convertedNUnit.assembly)
    {
        $strBld.Append($assembly.ToString()) | Out-Null
    }

    foreach($path in $AdditionalXUnitLogPath)
    {
        $addXunit = [xml] (Get-Content $path -ReadCount 0 -Raw)
        $strBld.Append($addXunit.assemblies.InnerXml) | Out-Null
    }

    $xunit.assemblies.InnerXml = $strBld.ToString()
    $xunit.Save($OutputLogPath)
}

function ConvertFrom-PesterLog {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true, Position = 0)]
        [string[]]$Logfile,
        [Parameter()][switch]$IncludeEmpty,
        [Parameter()][switch]$MultipleLog
    )
    <#
Convert our test logs to
xunit schema - top level assemblies
Pester conversion
foreach $r in "test-results"."test-suite".results."test-suite"
assembly
    name = $r.Description
    config-file = log file (this is the only way we can determine between admin/nonadmin log)
    test-framework = Pester
    environment = top-level "test-results.environment.platform
    run-date = date (doesn't exist in pester except for beginning)
    run-time = time
    time =
#>

    BEGIN {
        # CLASSES
        class assemblies {
            # attributes
            [datetime]$timestamp
            # child elements
            [System.Collections.Generic.List[testAssembly]]$assembly
            assemblies() {
                $this.timestamp = [datetime]::now
                $this.assembly = [System.Collections.Generic.List[testAssembly]]::new()
            }
            static [assemblies] op_Addition([assemblies]$ls, [assemblies]$rs) {
                $newAssembly = [assemblies]::new()
                $newAssembly.assembly.AddRange($ls.assembly)
                $newAssembly.assembly.AddRange($rs.assembly)
                return $newAssembly
            }
            [string]ToString() {
                $sb = [text.stringbuilder]::new()
                $sb.AppendLine('<assemblies timestamp="{0:MM}/{0:dd}/{0:yyyy} {0:HH}:{0:mm}:{0:ss}">' -f $this.timestamp)
                foreach ( $a in $this.assembly  ) {
                    $sb.Append("$a")
                }
                $sb.AppendLine("</assemblies>");
                return $sb.ToString()
            }
            # use Write-Output to emit these into the pipeline
            [array]GetTests() {
                return $this.Assembly.collection.test
            }
        }

        class testAssembly {
            # attributes
            [string]$name # path to pester file
            [string]${config-file}
            [string]${test-framework} # Pester
            [string]$environment
            [string]${run-date}
            [string]${run-time}
            [decimal]$time
            [int]$total
            [int]$passed
            [int]$failed
            [int]$skipped
            [int]$errors
            testAssembly ( ) {
                $this."config-file" = "no config"
                $this."test-framework" = "Pester"
                $this.environment = $script:environment
                $this."run-date" = $script:rundate
                $this."run-time" = $script:runtime
                $this.collection = [System.Collections.Generic.List[collection]]::new()
            }
            # child elements
            [error[]]$error
            [System.Collections.Generic.List[collection]]$collection
            [string]ToString() {
                $sb = [System.Text.StringBuilder]::new()
                $sb.AppendFormat('  <assembly name="{0}" ', $this.name)
                $sb.AppendFormat('environment="{0}" ', [security.securityelement]::escape($this.environment))
                $sb.AppendFormat('test-framework="{0}" ', $this."test-framework")
                $sb.AppendFormat('run-date="{0}" ', $this."run-date")
                $sb.AppendFormat('run-time="{0}" ', $this."run-time")
                $sb.AppendFormat('total="{0}" ', $this.total)
                $sb.AppendFormat('passed="{0}" ', $this.passed)
                $sb.AppendFormat('failed="{0}" ', $this.failed)
                $sb.AppendFormat('skipped="{0}" ', $this.skipped)
                $sb.AppendFormat('time="{0}" ', $this.time)
                $sb.AppendFormat('errors="{0}" ', $this.errors)
                $sb.AppendLine(">")
                if ( $this.error ) {
                    $sb.AppendLine("    <errors>")
                    foreach ( $e in $this.error ) {
                        $sb.AppendLine($e.ToString())
                    }
                    $sb.AppendLine("    </errors>")
                } else {
                    $sb.AppendLine("    <errors />")
                }
                foreach ( $col in $this.collection ) {
                    $sb.AppendLine($col.ToString())
                }
                $sb.AppendLine("  </assembly>")
                return $sb.ToString()
            }
        }

        class collection {
            # attributes
            [string]$name
            [decimal]$time
            [int]$total
            [int]$passed
            [int]$failed
            [int]$skipped
            # child element
            [System.Collections.Generic.List[test]]$test
            # constructor
            collection () {
                $this.test = [System.Collections.Generic.List[test]]::new()
            }
            [string]ToString() {
                $sb = [Text.StringBuilder]::new()
                if ( $this.test.count -eq 0 ) {
                    $sb.AppendLine("    <collection />")
                } else {
                    $sb.AppendFormat('    <collection total="{0}" passed="{1}" failed="{2}" skipped="{3}" name="{4}" time="{5}">' + "`n",
                        $this.total, $this.passed, $this.failed, $this.skipped, [security.securityelement]::escape($this.name), $this.time)
                    foreach ( $t in $this.test ) {
                        $sb.AppendLine("    " + $t.ToString());
                    }
                    $sb.Append("    </collection>")
                }
                return $sb.ToString()
            }
        }

        class errors {
            [error[]]$error
        }
        class error {
            # attributes
            [string]$type
            [string]$name
            # child elements
            [failure]$failure
            [string]ToString() {
                $sb = [system.text.stringbuilder]::new()
                $sb.AppendLine('<error type="{0}" name="{1}" >' -f $this.type, [security.securityelement]::escape($this.Name))
                $sb.AppendLine($this.failure -as [string])
                $sb.AppendLine("</error>")
                return $sb.ToString()
            }
        }

        class cdata {
            [string]$text
            cdata ( [string]$s ) { $this.text = $s }
            [string]ToString() {
                return '<![CDATA[' + [security.securityelement]::escape($this.text) + ']]>'
            }
        }

        class failure {
            [string]${exception-type}
            [cdata]$message
            [cdata]${stack-trace}
            failure ( [string]$message, [string]$stack ) {
                $this."exception-type" = "Pester"
                $this.Message = [cdata]::new($message)
                $this."stack-trace" = [cdata]::new($stack)
            }
            [string]ToString() {
                $sb = [text.stringbuilder]::new()
                $sb.AppendLine("        <failure>")
                $sb.AppendLine("          <message>" + ($this.message -as [string]) + "</message>")
                $sb.AppendLine("          <stack-trace>" + ($this."stack-trace" -as [string]) + "</stack-trace>")
                $sb.Append("        </failure>")
                return $sb.ToString()
            }
        }

        enum resultenum {
            Pass
            Fail
            Skip
        }

        class trait {
            # attributes
            [string]$name
            [string]$value
        }
        class traits {
            [trait[]]$trait
        }
        class test {
            # attributes
            [string]$name
            [string]$type
            [string]$method
            [decimal]$time
            [resultenum]$result
            # child elements
            [trait[]]$traits
            [failure]$failure
            [cdata]$reason # skip reason
            [string]ToString() {
                $sb = [text.stringbuilder]::new()
                $sb.appendformat('  <test name="{0}" type="{1}" method="{2}" time="{3}" result="{4}"',
                    [security.securityelement]::escape($this.name), [security.securityelement]::escape($this.type),
                    [security.securityelement]::escape($this.method), $this.time, $this.result)
                if ( $this.failure ) {
                    $sb.AppendLine(">")
                    $sb.AppendLine($this.failure -as [string])
                    $sb.append('      </test>')
                } else {
                    $sb.Append("/>")
                }
                return $sb.ToString()
            }
        }

        function convert-pesterlog ( [xml]$x, $logpath, [switch]$includeEmpty ) {
            <#$resultMap = @{
                Success = "Pass"
                Ignored = "Skip"
                Failure = "Fail"
            }#>

            $resultMap = @{
                Success = "Pass"
                Ignored = "Skip"
                Failure = "Fail"
                Inconclusive = "Skip"
            }

            $configfile = $logpath
            $runtime = $x."test-results".time
            $environment = $x."test-results".environment.platform + "-" + $x."test-results".environment."os-version"
            $rundate = $x."test-results".date
            $suites = $x."test-results"."test-suite".results."test-suite"
            $assemblies = [assemblies]::new()
            foreach ( $suite in $suites ) {
                $tCases = $suite.SelectNodes(".//test-case")
                # only create an assembly group if we have tests
                if ( $tCases.count -eq 0 -and ! $includeEmpty ) { continue }
                $tGroup = $tCases | Group-Object result
                $total = $tCases.Count
                $asm = [testassembly]::new()
                $asm.environment = $environment
                $asm."run-date" = $rundate
                $asm."run-time" = $runtime
                $asm.Name = $suite.name
                $asm."config-file" = $configfile
                $asm.time = $suite.time
                $asm.total = $suite.SelectNodes(".//test-case").Count
                $asm.Passed = $tGroup| Where-Object -FilterScript {$_.Name -eq "Success"} | ForEach-Object -Process {$_.Count}
                $asm.Failed = $tGroup| Where-Object -FilterScript {$_.Name -eq "Failure"} | ForEach-Object -Process {$_.Count}
                $asm.Skipped = $tGroup| Where-Object -FilterScript { $_.Name -eq "Ignored" } | ForEach-Object -Process {$_.Count}
                $asm.Skipped += $tGroup| Where-Object -FilterScript { $_.Name -eq "Inconclusive" } | ForEach-Object -Process {$_.Count}
                $c = [collection]::new()
                $c.passed = $asm.Passed
                $c.failed = $asm.failed
                $c.skipped = $asm.skipped
                $c.total = $asm.total
                $c.time = $asm.time
                $c.name = $asm.name
                foreach ( $tc in $suite.SelectNodes(".//test-case")) {
                    if ( $tc.result -match "Success|Ignored|Failure" ) {
                        $t = [test]::new()
                        $t.name = $tc.Name
                        $t.time = $tc.time
                        $t.method = $tc.description # the pester actually puts the name of the "it" as description
                        $t.type = $suite.results."test-suite".description | Select-Object -First 1
                        $t.result = $resultMap[$tc.result]
                        if ( $tc.failure ) {
                            $t.failure = [failure]::new($tc.failure.message, $tc.failure."stack-trace")
                        }
                        $null = $c.test.Add($t)
                    }
                }
                $null = $asm.collection.add($c)
                $assemblies.assembly.Add($asm)
            }
            $assemblies
        }

        # convert it to our object model
        # a simple conversion
        function convert-xunitlog {
            param ( $x, $logpath )
            $asms = [assemblies]::new()
            $asms.timestamp = $x.assemblies.timestamp
            foreach ( $assembly in $x.assemblies.assembly ) {
                $asm = [testAssembly]::new()
                $asm.environment = $assembly.environment
                $asm."test-framework" = $assembly."test-framework"
                $asm."run-date" = $assembly."run-date"
                $asm."run-time" = $assembly."run-time"
                $asm.total = $assembly.total
                $asm.passed = $assembly.passed
                $asm.failed = $assembly.failed
                $asm.skipped = $assembly.skipped
                $asm.time = $assembly.time
                $asm.name = $assembly.name
                foreach ( $coll in $assembly.collection ) {
                    $c = [collection]::new()
                    $c.name = $coll.name
                    $c.total = $coll.total
                    $c.passed = $coll.passed
                    $c.failed = $coll.failed
                    $c.skipped = $coll.skipped
                    $c.time = $coll.time
                    foreach ( $t in $coll.test ) {
                        $test = [test]::new()
                        $test.name = $t.name
                        $test.type = $t.type
                        $test.method = $t.method
                        $test.time = $t.time
                        $test.result = $t.result
                        $c.test.Add($test)
                    }
                    $null = $asm.collection.add($c)
                }
                $null = $asms.assembly.add($asm)
            }
            $asms
        }
        $Logs = @()
    }

    PROCESS {
        #### MAIN ####
        foreach ( $log in $Logfile ) {
            foreach ( $logpath in (Resolve-Path $log).path ) {
                Write-Progress "converting file $logpath"
                if ( ! $logpath) { throw "Cannot resolve $Logfile" }
                $x = [xml](Get-Content -Raw -ReadCount 0 $logpath)

                if ( $x.psobject.properties['test-results'] ) {
                    $Logs += convert-pesterlog $x $logpath -includeempty:$includeempty
                } elseif ( $x.psobject.properties['assemblies'] ) {
                    $Logs += convert-xunitlog $x $logpath -includeEmpty:$includeEmpty
                } else {
                    Write-Error "Cannot determine log type"
                }
            }
        }
    }

    END {
        if ( $MultipleLog ) {
            $Logs
        } else {
            $combinedLog = $Logs[0]
            for ( $i = 1; $i -lt $logs.count; $i++ ) {
                $combinedLog += $Logs[$i]
            }
            $combinedLog
        }
    }
}

# Save PSOptions to be restored by Restore-PSOptions
function Save-PSOptions {
    param(
        [ValidateScript({$parent = Split-Path $_;if($parent){Test-Path $parent}else{return $true}})]
        [ValidateNotNullOrEmpty()]
        [string]
        $PSOptionsPath = (Join-Path -Path $PSScriptRoot -ChildPath 'psoptions.json'),

        [ValidateNotNullOrEmpty()]
        [object]
        $Options = (Get-PSOptions -DefaultToNew)
    )

    $Options | ConvertTo-Json -Depth 3 | Out-File -Encoding utf8 -FilePath $PSOptionsPath
}

# Restore PSOptions
# Optionally remove the PSOptions file
function Restore-PSOptions {
    param(
        [ValidateScript({Test-Path $_})]
        [string]
        $PSOptionsPath = (Join-Path -Path $PSScriptRoot -ChildPath 'psoptions.json'),
        [switch]
        $Remove
    )

    $options = Get-Content -Path $PSOptionsPath | ConvertFrom-Json

    if($Remove)
    {
        # Remove PSOptions.
        # The file is only used to set the PSOptions.
        Remove-Item -Path $psOptionsPath -Force
    }

    $newOptions = New-PSOptionsObject `
                    -RootInfo $options.RootInfo `
                    -Top $options.Top `
                    -Runtime $options.Runtime `
                    -Crossgen $options.Crossgen `
                    -Configuration $options.Configuration `
                    -PSModuleRestore $options.PSModuleRestore `
                    -Framework $options.Framework `
                    -Output $options.Output `
                    -ForMinimalSize $options.ForMinimalSize

    Set-PSOptions -Options $newOptions
}

function New-PSOptionsObject
{
    param(
        [PSCustomObject]
        $RootInfo,

        [Parameter(Mandatory)]
        [String]
        $Top,

        [Parameter(Mandatory)]
        [String]
        $Runtime,

        [Parameter(Mandatory)]
        [Bool]
        $CrossGen,

        [Parameter(Mandatory)]
        [String]
        $Configuration,

        [Parameter(Mandatory)]
        [Bool]
        $PSModuleRestore,

        [Parameter(Mandatory)]
        [String]
        $Framework,

        [Parameter(Mandatory)]
        [String]
        $Output,

        [Parameter(Mandatory)]
        [Bool]
        $ForMinimalSize
    )

    return @{
        RootInfo = $RootInfo
        Top = $Top
        Configuration = $Configuration
        Framework = $Framework
        Runtime = $Runtime
        Output = $Output
        CrossGen = $CrossGen
        PSModuleRestore = $PSModuleRestore
        ForMinimalSize = $ForMinimalSize
    }
}

$script:RESX_TEMPLATE = @'
<?xml version="1.0" encoding="utf-8"?>
<root>
  <!--
    Microsoft ResX Schema

    Version 2.0

    The primary goals of this format is to allow a simple XML format
    that is mostly human readable. The generation and parsing of the
    various data types are done through the TypeConverter classes
    associated with the data types.

    Example:

    ... ado.net/XML headers & schema ...
    <resheader name="resmimetype">text/microsoft-resx</resheader>
    <resheader name="version">2.0</resheader>
    <resheader name="reader">System.Resources.ResXResourceReader, System.Windows.Forms, ...</resheader>
    <resheader name="writer">System.Resources.ResXResourceWriter, System.Windows.Forms, ...</resheader>
    <data name="Name1"><value>this is my long string</value><comment>this is a comment</comment></data>
    <data name="Color1" type="System.Drawing.Color, System.Drawing">Blue</data>
    <data name="Bitmap1" mimetype="application/x-microsoft.net.object.binary.base64">
        <value>[base64 mime encoded serialized .NET Framework object]</value>
    </data>
    <data name="Icon1" type="System.Drawing.Icon, System.Drawing" mimetype="application/x-microsoft.net.object.bytearray.base64">
        <value>[base64 mime encoded string representing a byte array form of the .NET Framework object]</value>
        <comment>This is a comment</comment>
    </data>

    There are any number of "resheader" rows that contain simple
    name/value pairs.

    Each data row contains a name, and value. The row also contains a
    type or mimetype. Type corresponds to a .NET class that support
    text/value conversion through the TypeConverter architecture.
    Classes that don't support this are serialized and stored with the
    mimetype set.

    The mimetype is used for serialized objects, and tells the
    ResXResourceReader how to depersist the object. This is currently not
    extensible. For a given mimetype the value must be set accordingly:

    Note - application/x-microsoft.net.object.binary.base64 is the format
    that the ResXResourceWriter will generate, however the reader can
    read any of the formats listed below.

    mimetype: application/x-microsoft.net.object.binary.base64
    value   : The object must be serialized with
            : System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
            : and then encoded with base64 encoding.

    mimetype: application/x-microsoft.net.object.soap.base64
    value   : The object must be serialized with
            : System.Runtime.Serialization.Formatters.Soap.SoapFormatter
            : and then encoded with base64 encoding.

    mimetype: application/x-microsoft.net.object.bytearray.base64
    value   : The object must be serialized into a byte array
            : using a System.ComponentModel.TypeConverter
            : and then encoded with base64 encoding.
    -->
  <xsd:schema id="root" xmlns="" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:msdata="urn:schemas-microsoft-com:xml-msdata">
    <xsd:import namespace="http://www.w3.org/XML/1998/namespace" />
    <xsd:element name="root" msdata:IsDataSet="true">
      <xsd:complexType>
        <xsd:choice maxOccurs="unbounded">
          <xsd:element name="metadata">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="value" type="xsd:string" minOccurs="0" />
              </xsd:sequence>
              <xsd:attribute name="name" use="required" type="xsd:string" />
              <xsd:attribute name="type" type="xsd:string" />
              <xsd:attribute name="mimetype" type="xsd:string" />
              <xsd:attribute ref="xml:space" />
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="assembly">
            <xsd:complexType>
              <xsd:attribute name="alias" type="xsd:string" />
              <xsd:attribute name="name" type="xsd:string" />
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="data">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="value" type="xsd:string" minOccurs="0" msdata:Ordinal="1" />
                <xsd:element name="comment" type="xsd:string" minOccurs="0" msdata:Ordinal="2" />
              </xsd:sequence>
              <xsd:attribute name="name" type="xsd:string" use="required" msdata:Ordinal="1" />
              <xsd:attribute name="type" type="xsd:string" msdata:Ordinal="3" />
              <xsd:attribute name="mimetype" type="xsd:string" msdata:Ordinal="4" />
              <xsd:attribute ref="xml:space" />
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="resheader">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="value" type="xsd:string" minOccurs="0" msdata:Ordinal="1" />
              </xsd:sequence>
              <xsd:attribute name="name" type="xsd:string" use="required" />
            </xsd:complexType>
          </xsd:element>
        </xsd:choice>
      </xsd:complexType>
    </xsd:element>
  </xsd:schema>
  <resheader name="resmimetype">
    <value>text/microsoft-resx</value>
  </resheader>
  <resheader name="version">
    <value>2.0</value>
  </resheader>
  <resheader name="reader">
    <value>System.Resources.ResXResourceReader, System.Windows.Forms, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
  <resheader name="writer">
    <value>System.Resources.ResXResourceWriter, System.Windows.Forms, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
{0}
</root>
'@

function Get-UniquePackageFolderName {
    param(
        [Parameter(Mandatory)] $Root
    )

    $packagePath = Join-Path $Root 'TestPackage'

    $triesLeft = 10

    while(Test-Path $packagePath) {
        $suffix = Get-Random

        # Not using Guid to avoid maxpath problems as in example below.
        # Example: 'TestPackage-ba0ae1db-8512-46c5-8b6c-1862d33a2d63\test\powershell\Modules\Microsoft.PowerShell.Security\TestData\CatalogTestData\UserConfigProv\DSCResources\UserConfigProviderModVersion1\UserConfigProviderModVersion1.schema.mof'
        $packagePath = Join-Path $Root "TestPackage_$suffix"
        $triesLeft--

        if ($triesLeft -le 0) {
            throw "Could find unique folder name for package path"
        }
    }

    $packagePath
}

function New-TestPackage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Destination,
        [string] $Runtime
    )

    if (Test-Path $Destination -PathType Leaf)
    {
        throw "Destination: '$Destination' is not a directory or does not exist."
    }
    else
    {
        $null = New-Item -Path $Destination -ItemType Directory -Force
        Write-Verbose -Message "Creating destination folder: $Destination"
    }

    $rootFolder = $env:TEMP

    # In some build agents, typically macOS on AzDevOps, $env:TEMP might not be set.
    if (-not $rootFolder -and $env:TF_BUILD) {
        $rootFolder = $env:AGENT_WORKFOLDER
    }

    Write-Verbose -Message "RootFolder: $rootFolder" -Verbose
    $packageRoot = Get-UniquePackageFolderName -Root $rootFolder

    $null = New-Item -ItemType Directory -Path $packageRoot -Force
    $packagePath = Join-Path $Destination "TestPackage.zip"
    Write-Verbose -Message "PackagePath: $packagePath" -Verbose

    # Build test tools so they are placed in appropriate folders under 'test' then copy to package root.
    $null = Publish-PSTestTools -runtime $Runtime
    $powerShellTestRoot =  Join-Path $PSScriptRoot 'test'
    Copy-Item $powerShellTestRoot -Recurse -Destination $packageRoot -Force
    Write-Verbose -Message "Copied test directory"

    # Copy assests folder to package root for wix related tests.
    $assetsPath = Join-Path $PSScriptRoot 'assets'
    Copy-Item $assetsPath -Recurse -Destination $packageRoot -Force
    Write-Verbose -Message "Copied assests directory"

    # Create expected folder structure for resx files in package root.
    $srcRootForResx = New-Item -Path "$packageRoot/src" -Force -ItemType Directory

    $resourceDirectories = Get-ChildItem -Recurse "$PSScriptRoot/src" -Directory -Filter 'resources'

    $resourceDirectories | ForEach-Object {
        $directoryFullName = $_.FullName

        $partToRemove = Join-Path $PSScriptRoot "src"

        $assemblyPart = $directoryFullName.Replace($partToRemove, '')
        $assemblyPart = $assemblyPart.TrimStart([io.path]::DirectorySeparatorChar)
        $resxDestPath = Join-Path $srcRootForResx $assemblyPart
        $null = New-Item -Path $resxDestPath -Force -ItemType Directory
        Write-Verbose -Message "Created resx directory : $resxDestPath"
        Copy-Item -Path "$directoryFullName\*" -Recurse $resxDestPath -Force
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if(Test-Path $packagePath)
    {
        Remove-Item -Path $packagePath -Force
    }

    [System.IO.Compression.ZipFile]::CreateFromDirectory($packageRoot, $packagePath)
}

function New-NugetConfigFile
{
    param(
        [Parameter(Mandatory=$true)] [string] $NugetFeedUrl,
        [Parameter(Mandatory=$true)] [string] $FeedName,
        [Parameter(Mandatory=$true)] [string] $UserName,
        [Parameter(Mandatory=$true)] [string] $ClearTextPAT,
        [Parameter(Mandatory=$true)] [string] $Destination
    )

    $nugetConfigTemplate = @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="[FEEDNAME]" value="[FEED]" />
  </packageSources>
  <disabledPackageSources>
    <clear />
  </disabledPackageSources>
  <packageSourceCredentials>
    <[FEEDNAME]>
      <add key="Username" value="[USERNAME]" />
      <add key="ClearTextPassword" value="[PASSWORD]" />
    </[FEEDNAME]>
  </packageSourceCredentials>
</configuration>
'@

    $content = $nugetConfigTemplate.Replace('[FEED]', $NugetFeedUrl).Replace('[FEEDNAME]', $FeedName).Replace('[USERNAME]', $UserName).Replace('[PASSWORD]', $ClearTextPAT)

    Set-Content -Path (Join-Path $Destination 'nuget.config') -Value $content -Force
}
Windows PowerShell
Copyright (C) Microsoft Corporation. All rights reserved.

Try the new cross-platform PowerShell https://aka.ms/pscore6

PS C:\WINDOWS\system32> <!DOCTYPE html>
>> <html xmlns="http://www.w3.org/1999/xhtml">
>> <head>
>>     <meta charset="utf-8" />
>>     <meta content="pdf2htmlEX" name="generator" />
>>     <meta content="IE=edge,chrome=1" http-equiv="X-UA-Compatible" />
>>     <style type="text/css">/*!
>>  * Base CSS for pdf2htmlEX
>>  * Copyright 2012,2013 Lu Wang <coolwanglu@gmail.com>
>>  * https://github.com/coolwanglu/pdf2htmlEX/blob/master/share/LICENSE
>>  */#sidebar{position:absolute;top:0;left:0;bottom:0;width:250px;padding:0;margin:0;overflow:auto}#page-container{posi
tion:absolute;top:0;left:0;margin:0;padding:0;border:0}@media screen{#sidebar.opened+#page-container{left:250px}#page-co
ntainer{bottom:0;right:0;overflow:auto}.loading-indicator{display:none}.loading-indicator.active{display:block;position:
absolute;width:64px;height:64px;top:50%;left:50%;margin-top:-32px;margin-left:-32px}.loading-indicator img{position:abso
lute;top:0;left:0;bottom:0;right:0}}@media print{@page{margin:0}html{margin:0}body{margin:0;-webkit-print-color-adjust:e
xact}#sidebar{display:none}#page-container{width:auto;height:auto;overflow:visible;background-color:transparent}.d{displ
ay:none}}.pf{position:relative;background-color:white;overflow:hidden;margin:0;border:0}.pc{position:absolute;border:0;p
adding:0;margin:0;top:0;left:0;width:100%;height:100%;overflow:hidden;display:block;transform-origin:0 0;-ms-transform-o
rigin:0 0;-webkit-transform-origin:0 0}.pc.opened{display:block}.bf{position:absolute;border:0;margin:0;top:0;bottom:0;w
idth:100%;height:100%;-ms-user-select:none;-moz-user-select:none;-webkit-user-select:none;user-select:none}.bi{position:
absolute;border:0;margin:0;-ms-user-select:none;-moz-user-select:none;-webkit-user-select:none;user-select:none}@media p
rint{.pf{margin:0;box-shadow:none;page-break-after:always;page-break-inside:avoid}@-moz-document url-prefix(){.pf{overfl
ow:visible;border:1px solid #fff}.pc{overflow:visible}}}.c{position:absolute;border:0;padding:0;margin:0;overflow:hidden
;display:block}.t{position:absolute;white-space:pre;font-size:1px;transform-origin:0 100%;-ms-transform-origin:0 100%;-w
ebkit-transform-origin:0 100%;unicode-bidi:bidi-override;-moz-font-feature-settings:"liga" 0}.t:after{content:''}.t:befo
re{content:'';display:inline-block}.t span{position:relative;unicode-bidi:bidi-override}._{display:inline-block;color:tr
ansparent;z-index:-1}::selection{background:rgba(127,255,255,0.4)}::-moz-selection{background:rgba(127,255,255,0.4)}.pi{
display:none}.d{position:absolute;transform-origin:0 100%;-ms-transform-origin:0 100%;-webkit-transform-origin:0 100%}.i
t{border:0;background-color:rgba(255,255,255,0.0)}.ir:hover{cursor:pointer}
>>     </style>
>>     <style type="text/css">/*!
>>  * Fancy styles for pdf2htmlEX
>>  * Copyright 2012,2013 Lu Wang <coolwanglu@gmail.com>
>>  * https://github.com/coolwanglu/pdf2htmlEX/blob/master/share/LICENSE
>>  */@keyframes fadein{from{opacity:0}to{opacity:1}}@-webkit-keyframes fadein{from{opacity:0}to{opacity:1}}@keyframes s
wing{0{transform:rotate(0)}10%{transform:rotate(0)}90%{transform:rotate(720deg)}100%{transform:rotate(720deg)}}@-webkit-
keyframes swing{0{-webkit-transform:rotate(0)}10%{-webkit-transform:rotate(0)}90%{-webkit-transform:rotate(720deg)}100%{
-webkit-transform:rotate(720deg)}}@media screen{#sidebar{background-color:#2f3236;background-image:url("data:image/svg+x
ml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI0IiBoZWlnaHQ9IjQiPgo8cmVjdCB3aWR0aD0iNCIgaGVpZ2
h0PSI0IiBmaWxsPSIjNDAzYzNmIj48L3JlY3Q+CjxwYXRoIGQ9Ik0wIDBMNCA0Wk00IDBMMCA0WiIgc3Ryb2tlLXdpZHRoPSIxIiBzdHJva2U9IiMxZTI5Mm
QiPjwvcGF0aD4KPC9zdmc+")}#outline{font-family:Georgia,Times,"Times New Roman",serif;font-size:13px;margin:2em 1em}#outli
ne ul{padding:0}#outline li{list-style-type:none;margin:1em 0}#outline li>ul{margin-left:1em}#outline a,#outline a:visit
ed,#outline a:hover,#outline a:active{line-height:1.2;color:#e8e8e8;text-overflow:ellipsis;white-space:nowrap;text-decor
ation:none;display:block;overflow:hidden;outline:0}#outline a:hover{color:#0cf}#page-container{background-color:#9e9e9e;
background-image:url("data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI1IiBoZWln
aHQ9IjUiPgo8cmVjdCB3aWR0aD0iNSIgaGVpZ2h0PSI1IiBmaWxsPSIjOWU5ZTllIj48L3JlY3Q+CjxwYXRoIGQ9Ik0wIDVMNSAwWk02IDRMNCA2Wk0tMSAx
TDEgLTFaIiBzdHJva2U9IiM4ODgiIHN0cm9rZS13aWR0aD0iMSI+PC9wYXRoPgo8L3N2Zz4=");-webkit-transition:left 500ms;transition:left
 500ms}.pf{margin:13px auto;box-shadow:1px 1px 3px 1px #333;border-collapse:separate}.pc.opened{-webkit-animation:fadein
 100ms;animation:fadein 100ms}.loading-indicator.active{-webkit-animation:swing 1.5s ease-in-out .01s infinite alternate
 none;animation:swing 1.5s ease-in-out .01s infinite alternate none}.checked{background:no-repeat url(data:image/png;bas
e64,iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAB3RJTUUH3goQDSYg
DiGofgAAAslJREFUOMvtlM9LFGEYx7/vvOPM6ywuuyPFihWFBUsdNnA6KLIh+QPx4KWExULdHQ/9A9EfUodYmATDYg/iRewQzklFWxcEBcGgEplDkDtI6sw4
PzrIbrOuedBb9MALD7zv+3m+z4/3Bf7bZS2bzQIAcrmcMDExcTeXy10DAFVVAQDksgFUVZ1ljD3yfd+0LOuFpmnvVVW9GHhkZAQcxwkNDQ2FSCQyRMgJxnVd
y7KstKZpn7nwha6urqqfTqfPBAJAuVymlNLXoigOhfd5nmeiKL5TVTV+lmIKwAOA7u5u6Lped2BsbOwjY6yf4zgQQkAIAcedaPR9H67r3uYBQFEUFItFtLe3
32lpaVkUBOHK3t5eRtf1DwAwODiIubk5DA8PM8bYW1EU+wEgCIJqsCAIQAiB7/u253k2BQDDMJBKpa4mEon5eDx+UxAESJL0uK2t7XosFlvSdf0QAEmlUnlR
FJ9Waho2Qghc1/U9z3uWz+eX+Wr+lL6SZfleEAQIggA8z6OpqSknimIvYyybSCReMsZ6TislhCAIAti2Dc/zejVNWwCAavN8339j27YbTg0AGGM3WltbP4Wh
lRWq6Q/btrs1TVsYHx+vNgqKoqBUKn2NRqPFxsbGJzzP05puUlpt0ukyOI6z7zjOwNTU1OLo6CgmJyf/gA3DgKIoWF1d/cIY24/FYgOU0pp0z/Ityzo8Pj5O
Tk9PbwHA+vp6zWghDC+VSiuRSOQgGo32UErJ38CO42wdHR09LBQK3zKZDDY2NupmFmF4R0cHVlZWlmRZ/iVJUn9FeWWcCCE4ODjYtG27Z2Zm5juAOmgdGAB2
d3cBADs7O8uSJN2SZfl+WKlpmpumaT6Yn58vn/fs6XmbhmHMNjc3tzDGFI7jYJrm5vb29sDa2trPC/9aiqJUy5pOp4f6+vqeJ5PJBAB0dnZe/t8NBajx/z37
Df5OGX8d13xzAAAAAElFTkSuQmCC)}}
>>     </style>
>>     <style type="text/css">.ff0{font-family:sans-serif;visibility:hidden;}
>> @font-face{font-family:ff1;src:url('data:application/font-woff;base64,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
g')format("woff");}.ff1{font-family:ff1;line-height:0.910156;font-style:normal;font-weight:normal;visibility:visible;}
>> @font-face{font-family:ff2;src:url('data:application/font-woff;base64,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
BAAAAANOF9V4AAAAAouMnKgAAAADWhOTs')format("woff");}.ff2{font-family:ff2;line-height:0.740234;font-style:normal;font-weig
ht:normal;visibility:visible;}
>> @font-face{font-family:ff3;src:url('data:application/font-woff;base64,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
jNUYAAAAA1oTYYg==')format("woff");}.ff3{font-family:ff3;line-height:0.893555;font-style:normal;font-weight:normal;visibi
lity:visible;}
>> .m0{transform:matrix(0.250000,0.000000,0.000000,0.250000,0,0);-ms-transform:matrix(0.250000,0.000000,0.000000,0.25000
0,0,0);-webkit-transform:matrix(0.250000,0.000000,0.000000,0.250000,0,0);}
>> .m1{transform:none;-ms-transform:none;-webkit-transform:none;}
>> .v0{vertical-align:0.000000px;}
>> .ls0{letter-spacing:0.000000px;}
>> .sc_{text-shadow:none;}
>> .sc0{text-shadow:-0.015em 0 transparent,0 0.015em transparent,0.015em 0 transparent,0 -0.015em  transparent;}
>> @media screen and (-webkit-min-device-pixel-ratio:0){
>> .sc_{-webkit-text-stroke:0px transparent;}
>> .sc0{-webkit-text-stroke:0.015em transparent;text-shadow:none;}
>> }
>> .ws0{word-spacing:0.000000px;}
>> ._2{margin-left:-4.806838px;}
>> ._3{margin-left:-2.884104px;}
>> ._1{width:63.028183px;}
>> ._0{width:120.053682px;}
>> .fc2{color:rgb(117,117,117);}
>> .fc1{color:rgb(0,0,0);}
>> .fc0{color:rgb(0,0,238);}
>> .fs1{font-size:40.007889px;}
>> .fs0{font-size:48.021473px;}
>> .ye{bottom:3.001330px;}
>> .y25{bottom:7.503364px;}
>> .y0{bottom:18.500000px;}
>> .y1{bottom:18.600282px;}
>> .y24{bottom:21.009403px;}
>> .y23{bottom:34.515442px;}
>> .y22{bottom:48.021482px;}
>> .y21{bottom:61.527521px;}
>> .y20{bottom:75.033560px;}
>> .y1f{bottom:90.040270px;}
>> .y1e{bottom:120.804026px;}
>> .y1d{bottom:150.067111px;}
>> .y1c{bottom:177.079190px;}
>> .y1b{bottom:190.585229px;}
>> .y1a{bottom:204.091268px;}
>> .y19{bottom:217.597308px;}
>> .y18{bottom:231.103347px;}
>> .y17{bottom:244.609386px;}
>> .y16{bottom:258.115425px;}
>> .y15{bottom:303.885891px;}
>> .y14{bottom:329.397299px;}
>> .y13{bottom:354.908706px;}
>> .y12{bottom:381.920785px;}
>> .y11{bottom:395.426824px;}
>> .y10{bottom:408.932863px;}
>> .yf{bottom:422.438903px;}
>> .yd{bottom:453.044565px;}
>> .yc{bottom:489.218763px;}
>> .yb{bottom:516.230842px;}
>> .ya{bottom:543.242920px;}
>> .y9{bottom:570.254999px;}
>> .y8{bottom:597.267077px;}
>> .y7{bottom:659.544925px;}
>> .y6{bottom:686.557003px;}
>> .y5{bottom:700.063042px;}
>> .y4{bottom:727.075121px;}
>> .y3{bottom:742.832166px;}
>> .y2{bottom:768.343574px;}
>> .h4{height:12.755683px;}
>> .h5{height:29.126837px;}
>> .h6{height:32.545803px;}
>> .h3{height:33.343034px;}
>> .h2{height:804.359678px;}
>> .h1{height:804.500000px;}
>> .h0{height:840.960000px;}
>> .w3{width:129.808046px;}
>> .w2{width:558.999937px;}
>> .w1{width:559.000000px;}
>> .w0{width:594.960000px;}
>> .x7{left:1.500672px;}
>> .x8{left:6.002684px;}
>> .x0{left:18.000000px;}
>> .x2{left:36.016105px;}
>> .x1{left:39.767782px;}
>> .x9{left:42.018789px;}
>> .x3{left:43.519460px;}
>> .x6{left:59.268451px;}
>> .x4{left:62.277848px;}
>> .x5{left:66.029525px;}
>> @media print{
>> .v0{vertical-align:0.000000pt;}
>> .ls0{letter-spacing:0.000000pt;}
>> .ws0{word-spacing:0.000000pt;}
>> ._2{margin-left:-6.409118pt;}
>> ._3{margin-left:-3.845472pt;}
>> ._1{width:84.037577pt;}
>> ._0{width:160.071576pt;}
>> .fs1{font-size:53.343852pt;}
>> .fs0{font-size:64.028630pt;}
>> .ye{bottom:4.001773pt;}
>> .y25{bottom:10.004485pt;}
>> .y0{bottom:24.666667pt;}
>> .y1{bottom:24.800376pt;}
>> .y24{bottom:28.012538pt;}
>> .y23{bottom:46.020590pt;}
>> .y22{bottom:64.028642pt;}
>> .y21{bottom:82.036695pt;}
>> .y20{bottom:100.044747pt;}
>> .y1f{bottom:120.053694pt;}
>> .y1e{bottom:161.072035pt;}
>> .y1d{bottom:200.089482pt;}
>> .y1c{bottom:236.105586pt;}
>> .y1b{bottom:254.113639pt;}
>> .y1a{bottom:272.121691pt;}
>> .y19{bottom:290.129743pt;}
>> .y18{bottom:308.137796pt;}
>> .y17{bottom:326.145848pt;}
>> .y16{bottom:344.153900pt;}
>> .y15{bottom:405.181189pt;}
>> .y14{bottom:439.196399pt;}
>> .y13{bottom:473.211608pt;}
>> .y12{bottom:509.227713pt;}
>> .y11{bottom:527.235765pt;}
>> .y10{bottom:545.243818pt;}
>> .yf{bottom:563.251870pt;}
>> .yd{bottom:604.059420pt;}
>> .yc{bottom:652.291684pt;}
>> .yb{bottom:688.307789pt;}
>> .ya{bottom:724.323893pt;}
>> .y9{bottom:760.339998pt;}
>> .y8{bottom:796.356103pt;}
>> .y7{bottom:879.393233pt;}
>> .y6{bottom:915.409337pt;}
>> .y5{bottom:933.417390pt;}
>> .y4{bottom:969.433494pt;}
>> .y3{bottom:990.442889pt;}
>> .y2{bottom:1024.458098pt;}
>> .h4{height:17.007578pt;}
>> .h5{height:38.835783pt;}
>> .h6{height:43.394404pt;}
>> .h3{height:44.457379pt;}
>> .h2{height:1072.479571pt;}
>> .h1{height:1072.666667pt;}
>> .h0{height:1121.280000pt;}
>> .w3{width:173.077394pt;}
>> .w2{width:745.333249pt;}
>> .w1{width:745.333333pt;}
>> .w0{width:793.280000pt;}
>> .x7{left:2.000896pt;}
>> .x8{left:8.003579pt;}
>> .x0{left:24.000000pt;}
>> .x2{left:48.021473pt;}
>> .x1{left:53.023710pt;}
>> .x9{left:56.025052pt;}
>> .x3{left:58.025946pt;}
>> .x6{left:79.024602pt;}
>> .x4{left:83.037130pt;}
>> .x5{left:88.039367pt;}
>> }
>>     </style>
>>     <script>
>> /*
>>  Copyright 2012 Mozilla Foundation
>>  Copyright 2013 Lu Wang <coolwanglu@gmail.com>
>>  Apachine License Version 2.0
>> */
>> (function(){function b(a,b,e,f){var c=(a.className||"").split(/\s+/g);""===c[0]&&c.shift();var d=c.indexOf(b);0>d&&e&
&c.push(b);0<=d&&f&&c.splice(d,1);a.className=c.join(" ");return 0<=d}if(!("classList"in document.createElement("div")))
{var e={add:function(a){b(this.element,a,!0,!1)},contains:function(a){return b(this.element,a,!1,!1)},remove:function(a)
{b(this.element,a,!1,!0)},toggle:function(a){b(this.element,a,!0,!0)}};Object.defineProperty(HTMLElement.prototype,"clas
sList",{get:function(){if(this._classList)return this._classList;
>> var a=Object.create(e,{element:{value:this,writable:!1,enumerable:!0}});Object.defineProperty(this,"_classList",{valu
e:a,writable:!1,enumerable:!1});return a},enumerable:!0})}})();
>> </script><script>
>> (function(){/*
>>  pdf2htmlEX.js: Core UI functions for pdf2htmlEX
>>  Copyright 2012,2013 Lu Wang <coolwanglu@gmail.com> and other contributors
>>  https://github.com/coolwanglu/pdf2htmlEX/blob/master/share/LICENSE
>> */
>> var pdf2htmlEX=window.pdf2htmlEX=window.pdf2htmlEX||{},CSS_CLASS_NAMES={page_frame:"pf",page_content_box:"pc",page_da
ta:"pi",background_image:"bi",link:"l",input_radio:"ir",__dummy__:"no comma"},DEFAULT_CONFIG={container_id:"page-contain
er",sidebar_id:"sidebar",outline_id:"outline",loading_indicator_cls:"loading-indicator",preload_pages:3,render_timeout:1
00,scale_step:0.9,key_handler:!0,hashchange_handler:!0,view_history_handler:!0,__dummy__:"no comma"},EPS=1E-6;
>> function invert(a){var b=a[0]*a[3]-a[1]*a[2];return[a[3]/b,-a[1]/b,-a[2]/b,a[0]/b,(a[2]*a[5]-a[3]*a[4])/b,(a[1]*a[4]-
a[0]*a[5])/b]}function transform(a,b){return[a[0]*b[0]+a[2]*b[1]+a[4],a[1]*b[0]+a[3]*b[1]+a[5]]}function get_page_number
(a){return parseInt(a.getAttribute("data-page-no"),16)}function disable_dragstart(a){for(var b=0,c=a.length;b<c;++b)a[b]
.addEventListener("dragstart",function(){return!1},!1)}
>> function clone_and_extend_objs(a){for(var b={},c=0,e=arguments.length;c<e;++c){var h=arguments[c],d;for(d in h)h.hasO
wnProperty(d)&&(b[d]=h[d])}return b}
>> function Page(a){if(a){this.shown=this.loaded=!1;this.page=a;this.num=get_page_number(a);this.original_height=a.clien
tHeight;this.original_width=a.clientWidth;var b=a.getElementsByClassName(CSS_CLASS_NAMES.page_content_box)[0];b&&(this.c
ontent_box=b,this.original_scale=this.cur_scale=this.original_height/b.clientHeight,this.page_data=JSON.parse(a.getEleme
ntsByClassName(CSS_CLASS_NAMES.page_data)[0].getAttribute("data-data")),this.ctm=this.page_data.ctm,this.ictm=invert(thi
s.ctm),this.loaded=!0)}}
>> Page.prototype={hide:function(){this.loaded&&this.shown&&(this.content_box.classList.remove("opened"),this.shown=!1)}
,show:function(){this.loaded&&!this.shown&&(this.content_box.classList.add("opened"),this.shown=!0)},rescale:function(a)
{this.cur_scale=0===a?this.original_scale:a;this.loaded&&(a=this.content_box.style,a.msTransform=a.webkitTransform=a.tra
nsform="scale("+this.cur_scale.toFixed(3)+")");a=this.page.style;a.height=this.original_height*this.cur_scale+"px";a.wid
th=this.original_width*this.cur_scale+
>> "px"},view_position:function(){var a=this.page,b=a.parentNode;return[b.scrollLeft-a.offsetLeft-a.clientLeft,b.scrollT
op-a.offsetTop-a.clientTop]},height:function(){return this.page.clientHeight},width:function(){return this.page.clientWi
dth}};function Viewer(a){this.config=clone_and_extend_objs(DEFAULT_CONFIG,0<arguments.length?a:{});this.pages_loading=[]
;this.init_before_loading_content();var b=this;document.addEventListener("DOMContentLoaded",function(){b.init_after_load
ing_content()},!1)}
>> Viewer.prototype={scale:1,cur_page_idx:0,first_page_idx:0,init_before_loading_content:function(){this.pre_hide_pages(
)},initialize_radio_button:function(){for(var a=document.getElementsByClassName(CSS_CLASS_NAMES.input_radio),b=0;b<a.len
gth;b++)a[b].addEventListener("click",function(){this.classList.toggle("checked")})},init_after_loading_content:function
(){this.sidebar=document.getElementById(this.config.sidebar_id);this.outline=document.getElementById(this.config.outline
_id);this.container=document.getElementById(this.config.container_id);
>> this.loading_indicator=document.getElementsByClassName(this.config.loading_indicator_cls)[0];for(var a=!0,b=this.outl
ine.childNodes,c=0,e=b.length;c<e;++c)if("ul"===b[c].nodeName.toLowerCase()){a=!1;break}a||this.sidebar.classList.add("o
pened");this.find_pages();if(0!=this.pages.length){disable_dragstart(document.getElementsByClassName(CSS_CLASS_NAMES.bac
kground_image));this.config.key_handler&&this.register_key_handler();var h=this;this.config.hashchange_handler&&window.a
ddEventListener("hashchange",
>> function(a){h.navigate_to_dest(document.location.hash.substring(1))},!1);this.config.view_history_handler&&window.add
EventListener("popstate",function(a){a.state&&h.navigate_to_dest(a.state)},!1);this.container.addEventListener("scroll",
function(){h.update_page_idx();h.schedule_render(!0)},!1);[this.container,this.outline].forEach(function(a){a.addEventLi
stener("click",h.link_handler.bind(h),!1)});this.initialize_radio_button();this.render()}},find_pages:function(){for(var
 a=[],b={},c=this.container.childNodes,
>> e=0,h=c.length;e<h;++e){var d=c[e];d.nodeType===Node.ELEMENT_NODE&&d.classList.contains(CSS_CLASS_NAMES.page_frame)&&
(d=new Page(d),a.push(d),b[d.num]=a.length-1)}this.pages=a;this.page_map=b},load_page:function(a,b,c){var e=this.pages;i
f(!(a>=e.length||(e=e[a],e.loaded||this.pages_loading[a]))){var e=e.page,h=e.getAttribute("data-page-url");if(h){this.pa
ges_loading[a]=!0;var d=e.getElementsByClassName(this.config.loading_indicator_cls)[0];"undefined"===typeof d&&(d=this.l
oading_indicator.cloneNode(!0),
>> d.classList.add("active"),e.appendChild(d));var f=this,g=new XMLHttpRequest;g.open("GET",h,!0);g.onload=function(){if
(200===g.status||0===g.status){var b=document.createElement("div");b.innerHTML=g.responseText;for(var d=null,b=b.childNo
des,e=0,h=b.length;e<h;++e){var p=b[e];if(p.nodeType===Node.ELEMENT_NODE&&p.classList.contains(CSS_CLASS_NAMES.page_fram
e)){d=p;break}}b=f.pages[a];f.container.replaceChild(d,b.page);b=new Page(d);f.pages[a]=b;b.hide();b.rescale(f.scale);di
sable_dragstart(d.getElementsByClassName(CSS_CLASS_NAMES.background_image));
>> f.schedule_render(!1);c&&c(b)}delete f.pages_loading[a]};g.send(null)}void 0===b&&(b=this.config.preload_pages);0<--b
&&(f=this,setTimeout(function(){f.load_page(a+1,b)},0))}},pre_hide_pages:function(){var a="@media screen{."+CSS_CLASS_NA
MES.page_content_box+"{display:none;}}",b=document.createElement("style");b.styleSheet?b.styleSheet.cssText=a:b.appendCh
ild(document.createTextNode(a));document.head.appendChild(b)},render:function(){for(var a=this.container,b=a.scrollTop,c
=a.clientHeight,a=b-c,b=
>> b+c+c,c=this.pages,e=0,h=c.length;e<h;++e){var d=c[e],f=d.page,g=f.offsetTop+f.clientTop,f=g+f.clientHeight;g<=b&&f>=
a?d.loaded?d.show():this.load_page(e):d.hide()}},update_page_idx:function(){var a=this.pages,b=a.length;if(!(2>b)){for(v
ar c=this.container,e=c.scrollTop,c=e+c.clientHeight,h=-1,d=b,f=d-h;1<f;){var g=h+Math.floor(f/2),f=a[g].page;f.offsetTo
p+f.clientTop+f.clientHeight>=e?d=g:h=g;f=d-h}this.first_page_idx=d;for(var g=h=this.cur_page_idx,k=0;d<b;++d){var f=a[d
].page,l=f.offsetTop+f.clientTop,
>> f=f.clientHeight;if(l>c)break;f=(Math.min(c,l+f)-Math.max(e,l))/f;if(d===h&&Math.abs(f-1)<=EPS){g=h;break}f>k&&(k=f,g
=d)}this.cur_page_idx=g}},schedule_render:function(a){if(void 0!==this.render_timer){if(!a)return;clearTimeout(this.rend
er_timer)}var b=this;this.render_timer=setTimeout(function(){delete b.render_timer;b.render()},this.config.render_timeou
t)},register_key_handler:function(){var a=this;window.addEventListener("DOMMouseScroll",function(b){if(b.ctrlKey){b.prev
entDefault();var c=a.container,
>> e=c.getBoundingClientRect(),c=[b.clientX-e.left-c.clientLeft,b.clientY-e.top-c.clientTop];a.rescale(Math.pow(a.config
.scale_step,b.detail),!0,c)}},!1);window.addEventListener("keydown",function(b){var c=!1,e=b.ctrlKey||b.metaKey,h=b.altK
ey;switch(b.keyCode){case 61:case 107:case 187:e&&(a.rescale(1/a.config.scale_step,!0),c=!0);break;case 173:case 109:cas
e 189:e&&(a.rescale(a.config.scale_step,!0),c=!0);break;case 48:e&&(a.rescale(0,!1),c=!0);break;case 33:h?a.scroll_to(a.
cur_page_idx-1):a.container.scrollTop-=
>> a.container.clientHeight;c=!0;break;case 34:h?a.scroll_to(a.cur_page_idx+1):a.container.scrollTop+=a.container.client
Height;c=!0;break;case 35:a.container.scrollTop=a.container.scrollHeight;c=!0;break;case 36:a.container.scrollTop=0,c=!0
}c&&b.preventDefault()},!1)},rescale:function(a,b,c){var e=this.scale;this.scale=a=0===a?1:b?e*a:a;c||(c=[0,0]);b=this.c
ontainer;c[0]+=b.scrollLeft;c[1]+=b.scrollTop;for(var h=this.pages,d=h.length,f=this.first_page_idx;f<d;++f){var g=h[f].
page;if(g.offsetTop+g.clientTop>=
>> c[1])break}g=f-1;0>g&&(g=0);var g=h[g].page,k=g.clientWidth,f=g.clientHeight,l=g.offsetLeft+g.clientLeft,m=c[0]-l;0>m
?m=0:m>k&&(m=k);k=g.offsetTop+g.clientTop;c=c[1]-k;0>c?c=0:c>f&&(c=f);for(f=0;f<d;++f)h[f].rescale(a);b.scrollLeft+=m/e*
a+g.offsetLeft+g.clientLeft-m-l;b.scrollTop+=c/e*a+g.offsetTop+g.clientTop-c-k;this.schedule_render(!0)},fit_width:funct
ion(){var a=this.cur_page_idx;this.rescale(this.container.clientWidth/this.pages[a].width(),!0);this.scroll_to(a)},fit_h
eight:function(){var a=this.cur_page_idx;
>> this.rescale(this.container.clientHeight/this.pages[a].height(),!0);this.scroll_to(a)},get_containing_page:function(a
){for(;a;){if(a.nodeType===Node.ELEMENT_NODE&&a.classList.contains(CSS_CLASS_NAMES.page_frame)){a=get_page_number(a);var
 b=this.page_map;return a in b?this.pages[b[a]]:null}a=a.parentNode}return null},link_handler:function(a){var b=a.target
,c=b.getAttribute("data-dest-detail");if(c){if(this.config.view_history_handler)try{var e=this.get_current_view_hash();w
indow.history.replaceState(e,
>> "","#"+e);window.history.pushState(c,"","#"+c)}catch(h){}this.navigate_to_dest(c,this.get_containing_page(b));a.preve
ntDefault()}},navigate_to_dest:function(a,b){try{var c=JSON.parse(a)}catch(e){return}if(c instanceof Array){var h=c[0],d
=this.page_map;if(h in d){for(var f=d[h],h=this.pages[f],d=2,g=c.length;d<g;++d){var k=c[d];if(null!==k&&"number"!==type
of k)return}for(;6>c.length;)c.push(null);var g=b||this.pages[this.cur_page_idx],d=g.view_position(),d=transform(g.ictm,
[d[0],g.height()-d[1]]),
>> g=this.scale,l=[0,0],m=!0,k=!1,n=this.scale;switch(c[1]){case "XYZ":l=[null===c[2]?d[0]:c[2]*n,null===c[3]?d[1]:c[3]*
n];g=c[4];if(null===g||0===g)g=this.scale;k=!0;break;case "Fit":case "FitB":l=[0,0];k=!0;break;case "FitH":case "FitBH":
l=[0,null===c[2]?d[1]:c[2]*n];k=!0;break;case "FitV":case "FitBV":l=[null===c[2]?d[0]:c[2]*n,0];k=!0;break;case "FitR":l
=[c[2]*n,c[5]*n],m=!1,k=!0}if(k){this.rescale(g,!1);var p=this,c=function(a){l=transform(a.ctm,l);m&&(l[1]=a.height()-l[
1]);p.scroll_to(f,l)};h.loaded?
>> c(h):(this.load_page(f,void 0,c),this.scroll_to(f))}}}},scroll_to:function(a,b){var c=this.pages;if(!(0>a||a>=c.lengt
h)){c=c[a].view_position();void 0===b&&(b=[0,0]);var e=this.container;e.scrollLeft+=b[0]-c[0];e.scrollTop+=b[1]-c[1]}},g
et_current_view_hash:function(){var a=[],b=this.pages[this.cur_page_idx];a.push(b.num);a.push("XYZ");var c=b.view_positi
on(),c=transform(b.ictm,[c[0],b.height()-c[1]]);a.push(c[0]/this.scale);a.push(c[1]/this.scale);a.push(this.scale);retur
n JSON.stringify(a)}};
>> pdf2htmlEX.Viewer=Viewer;})();
>> </script><script>
>> try{
>> pdf2htmlEX.defaultViewer = new pdf2htmlEX.Viewer({});
>> }catch(e){}
>> </script>
>>     <title></title>
>> </head>
>> <body>
>> <div id="sidebar">
>> <div id="outline">
>> <ul>
>>     <li><a class="l" data-dest-detail="[1,&quot;XYZ&quot;,0,840.96,null]" href="#pf1">Local Disk</a>
>>     <ul>
>>         <li><a class="l" data-dest-detail="[1,&quot;XYZ&quot;,54,151,null]" href="#pf1">Settings</a></li>
>>         <li><a class="l" data-dest-detail="[2,&quot;XYZ&quot;,24,528,null]" href="#pf2">Documents</a></li>
>>     </ul>
>>     </li>
>> </ul>
>> </div>
>> </div>
>>
>> <div id="page-container">
>> <div class="pf w0 h0" data-page-no="1" id="pf1">
>> <div class="pc pc1 w0 h0"><img alt="" class="bi x0 y0 w1 h1" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAABF4AA
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
1ZVq9WiUup6e2Aw72qk+sVfKhazz35uy+aND6zqW7048vob//PLV375+3fe/MTslogoZqVCsbueGsV68cbERmtdLQAASKOWked5zBVKqasUXZd8qdhZWN2/4
e47PnNhZObs7LHfnqjXm8tj8I9nKKRCR9yY36TaWlcLAADSqGV84xv/7yfYqXsAACAASURBVMoPvv/++++//35XCwAA7aZgCgAAAKQRAACANAIAAJBGAAAA0
ggAAEAaAQAASCMAAABpBAAAII0AAACkEQAAgDQCAACQRgAAANIIAABAGgEAAEgjAAAAaQQAACCNAAAApBEAAIA0AgAAkEYAAADSCAAAQBoBAABIIwAAgA9Wu
rVv74UXXnC1AADA/ylLKZkFAACgzXmhDgAA4FZ/oe6mlWXvXDKS0grTAgAAS/YjuhfqAAAAvFAHAAAgjQAAAKQRAACANAIAAJBGAAAA0ggAAEAaAQAASCMAA
ABpBAAAII0AAACkEQAAgDQCAACQRgAAANIIAABAGgEAAEgjAAAAaQQAACCNAAAApBEAAIA0AgAAkEYAAADSCAAAQBoBAABIIwAAAGkEAAAgjQAAAKQRAACAN
AIAAJBGAAAA0ggAAEAaAQAASCMAAABpBAAAII0AAACkEQAAgDQCAACQRgAAANIIAABAGt141Wq10WiYBwAAkEbtqNFofPe7382y7I477ujo6Ni8efP09LRpA
QCAFpKllMzCVRoZGdm/f3+5XH7ooYciYv/+/RExNTW1adMmkwMAANKoLUxMTAwNDQ0PD//0pz8tlUoRMT09vX79+nK5fPz48cURAADgJueFuqt14MCBiNi3b
9+FClq3bt3evXsrlcqJEyfMDwAASKO2UK1WF3Po4sHbb789IiYnJ80PAABIo7YwODgYEZfsu3D06NGI2Lp1q/kBAICW4LNGV+vVV1+97777hoeHDx482NPTE
3/49JHPGgEAgDRqL0899dSePXsiYufOndVqdXx8POxQBwAA0qgN/eQnP/nGN74xNTUVEbt37/7mN7+5+KIdAAAgjQAAAFqDbRgAAACkEQAAgDQCAACQRgAAA
NIIAABAGgEAAEgjAAAAaQQAACCNAAAApBEAAIA0AgAAkEYAAADSCAAAQBoBAABIIwAAAGkEAAAgja6n2dnZRqNhHgAAQBq1qbGxsVWrVvX29nZ0dGzevHl6e
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" />
>> <div class="c x0 y1 w2 h2">
>> <div class="t m0 x1 h3 y2 ff1 fs0 fc0 sc0 ls0 ws0">&nbsp;</div>
>>
>> <div class="t m0 x2 h3 y3 ff1 fs0 fc0 sc0 ls0 ws0">Property X Melbourne</div>
>>
>> <div class="t m0 x3 h3 y4 ff1 fs0 fc0 sc0 ls0 ws0">Settings</div>
>>
>> <div class="t m0 x3 h3 y5 ff1 fs0 fc0 sc0 ls0 ws0">Property X Collingwood</div>
>>
>> <div class="t m0 x3 h3 y6 ff1 fs0 fc0 sc0 ls0 ws0">Demo Portfolio</div>
>>
>> <div class="t m0 x3 h3 y7 ff1 fs0 fc0 sc0 ls0 ws0">My Clients</div>
>>
>> <div class="t m0 x4 h3 y8 ff1 fs0 fc0 sc0 ls0 ws0">&nbsp;</div>
>>
>> <div class="t m0 x5 h3 y9 ff1 fs0 fc1 sc0 ls0 ws0">Carly Ewing</div>
>>
>> <div class="t m0 x5 h3 ya ff1 fs0 fc0 sc0 ls0 ws0">Your Profile</div>
>>
>> <div class="t m0 x5 h3 yb ff1 fs0 fc0 sc0 ls0 ws0">Notifications</div>
>>
>> <div class="t m0 x5 h3 yc ff1 fs0 fc0 sc0 ls0 ws0">Sign Out</div>
>> </div>
>>
>> <div class="c x6 yd w3 h4">
>> <div class="t m0 x7 h5 ye ff2 fs1 fc2 sc0 ls0 ws0">Search...</div>
>> </div>
>>
>> <div class="c x0 y1 w2 h2">
>> <div class="t m0 x5 h3 yf ff1 fs0 fc1 sc0 ls0 ws0">Alerts <span class="fs1">(from batched actions)</span> <span class
="fs1">0 new</span></div>
>>
>> <div class="t m0 x5 h3 y10 ff1 fs0 fc1 sc0 ls0 ws0">No new alerts</div>
>>
>> <div class="t m0 x5 h3 y11 ff1 fs0 fc0 sc0 ls0 ws0">Clear</div>
>>
>> <div class="t m0 x5 h3 y12 ff1 fs0 fc1 sc0 ls0 ws0">Notifications</div>
>>
>> <div class="t m0 x5 h3 y13 ff1 fs0 fc0 sc0 ls0 ws0">View All Notifications</div>
>>
>> <div class="t m0 x8 h3 y14 ff1 fs0 fc1 sc0 ls0 ws0">Connection lost</div>
>>
>> <div class="t m0 x8 h3 y15 ff1 fs0 fc0 sc0 ls0 ws0">Reconnect</div>
>>
>> <div class="t m0 x5 h3 y16 ff1 fs0 fc0 sc0 ls0 ws0">Invite</div>
>>
>> <div class="t m0 x5 h3 y17 ff1 fs0 fc0 sc0 ls0 ws0">Support list</div>
>>
>> <div class="t m0 x5 h3 y18 ff1 fs0 fc0 sc0 ls0 ws0">Migrate list</div>
>>
>> <div class="t m0 x5 h3 y19 ff1 fs0 fc0 sc0 ls0 ws0">Data transfer list</div>
>>
>> <div class="t m0 x5 h3 y1a ff1 fs0 fc0 sc0 ls0 ws0">Portfolios</div>
>>
>> <div class="t m0 x5 h3 y1b ff1 fs0 fc0 sc0 ls0 ws0">SetupMe</div>
>>
>> <div class="t m0 x5 h3 y1c ff1 fs0 fc0 sc0 ls0 ws0">Partners</div>
>>
>> <div class="t m0 x5 h3 y1d ff1 fs0 fc0 sc0 ls0 ws0">Administration</div>
>>
>> <div class="t m0 x2 h6 y1e ff3 fs0 fc1 sc0 ls0 ws0">Settings</div>
>>
>> <div class="t m0 x9 h5 y1f ff2 fs1 fc1 sc0 ls0 ws0">Dashboard</div>
>>
>> <div class="t m0 x2 h3 y20 ff1 fs0 fc1 sc0 ls0 ws0">Portfolio</div>
>>
>> <div class="t m0 x5 h3 y21 ff1 fs0 fc0 sc0 ls0 ws0">Company</div>
>>
>> <div class="t m0 x5 h3 y22 ff1 fs0 fc0 sc0 ls0 ws0">Banking</div>
>>
>> <div class="t m0 x5 h3 y23 ff1 fs0 fc0 sc0 ls0 ws0">Fees</div>
>>
>> <div class="t m0 x5 h3 y24 ff1 fs0 fc0 sc0 ls0 ws0">Labels</div>
>>
>> <div class="t m0 x5 h3 y25 ff1 fs0 fc0 sc0 ls0 ws0">Chart of Accounts</div>
>> </div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:24.003000px;bottom:784.693000px;width:73.533000px;h
eight:32.264000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:97.536000px;bottom:784.693000px;width:27.012000px;h
eight:14.256000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:54.016000px;bottom:759.181000px;width:108.799000px;
height:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:61.519000px;bottom:743.424000px;width:39.018000px;h
eight:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:61.519000px;bottom:716.412000px;width:118.553000px;
height:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:61.519000px;bottom:702.906000px;width:75.034000px;h
eight:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:61.519000px;bottom:675.894000px;width:54.025000px;h
eight:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:54.016000px;bottom:612.866000px;width:516.981000px;
height:29.263000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:559.592000px;width:59.276000px;h
eight:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:532.580000px;width:63.028000px;h
eight:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:505.568000px;width:42.769000px;h
eight:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:411.776000px;width:26.261000px;h
eight:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:371.258000px;width:109.549000px;
height:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:24.003000px;bottom:320.235000px;width:51.023000px;h
eight:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:274.465000px;width:27.762000px;h
eight:12.755000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:260.959000px;width:55.524000px;h
eight:12.755000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:247.453000px;width:55.524000px;h
eight:12.755000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:233.947000px;width:80.285000px;h
eight:12.755000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:220.441000px;width:47.271000px;h
eight:12.755000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:206.934000px;width:43.519000px;h
eight:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:193.428000px;width:39.017000px;h
eight:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:166.416000px;width:72.782000px;h
eight:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:77.877000px;width:46.520000px;he
ight:12.756000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:64.371000px;width:40.518000px;he
ight:12.755000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:50.865000px;width:21.759000px;he
ight:12.755000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:37.359000px;width:32.264000px;he
ight:12.755000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>>
>> <div class="d m1" style="border-style:none;position:absolute;left:84.030000px;bottom:23.853000px;width:87.789000px;he
ight:12.755000px;background-color:rgba(255,255,255,0.000001);">&nbsp;</div>
>> </div>
>>
>> <div class="pi" data-data="{&quot;ctm&quot;:[1.000000,0.000000,0.000000,1.000000,0.000000,0.000000]}">&nbsp;</div>
>> </div>
>> </div>
>>
>> <div class="loading-indicator"><img alt="" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAA
ABGdBTUEAALGPC/xhBQAAAwBQTFRFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAQAAAwAACAEBDAIDFgQFHwUIKggLMggPOgsQ/w1x/Q5v/w5w9w9ryhBT+xBsWhAbuhFKUhEXUhEXrhJEuxJKwBJN1xJY8hJn/xJ
syhNRoxM+shNF8BNkZxMfXBMZ2xRZlxQ34BRb8BRk3hVarBVA7RZh8RZi4RZa/xZqkRcw9Rdjihgsqxg99BhibBkc5hla9xli9BlgaRoapho55xpZ/hpm8xp
fchsd+Rtibxsc9htgexwichwdehwh/hxk9Rxedx0fhh4igB4idx4eeR4fhR8kfR8g/h9h9R9bdSAb9iBb7yFX/yJfpCMwgyQf8iVW/iVd+iVZ9iVWoCYsmyc
jhice/ihb/Sla+ylX/SpYmisl/StYjisfkiwg/ixX7CxN9yxS/S1W/i1W6y1M9y1Q7S5M6S5K+i5S6C9I/i9U+jBQ7jFK/jFStTIo+DJO9zNM7TRH+DRM/jR
Q8jVJ/jZO8DhF9DhH9jlH+TlI/jpL8jpE8zpF8jtD9DxE7zw9/z1I9j1A9D5C+D5D4D8ywD8nwD8n90A/8kA8/0BGxEApv0El7kM5+ENA+UNAykMp7kQ1+0R
B+EQ+7EQ2/0VCxUUl6kU0zkUp9UY8/kZByUkj1Eoo6Usw9Uw3300p500t3U8p91Ez11Ij4VIo81Mv+FMz+VM0/FM19FQw/lQ19VYv/lU1/1cz7Fgo/1gy8Fk
p9lor4loi/1sw8l0o9l4o/l4t6l8i8mAl+WEn8mEk52Id9WMk9GMk/mMp+GUj72Qg8mQh92Uj/mUn+GYi7WYd+GYj6mYc62cb92ch8Gce7mcd6Wcb6mcb+mg
i/mgl/Gsg+2sg+Wog/moj/msi/mwh/m0g/m8f/nEd/3Ic/3Mb/3Qb/3Ua/3Ya/3YZ/3cZ/3cY/3gY/0VC/0NE/0JE/w5wl4XsJQAAAPx0Uk5TAAAAAAAAAAA
AAAAAAAAAAAABCQsNDxMWGRwhJioyOkBLT1VTUP77/vK99zRpPkVmsbbB7f5nYabkJy5kX8HeXaG/11H+W89Xn8JqTMuQcplC/op1x2GZhV2I/IV+HFRXgVS
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" /></div>
>> </body>
>> </html>
>> ^C
PS C:\WINDOWS\system32> @font-face{font-family:ff1;src:url('data:application/font-woff;base64,d09GRgABAAAAAJXoABAAAAAA3d
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
>>     <style type="text/css">.ff0{font-family:sans-serif;visibility:hidden;}
>>     </style>
>>  */@keyframes fadein{from{opacity:0}to{opacity:1}}@-webkit-keyframes fadein{from{opacity:0}to{opacity:1}}@keyframes s
wing{0{transform:rotate(0)}10%{transform:rotate(0)}90%{transform:rotate(720deg)}100%{transform:rotate(720deg)}}@-webkit-
keyframes swing{0{-webkit-transform:rotate(0)}10%{-webkit-transform:rotate(0)}90%{-webkit-transform:rotate(720deg)}100%{
-webkit-transform:rotate(720deg)}}@media screen{#sidebar{background-color:#2f3236;background-image:url("data:image/svg+x
ml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI0IiBoZWlnaHQ9IjQiPgo8cmVjdCB3aWR0aD0iNCIgaGVpZ2
h0PSI0IiBmaWxsPSIjNDAzYzNmIj48L3JlY3Q+CjxwYXRoIGQ9Ik0wIDBMNCA0Wk00IDBMMCA0WiIgc3Ryb2tlLXdpZHRoPSIxIiBzdHJva2U9IiMxZTI5Mm
QiPjwvcGF0aD4KPC9zdmc+")}#outline{font-family:Georgia,Times,"Times New Roman",serif;font-size:13px;margin:2em 1em}#outli
ne ul{padding:0}#outline li{list-style-type:none;margin:1em 0}#outline li>ul{margin-left:1em}#outline a,#outline a:visit
ed,#outline a:hover,#outline a:active{line-height:1.2;color:#e8e8e8;text-overflow:ellipsis;white-space:nowrap;text-decor
ation:none;display:block;overflow:hidden;outline:0}#outline a:hover{color:#0cf}#page-container{background-color:#9e9e9e;
background-image:url("data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI1IiBoZWln
aHQ9IjUiPgo8cmVjdCB3aWR0aD0iNSIgaGVpZ2h0PSI1IiBmaWxsPSIjOWU5ZTllIj48L3JlY3Q+CjxwYXRoIGQ9Ik0wIDVMNSAwWk02IDRMNCA2Wk0tMSAx
TDEgLTFaIiBzdHJva2U9IiM4ODgiIHN0cm9rZS13aWR0aD0iMSI+PC9wYXRoPgo8L3N2Zz4=");-webkit-transition:left 500ms;transition:left
 500ms}.pf{margin:13px auto;box-shadow:1px 1px 3px 1px #333;border-collapse:separate}.pc.opened{-webkit-animation:fadein
 100ms;animation:fadein 100ms}.loading-indicator.active{-webkit-animation:swing 1.5s ease-in-out .01s infinite alternate
 none;animation:swing 1.5s ease-in-out .01s infinite alternate none}.checked{background:no-repeat url(data:image/png;bas
e64,iVBORw0KGgoAAAANSUhEUgAAABYAAAAWCAYAAADEtGw7AAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAB3RJTUUH3goQDSYg
DiGofgAAAslJREFUOMvtlM9LFGEYx7/vvOPM6ywuuyPFihWFBUsdNnA6KLIh+QPx4KWExULdHQ/9A9EfUodYmATDYg/iRewQzklFWxcEBcGgEplDkDtI6sw4
PzrIbrOuedBb9MALD7zv+3m+z4/3Bf7bZS2bzQIAcrmcMDExcTeXy10DAFVVAQDksgFUVZ1ljD3yfd+0LOuFpmnvVVW9GHhkZAQcxwkNDQ2FSCQyRMgJxnVd
y7KstKZpn7nwha6urqqfTqfPBAJAuVymlNLXoigOhfd5nmeiKL5TVTV+lmIKwAOA7u5u6Lped2BsbOwjY6yf4zgQQkAIAcedaPR9H67r3uYBQFEUFItFtLe3
32lpaVkUBOHK3t5eRtf1DwAwODiIubk5DA8PM8bYW1EU+wEgCIJqsCAIQAiB7/u253k2BQDDMJBKpa4mEon5eDx+UxAESJL0uK2t7XosFlvSdf0QAEmlUnlR
FJ9Waho2Qghc1/U9z3uWz+eX+Wr+lL6SZfleEAQIggA8z6OpqSknimIvYyybSCReMsZ6TislhCAIAti2Dc/zejVNWwCAavN8339j27YbTg0AGGM3WltbP4Wh
lRWq6Q/btrs1TVsYHx+vNgqKoqBUKn2NRqPFxsbGJzzP05puUlpt0ukyOI6z7zjOwNTU1OLo6CgmJyf/gA3DgKIoWF1d/cIY24/FYgOU0pp0z/Ityzo8Pj5O
Tk9PbwHA+vp6zWghDC+VSiuRSOQgGo32UErJ38CO42wdHR09LBQK3zKZDDY2NupmFmF4R0cHVlZWlmRZ/iVJUn9FeWWcCCE4ODjYtG27Z2Zm5juAOmgdGAB2
d3cBADs7O8uSJN2SZfl+WKlpmpumaT6Yn58vn/fs6XmbhmHMNjc3tzDGFI7jYJrm5vb29sDa2trPC/9aiqJUy5pOp4f6+vqeJ5PJBAB0dnZe/t8NBajx/z37
Df5OGX8d13xzAAAAAElFTkSuQmCC)}}Yn58vn/fs6XmbhmHMNjc3tzDGFI7jYJrm5vb29sDa2trPC/9aiqJUy5pOp4f6+vqeJ5PJBAB0dnZe/t8NBajx/z37
>>  * https://github.com/coolwanglu/pdf2htmlEX/blob/master/share/LICENSEng:0;margin:0;overflow:auto}#page-container{posi
>>  * Copyright 2012,2013 Lu Wang <coolwanglu@gmail.com> r/share/LICENSEng:0;margin:0;overflow:auto}#page-container{posi
>>  * Fancy styles for pdf2htmlEX <coolwanglu@gmail.com> dth:250px;padding:0;margin:0;overflow:auto}#page-container{posi
>>     <style type="text/css">/*! op:0;left:0;bottom:0;width:250px;padding:0;margin:0;overflow:auto}#page-container{posi
>>     </style>ype="text/css">/*! op:0;left:0;bottom:0;width:250px;padding:0;margin:0;overflow:auto}#page-container{posi
>>  */#sidebar{position:absolute;top:0;left:0;bottom:0;width:250px;padding:0;margin:0;overflow:auto}#page-container{posi
tion:absolute;top:0;left:0;margin:0;padding:0;border:0}@media screen{#sidebar.opened+#page-container{left:250px}#page-co
ntainer{bottom:0;right:0;overflow:auto}.loading-indicator{display:none}.loading-indicator.active{display:block;position:
absolute;width:64px;height:64px;top:50%;left:50%;margin-top:-32px;margin-left:-32px}.loading-indicator img{position:abso
lute;top:0;left:0;bottom:0;right:0}}@media print{@page{margin:0}html{margin:0}body{margin:0;-webkit-print-color-adjust:e
xact}#sidebar{display:none}#page-container{width:auto;height:auto;overflow:visible;background-color:transparent}.d{displ
ay:none}}.pf{position:relative;background-color:white;overflow:hidden;margin:0;border:0}.pc{position:absolute;border:0;p
adding:0;margin:0;top:0;left:0;width:100%;height:100%;overflow:hidden;display:block;transform-origin:0 0;-ms-transform-o
rigin:0 0;-webkit-transform-origin:0 0}.pc.opened{display:block}.bf{position:absolute;border:0;margin:0;top:0;bottom:0;w
idth:100%;height:100%;-ms-user-select:none;-moz-user-select:none;-webkit-user-select:none;user-select:none}.bi{position:
absolute;border:0;margin:0;-ms-user-select:none;-moz-user-select:none;-webkit-user-select:none;user-select:none}@media p
rint{.pf{margin:0;box-shadow:none;page-break-after:always;page-break-inside:avoid}@-moz-document url-prefix(){.pf{overfl
ow:visible;border:1px solid #fff}.pc{overflow:visible}}}.c{position:absolute;border:0;padding:0;margin:0;overflow:hidden
;display:block}.t{position:absolute;white-space:pre;font-size:1px;transform-origin:0 100%;-ms-transform-origin:0 100%;-w
ebkit-transform-origin:0 100%;unicode-bidi:bidi-override;-moz-font-feature-settings:"liga" 0}.t:after{content:''}.t:befo
re{content:'';display:inline-block}.t span{position:relative;unicode-bidi:bidi-override}._{display:inline-block;color:tr
ansparent;z-index:-1}::selection{background:rgba(127,255,255,0.4)}::-moz-selection{background:rgba(127,255,255,0.4)}.pi{
display:none}.d{position:absolute;transform-origin:0 100%;-ms-transform-origin:0 100%;-webkit-transform-origin:0 100%}.i
t{border:0;background-color:rgba(255,255,255,0.0)}.ir:hover{cursor:pointer}lection{background:rgba(127,255,255,0.4)}.pi{
>>  * https://github.com/coolwanglu/pdf2htmlEX/blob/master/share/LICENSEorigin:0 100%;-webkit-transform-origin:0 100%}.i
>>  * Copyright 2012,2013 Lu Wang <coolwanglu@gmail.com> er{cursor:pointer}
>>  * Base CSS for pdf2htmlEXwanglu/pdf2htmlEX/blob/master/share/LICENSE
>>     <style type="text/css">/*! <coolwanglu@gmail.com> Compatible" />
>>     <meta content="IE=edge,chrome=1" http-equiv="X-UA-Compatible" />
>>     <meta content="pdf2htmlEX" name="generator" />
>>     <meta charset="utf-8" />hrome=1" http-equiv="X-UA-Compatible" />
>> <head>eta content="pdf2htmlEX" name="generator" />
>> <html xmlns="http://www.w3.org/1999/xhtml">
>> <!DOCTYPE html>
