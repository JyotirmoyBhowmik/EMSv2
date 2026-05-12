$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $here) -replace '\.Tests$', ''

Import-Module "$here\..\Disk.psm1" -Force

# Create dummy functions in the global scope so Pester can mock them in PowerShell Core on Linux
if (-not (Get-Command Get-WmiObject -ErrorAction SilentlyContinue)) {
    Set-Item -Path "Function:Global:Get-WmiObject" -Value { throw "Not Implemented" }
}
if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
    Set-Item -Path "Function:Global:Get-CimInstance" -Value { throw "Not Implemented" }
}

Describe "Invoke-DiskCollection" {
    BeforeAll {
        $Script:ScanId = [Guid]::NewGuid()
        $Script:ComputerName = "TEST-PC"
    }

    Context "Successful Collection (WMI)" {
        BeforeEach {
            Mock Get-WmiObject {
                return @(
                    [PSCustomObject]@{
                        DeviceID   = "C:"
                        VolumeName = "System"
                        Size       = 500GB
                        FreeSpace  = 200GB
                        FileSystem = "NTFS"
                    },
                    [PSCustomObject]@{
                        DeviceID   = "D:"
                        VolumeName = "Data"
                        Size       = 1000GB
                        FreeSpace  = 750GB
                        FileSystem = "NTFS"
                    }
                )
            } -ModuleName "Disk"
        }

        It "Returns success and metrics when WMI call succeeds" {
            $session = [PSCustomObject]@{ Protocol = "WMI" }
            $result = Invoke-DiskCollection -Session $session -ComputerName $Script:ComputerName -ScanId $Script:ScanId

            $result.Success | Should -Be $true
            $result.Metrics.Count | Should -Be 2

            # Metric 1: C: Drive
            $cDrive = $result.Metrics | Where-Object { $_.drive_letter -eq "C" }
            $cDrive.total_gb | Should -Be 500
            $cDrive.free_gb | Should -Be 200
            $cDrive.used_gb | Should -Be 300
            $cDrive.usage_percent | Should -Be 60
            $cDrive.is_system_drive | Should -Be $true
            $cDrive.volume_name | Should -Be "System"
            $cDrive.file_system | Should -Be "NTFS"

            # Metric 2: D: Drive
            $dDrive = $result.Metrics | Where-Object { $_.drive_letter -eq "D" }
            $dDrive.total_gb | Should -Be 1000
            $dDrive.free_gb | Should -Be 750
            $dDrive.used_gb | Should -Be 250
            $dDrive.usage_percent | Should -Be 25
            $dDrive.is_system_drive | Should -Be $false
            $dDrive.volume_name | Should -Be "Data"
            $dDrive.file_system | Should -Be "NTFS"
        }
    }

    Context "Successful Collection (CIM)" {
        BeforeEach {
            Mock Get-CimInstance {
                return @(
                    [PSCustomObject]@{
                        DeviceID   = "C:"
                        VolumeName = "System"
                        Size       = 200GB
                        FreeSpace  = 100GB
                        FileSystem = "NTFS"
                    }
                )
            } -ModuleName "Disk"
        }

        It "Returns success and metrics when CIM call succeeds" {
            $session = [PSCustomObject]@{ Protocol = "CIM"; Session = "DummySession" }
            $result = Invoke-DiskCollection -Session $session -ComputerName $Script:ComputerName -ScanId $Script:ScanId

            $result.Success | Should -Be $true
            $result.Metrics.Count | Should -Be 1

            $cDrive = $result.Metrics[0]
            $cDrive.total_gb | Should -Be 200
            $cDrive.free_gb | Should -Be 100
            $cDrive.used_gb | Should -Be 100
            $cDrive.usage_percent | Should -Be 50
            $cDrive.is_system_drive | Should -Be $true
        }
    }

    Context "Error Handling" {
        BeforeEach {
            Mock Get-WmiObject {
                throw "Access Denied"
            } -ModuleName "Disk"
        }

        It "Returns false and captures error when WMI call fails" {
            $session = [PSCustomObject]@{ Protocol = "WMI" }
            $result = Invoke-DiskCollection -Session $session -ComputerName $Script:ComputerName -ScanId $Script:ScanId

            $result.Success | Should -Be $false
            $result.Errors.Count | Should -Be 1
            $result.Errors[0] | Should -Match "\[Disk\] Access Denied"
            $result.Metrics.Count | Should -Be 0
        }
    }
}
