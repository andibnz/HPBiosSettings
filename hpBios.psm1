
<#
	Version 1.0

    .DESCRIPTION
        PS Module to provide a method of Getting & Configuring BIOS/UEFI settings for HP computers.
        n.b. only tested on HP Business Computers (Pro/Elite series)
        
    .USAGE
        Get-HPBiosSetting -Computername $HostName
        Set-HPBiosSetting -Computername $HostName -Property $Setting -Value $Value

    .NOTE
       The Property & Value variables ARE case sensitive.    
	
#>


function Get-HPBiosSetting {
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)][string[]]$Computername
    )
    Begin {
        $scriptStartTime = (Get-Date)
        Write-Verbose "Getting BIOS Settings from $Computername"
    }
    Process {
        foreach($node in $Computername) {
            if($(Test-Connection -ComputerName $node -Count 1 -ErrorAction SilentlyContinue)) {
                try {
                    $getBIOSSettings = Get-WmiObject -ComputerName $node -Namespace "root\hp\instrumentedBIOS" -Class hp_biosSetting -ErrorAction Stop | where { $_.Name -ne ' ' } | select PSComputerName,Name,Value,IsReadOnly #| Sort-Object name
                } catch [System.Runtime.InteropServices.ExternalException] {
                    $getBIOSMSG= "RPC service down"
                    $getBIOSFailed = $true
                } catch [UnauthorizedAccessException] {
                    $getBIOSMSG= "Access Denied"
                    $getBIOSFailed = $true   
                } catch [System.Management.ManagementException] {         
                    $getBIOSMSG= "Invalid class"
                    $getBIOSFailed = $true   
                } finally {
                    if($getBIOSFailed) {
                        Write-Warning $getBIOSMSG
                    } else {
                        Write-Output $getBIOSSettings
                    }
                }
            } else {
                Write-Warning "$node is down.."
            }
        }
    }
    End {
        $scriptEndTime = $([timespan]::fromseconds(((Get-Date)-$scriptStartTime).Totalseconds).ToString(“mm\:ss”))
        Write-Verbose "Completed in $scriptEndTime"
    }
}

function Set-HPBiosSetting {
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)][string[]]$Computername,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)][string[]]$Property,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)][string[]]$Value,
        [Parameter(Mandatory=$false,ValueFromPipeline=$false)][string]$Password,
        [Parameter(Mandatory=$false)][switch]$Reboot
    )
    Begin {
        $scriptStartTime = (Get-Date)
        Write-Verbose "Getting BIOS Settings from $Computername"
        if($Password) {
            $Password = "<utf-16/>"+$Password
            Write-Verbose $Password
        }
    }
    Process {
        foreach($node in $Computername) {
            $node = $node.ToUpper()
            $Completed = @()
            if($(Test-Connection -ComputerName $node -Count 1 -ErrorAction SilentlyContinue)) {
                try {
                    $setBiosSetting = Get-WmiObject -ComputerName $node -Namespace "root\hp\instrumentedbios" -Class HP_BiosSettingInterface 
                } catch [System.Runtime.InteropServices.ExternalException] {
                    $setBiosMSG = "RPC Service Down"
                    $setBiosFailed = $true
                } catch [UnauthorizedAccessException] {
                    $setBiosMSG = "Access Denied"
                    $setBiosFailed = $true   
                } catch [System.ArgumentException] {
                    $setBiosMSG = "Value does not fall within the expected range."
                    $setBiosFailed = $true
                } catch [System.Management.ManagementException] {         
                    $setBiosMSG = "Invalid Class: HP_BiosSettingInterface"
                    $setBiosFailed = $true   
                } finally {
                    if($setBiosFailed) {
                        Write-Warning "$node WMI error $setBiosMSG"
                    } else {
                        $cnt = -1
                        foreach($item in $Property) {
                            $cnt++
                            Write-Verbose "$node Property: `"$item`" Value: `"$($Value[$cnt])`""
                            $setResult = $setBiosSetting.SetBIOSSetting($item,$($Value[$cnt]),$Password) | Select-Object -ExpandProperty Return
                            switch($setResult) {
                                0 { Write-Output "[$node] Property: `"$item`" Value: `"$($Value[$cnt])`", Success!"; $Completed += $true }
                                1 { Write-Warning "$node Property: `"$item`" Value: `"$($Value[$cnt])`", Not Supported! Code: $setResult"; $Completed += $false }
                                2 { Write-Warning "$node Property: `"$item`" Value: `"$($Value[$cnt])`", Unspecified Error. Code: $setResult"; $Completed += $false }
                                3 { Write-Warning "$node Property: `"$item`" Value: `"$($Value[$cnt])`", Timeout. Code: $setResult"; $Completed += $false }
                                4 { Write-Warning "$node Property: `"$item`" Value: `"$($Value[$cnt])`", Failed. Code: $setResult"; $Completed += $false }
                                5 { Write-Warning "$node Property: `"$item`" Value: `"$($Value[$cnt])`", Invalid Parameter. Code: $setResult"; $Completed += $false }
                                6 { Write-Warning "$node Property: `"$item`" Value: `"$($Value[$cnt])`", Access Denied. Code: $setResult"; $Completed += $false }
                                default { Write-Warning "$node Property: `"$item`" Value: `"$($Value[$cnt])`", Unknown error, Code: $setResult"; $Completed += $false }
                            }
                        }
                        if($Reboot) {
                            if($Completed -notcontains $false) {
                                Write-Warning "$node Rebooting.."
                                Restart-Computer -ComputerName $node -Force
                            } else {
                                Write-Warning "$node 1 or more settings failed to complete! ABORTING REBOOT!"
                            }
                        }
                    }
                }
            } else {
                Write-Warning "$node is down.."
            }
        }
    }
    End {
        $scriptEndTime = $([timespan]::fromseconds(((Get-Date)-$scriptStartTime).Totalseconds).ToString(“mm\:ss”))
        Write-Verbose "Completed in $scriptEndTime"
    }
}