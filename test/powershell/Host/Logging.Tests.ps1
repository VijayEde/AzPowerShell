using namespace System.Text

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module PSSysLog

<#
    Define enums that mirror the internal enums used
    in product code. These are used to configure
    syslog logging.
#>
enum LogLevel
{
    LogAlways = 0x0
    Critical = 0x1
    Error = 0x2
    Warning = 0x3
    Informational = 0x4
    Verbose = 0x5
    Debug = 0x14
}

enum LogChannel
{
    Operational = 0x10
    Analytic = 0x11
}

enum LogKeyword
{
    Runspace = 0x1
    Pipeline = 0x2
    Protocol = 0x4
    Transport = 0x8
    Host = 0x10
    Cmdlets = 0x20
    Serializer = 0x40
    Session = 0x80
    ManagedPlugin = 0x100
}

<#
.SYNOPSIS
   Creates a powershell.config.json file with syslog settings

.PARAMETER logId
    The identifier to use for logging

.PARAMETER logLevel
    The optional logging level, see the LogLevel enum

.PARAMETER logChannels
    The optional logging channels to enable; see the LogChannel enum

.PARAMETER logKeywords
    The optional keywords to enable ; see the LogKeyword enum
#>
function WriteLogSettings
{
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LogId,

        [System.Nullable[LogLevel]] $LogLevel = $null,

        [LogChannel[]] $LogChannels = $null,

        [LogKeyword[]] $LogKeywords = $null
    )

    [StringBuilder] $sb = [StringBuilder]::new()
    $filename = [Guid]::NewGuid().ToString('N')
    $fullPath = Join-Path -Path $TestDrive -ChildPath "$filename.config.json"

    $null = $sb.AppendLine('{')
    $null = $sb.AppendFormat('"LogIdentity": "{0}"', $LogId)

    [string] $channels = [string]::Empty
    if ($LogChannels -ne $null)
    {
        $channels = $LogChannels -join ', '
    }
    [string] $keywords = [string]::Empty
    if ($LogKeywords -ne $null)
    {
        $keywords = $LogKeywords -join ', '
    }

    if ($null -ne $LogLevel)
    {
        $null = $sb.AppendLine(',')
        $null = $sb.AppendFormat('"LogLevel": "{0}"', $LogLevel.ToString())
    }
    if ([string]::IsNullOrEmpty($channels) -eq $false)
    {
        $null = $sb.AppendLine(',')
        $null = $sb.AppendFormat('"LogChannels": "{0}"', $channels)
    }
    if ([string]::IsNullOrEmpty($keywords) -eq $false)
    {
        $null = $sb.AppendLine(',')
        $null = $sb.AppendFormat('"LogKeywords": "{0}"', $keywords)
    }

    $null = $sb.AppendLine()
    $null = $sb.AppendLine('}')

    $sb.ToString() | Set-Content -Path $fullPath -ErrorAction Stop
    return $fullPath
}

Describe 'Basic SysLog tests on Linux' -Tag @('CI','RequireSudoOnUnix') {
    BeforeAll {
        [bool] $IsSupportedEnvironment = $IsLinux
        [string] $SysLogFile = [string]::Empty

        if ($IsSupportedEnvironment)
        {
            if (Test-Path -Path '/var/log/syslog')
            {
                $SysLogFile = '/var/log/syslog'
            }
            elseif (Test-Path -Path '/var/log/messages')
            {
                $SysLogFile = '/var/log/messages'
            }
            else
            {
                # TODO: Look into journalctl and other variations.
                Write-Warning -Message 'Unsupported Linux syslog configuration.'
                $IsSupportedEnvironment = $false
            }
            [string] $powershell = Join-Path -Path $PSHome -ChildPath 'pwsh'
        }
    }

    BeforeEach {
        # generate a unique log application id
        [string] $logId = [Guid]::NewGuid().ToString('N')
    }

    It 'Verifies basic logging with no customizations' -Skip:(!$IsSupportedEnvironment) {
        $configFile = WriteLogSettings -LogId $logId
        & $powershell -NoProfile -SettingsFile $configFile -Command '$env:PSModulePath | out-null'

        # Get log entries from the last 100 that match our id and are after the time we launched Powershell
        $items = Get-PSSysLog -Path $SyslogFile -Id $logId -Tail 100 -Verbose -TotalCount 3

        $items | Should Not Be $null
        $items.Length | Should BeGreaterThan 1
        $items[0].EventId | Should Be 'Perftrack_ConsoleStartupStart:PowershellConsoleStartup.WinStart.Informational'
        $items[1].EventId | Should Be 'Perftrack_ConsoleStartupStop:PowershellConsoleStartup.WinStop.Informational'
        # if there are more items than expected...
        if ($items.Length -gt 2)
        {
            # Force reporting of the first unexpected item to help diagnosis
            $items[2] | Should be $null
        }
    }

    It 'Verifies logging level filtering works' -Skip:(!$IsSupportedEnvironment) {
        $configFile = WriteLogSettings -LogId $logId -LogLevel Warning
        & $powershell -NoProfile -SettingsFile $configFile -Command '$env:PSModulePath | out-null'

        # by default, only informational events are logged. With Level = Warning, nothing should
        # have been logged.
        $items = Get-PSSysLog -Path $SyslogFile -Id $logId -Tail 100 -TotalCount 1
        $items | Should Be $null
    }
}

Describe 'Basic os_log tests on MacOS' -Tag @('CI','RequireSudoOnUnix') {
    BeforeAll {
        [bool] $IsSupportedEnvironment = $IsMacOS
        [bool] $persistenceEnabled = $false

        if ($IsSupportedEnvironment)
        {
            # Check the current state.
            $persistenceEnabled  = (Get-OSLogPersistence).Enabled
            if (!$persistenceEnabled)
            {
                # enable powershell log persistence to support exporting log entries
                # for each test
                Write-Verbose -Message 'Enabling pwsh log persistence'
                Set-OsLogPersistence -Enable $true
            }
        }
        [string] $powershell = Join-Path -Path $PSHome -ChildPath 'pwsh'
    }

    BeforeEach {
        if ($IsSupportedEnvironment)
        {
            # generate a unique log application id
            [string] $logId = [Guid]::NewGuid().ToString('N')

            # Generate a working directory and content file for Export-OSLog
            [string] $workingDirectory = Join-Path -Path $TestDrive -ChildPath $logId
            $null = New-Item -Path $workingDirectory -ItemType Directory -ErrorAction Stop

            [string] $contentFile = Join-Path -Path $workingDirectory -ChildPath ('pwsh.log.txt')
            # get log items after current time.
            [DateTime] $after = [DateTime]::Now
        }
    }

    AfterAll {
        if ($IsSupportedEnvironment -and !$persistenceEnabled)
        {
            # disable persistence if it wasn't enabled
            Write-Verbose -Message 'Disabling pwsh log persistence'
            Set-OsLogPersistence -Enable $false
        }
    }

    It 'Verifies basic logging with no customizations' -Skip:(!$IsSupportedEnvironment) {
        $configFile = WriteLogSettings -LogId $logId
        & $powershell -NoProfile -SettingsFile $configFile -Command '$env:PSModulePath | out-null'

        Export-OsLog -WorkingDirectory $workingDirectory -After $after -Verbose | Set-Content -Path $contentFile
        $items = Get-PSOsLog -Path $contentFile -Id $logId -After $after -TotalCount 3 -Verbose

        $items | Should Not Be $null
        $items.Length | Should BeGreaterThan 1
        $items[0].EventId | Should Be 'Perftrack_ConsoleStartupStart:PowershellConsoleStartup.WinStart.Informational'
        $items[1].EventId | Should Be 'Perftrack_ConsoleStartupStop:PowershellConsoleStartup.WinStop.Informational'
        # if there are more items than expected...
        if ($items.Length -gt 2)
        {
            # Force reporting of the first unexpected item to help diagnosis
            $items[2] | Should be $null
        }
    }

    It 'Verifies logging level filtering works' -Skip:(!$IsSupportedEnvironment) {
        $configFile = WriteLogSettings -LogId $logId -LogLevel Warning
        & $powershell -NoProfile -SettingsFile $configFile -Command '$env:PSModulePath | out-null'

        Export-OsLog -WorkingDirectory $workingDirectory -After $after -Verbose | Set-Content -Path $contentFile
        # by default, powershell startup should only log informational events are logged.
        # With Level = Warning, nothing should
        $items = Get-PSOsLog -Path $contentFile -Id $logId -After $after -TotalCount 3
        $items | Should Be $null
    }
}
