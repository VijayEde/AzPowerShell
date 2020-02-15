# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
Describe "Control Service cmdlet tests" -Tags "Feature","RequireAdminOnWindows" {
  BeforeAll {
    $originalDefaultParameterValues = $PSDefaultParameterValues.Clone()
    if ( -not $IsWindows ) {
        $PSDefaultParameterValues["it:skip"] = $true
    }
    if ($IsWindows) {
      $testservicename1 = "testrawservice1"
      $testservicename2 = "testrawservice2"
      $svcbinaryname    = "TestRawService"
      $svccmd = Get-Command $svcbinaryname
      $svccmd | Should -Not -BeNullOrEmpty
      $svcfullpath = $svccmd.Path
      $testservice1 = New-Service -BinaryPathName $svcfullpath -Name $testservicename1
      $testservice1 | Should -Not -BeNullOrEmpty
      $testservice2 = New-Service -BinaryPathName $svcfullpath -Name $testservicename2 -DependsOn $testservicename1
      $testservice2 | Should -Not -BeNullOrEmpty
    }
  }
  AfterAll {
    $global:PSDefaultParameterValues = $originalDefaultParameterValues
    if ($IsWindows) {
      Stop-Process -Name $svcbinaryname -Force
      Stop-Service $testservicename2
      Stop-Service $testservicename1
      Remove-Service $testservicename2
      Remove-Service $testservicename1
    }
  }

  It "Stop-Service fails" {
    Start-Service $testservicename2
    Stop-Service $testservicename1 -Force
  }

  It "StopServiceCommand can be used as API for '<parameter>' with '<value>'" -TestCases @(
    @{parameter="Force";value=$true},
    @{parameter="Force";value=$false},
    @{parameter="NoWait";value=$true},
    @{parameter="NoWait";value=$false}
  ) {
    param($parameter, $value)
    $stopservicecmd = [Microsoft.PowerShell.Commands.StopServiceCommand]::new()
    $stopservicecmd.$parameter = $value
    $stopservicecmd.$parameter | Should -Be $value
  }

  It "RestartServiceCommand can be used as API for '<parameter>' with '<value>'" -TestCases @(
    @{parameter="Force";value=$true},
    @{parameter="Force";value=$false}
  ) {
    param($parameter, $value)
    $restartservicecmd = [Microsoft.PowerShell.Commands.RestartServiceCommand]::new()
    $restartservicecmd.$parameter = $value
    $restartservicecmd.$parameter | Should -Be $value
  }

  It "Stop/Start/Restart-Service works" {
    $wasStopped = $false
    try {
      $spooler = Get-Service Spooler
      $spooler | Should -Not -BeNullOrEmpty
      if ($spooler.Status -ne "Running") {
        $wasStopped = $true
        $spooler = Start-Service Spooler -PassThru
      }
      $spooler.Status | Should -BeExactly "Running"
      $spooler = Stop-Service Spooler -PassThru
      $spooler.Status | Should -BeExactly "Stopped"
      (Get-Service Spooler).Status | Should -BeExactly "Stopped"
      $spooler = Start-Service Spooler -PassThru
      $spooler.Status | Should -BeExactly "Running"
      (Get-Service Spooler).Status | Should -BeExactly "Running"
      Stop-Service Spooler
      (Get-Service Spooler).Status | Should -BeExactly "Stopped"
      $spooler = Restart-Service Spooler -PassThru
      $spooler.Status | Should -BeExactly "Running"
      (Get-Service Spooler).Status | Should -BeExactly "Running"
    } finally {
      if ($wasStopped) {
        Stop-Service Spooler
      }
    }
  }

  It "Suspend/Resume-Service works" {
    try {
      $originalState = "Running"
      $serviceName = "WerSvc"
      $service = Get-Service $serviceName
      if ($service.Status -ne $originalState) {
        $originalState = $service.Status
        Start-Service $serviceName
      }
      $service | Should -Not -BeNullOrEmpty
      Suspend-Service $serviceName
      (Get-Service $serviceName).Status | Should -BeExactly "Paused"
      Resume-Service $serviceName
      (Get-Service $serviceName).Status | Should -BeExactly "Running"
    } finally {
      Set-Service $serviceName -Status $originalState
    }
  }

  It "Failure to control service with '<script>'" -TestCases @(
    @{script={Stop-Service dcomlaunch -ErrorAction Stop};errorid="ServiceHasDependentServices,Microsoft.PowerShell.Commands.StopServiceCommand"},
    @{script={Suspend-Service winrm -ErrorAction Stop};errorid="CouldNotSuspendServiceNotSupported,Microsoft.PowerShell.Commands.SuspendServiceCommand"},
    @{script={Resume-Service winrm -ErrorAction Stop};errorid="CouldNotResumeServiceNotSupported,Microsoft.PowerShell.Commands.ResumeServiceCommand"},
    @{script={Stop-Service $(new-guid) -ErrorAction Stop};errorid="NoServiceFoundForGivenName,Microsoft.PowerShell.Commands.StopServiceCommand"},
    @{script={Start-Service $(new-guid) -ErrorAction Stop};errorid="NoServiceFoundForGivenName,Microsoft.PowerShell.Commands.StartServiceCommand"},
    @{script={Resume-Service $(new-guid) -ErrorAction Stop};errorid="NoServiceFoundForGivenName,Microsoft.PowerShell.Commands.ResumeServiceCommand"},
    @{script={Suspend-Service $(new-guid) -ErrorAction Stop};errorid="NoServiceFoundForGivenName,Microsoft.PowerShell.Commands.SuspendServiceCommand"},
    @{script={Restart-Service $(new-guid) -ErrorAction Stop};errorid="NoServiceFoundForGivenName,Microsoft.PowerShell.Commands.RestartServiceCommand"}
  ) {
      param($script,$errorid)
      { & $script } | Should -Throw -ErrorId $errorid
  }

}
