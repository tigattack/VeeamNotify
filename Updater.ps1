# Pull version from script trigger
Param (
	[string]$LatestVersion
)

# Set variables
$projectPath = "$PSScriptRoot\VeeamNotify"

# Import functions
Import-Module "$projectPath\resources\Logger.psm1"

# Logging
## Set log file name
$date = (Get-Date -UFormat %Y-%m-%d_%T).Replace(':','.')
$logFile = "$PSScriptRoot\$($date)_Update.log"
## Start logging to file
Start-Logging $logFile

# Set error action preference.
Write-LogMessage -Tag 'INFO' -Message 'Set error action preference.'
$ErrorActionPreference = 'Stop'

# Notification function
function Update-Notification {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'Low'
	)]
	Param ()
	If ($PSCmdlet.ShouldProcess('Discord', 'Send update notification')) {
		Write-LogMessage -Tag 'INFO' -Message 'Building notification.'
		# Create embed and fields array
		[System.Collections.ArrayList]$embedArray = @()
		[System.Collections.ArrayList]$fieldArray = @()
		# Thumbnail object
		$thumbObject = [PSCustomObject]@{
			url = $currentConfig.thumbnail
		}
		# Field objects
		$resultField = [PSCustomObject]@{
			name   = 'Update Result'
			value  = $result
			inline = 'false'
		}
		$newVersionField = [PSCustomObject]@{
			name   = 'New version'
			value  = $newVersion
			inline = 'false'
		}
		$oldVersionField = [PSCustomObject]@{
			name   = 'Old version'
			value  = $oldVersion
			inline = 'false'
		}
		# Add field objects to the field array
		$fieldArray.Add($oldVersionField) | Out-Null
		$fieldArray.Add($newVersionField) | Out-Null
		$fieldArray.Add($resultField) | Out-Null
		# Send error if exist
		If ($null -ne $errorVar) {
			$errorField = [PSCustomObject]@{
				name   = 'Update Error'
				value  = $errorVar
				inline = 'false'
			}
			$fieldArray.Add($errorField) | Out-Null
		}
		# Embed object including field and thumbnail vars from above
		$embedObject = [PSCustomObject]@{
			title     = 'Update'
			color     = '1267393'
			thumbnail	= $thumbObject
			fields    = $fieldArray
		}
		# Add embed object to the array created above
		$embedArray.Add($embedObject) | Out-Null
		# Build payload
		$payload = [PSCustomObject]@{
			embeds	= $embedArray
		}
		Write-LogMessage -Tag 'INFO' -Message 'Sending notification.'
		# Send iiit
		Try {
			Invoke-RestMethod -Uri $currentConfig.webhook -Body ($payload | ConvertTo-Json -Depth 4) -Method Post -ContentType 'application/json'
		}
		Catch {
			$errorVar = $_.CategoryInfo.Activity + ' : ' + $_.ToString()
			Write-Warning 'Update notification failed to send to Discord.'
			Write-LogMessage -Tag 'ERROR' -Message "$errorVar"
		}
	}
}

# Success function
function Update-Success {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'Low'
	)]
	Param ()
	If ($PSCmdlet.ShouldProcess('Updater', 'Update success process')) {
		# Set error action preference so that errors while ending the script don't end the script prematurely.
		Write-LogMessage -Tag 'INFO' -Message 'Set error action preference.'
		$ErrorActionPreference = 'Continue'

		# Set result var for notification and script output
		$script:result = 'Success!'

		# Copy logs directory from copy of previously installed version to new install
		Write-LogMessage -Tag 'INFO' -Message 'Copying logs from old version to new version.'
		Copy-Item -Path $projectPath-old\log -Destination $projectPath\ -Recurse -Force

		# Remove copy of previously installed version
		Write-LogMessage -Tag 'INFO' -Message 'Removing old version.'
		Remove-Item -Path $projectPath-old -Recurse -Force

		# Trigger the Update-Notification function and then End-Script function.
		Update-Notification
		End-Script
	}
}

# Failure function
function Update-Fail {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'Low'
	)]
	Param ()
	If ($PSCmdlet.ShouldProcess('Updater', 'Update failure process')) {
		# Set error action preference so that errors while ending the script don't end the script prematurely.
		Write-LogMessage -Tag 'INFO' -Message 'Set error action preference.'
		$ErrorActionPreference = 'Continue'

		# Set result var for notification and script output
		$script:result = 'Failure!'

		# Take action based on the stage at which the error occured
		Switch ($fail) {
			download {
				Write-Warning 'Failed to download update.'
			}
			unzip {
				Write-Warning 'Failed to unzip update. Cleaning up and reverting.'
				Remove-Item -Path $projectPath-$LatestVersion.zip -Force
			}
			rename_old {
				Write-Warning 'Failed to rename old version. Cleaning up and reverting.'
				Remove-Item -Path $projectPath-$LatestVersion.zip -Force
				Remove-Item -Path $projectPath-$LatestVersion -Recurse -Force
			}
			rename_new {
				Write-Warning 'Failed to rename new version. Cleaning up and reverting.'
				Remove-Item -Path $projectPath-$LatestVersion.zip -Force
				Remove-Item -Path $projectPath-$LatestVersion -Recurse -Force
				Rename-Item $projectPath-old $projectPath
			}
			after_rename_new {
				Write-Warning 'Failed after renaming new version. Cleaning up and reverting.'
				Remove-Item -Path $projectPath-$LatestVersion.zip -Force
				Remove-Item -Path $projectPath -Recurse -Force
				Rename-Item $projectPath-old $projectPath
			}
		}

		# Trigger the Update-Notification function and then End-Script function.
		Update-Notification
		End-Script
	}
}

# End of script function
function Stop-Script {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'Low'
	)]
	Param ()
	If ($PSCmdlet.ShouldProcess('Updater', 'Cleanup & stop')) {
		# Clean up.
		Write-LogMessage -Tag 'INFO' -Message 'Remove downloaded ZIP.'
		If (Test-Path "$projectPath-$LatestVersion.zip") {
			Remove-Item "$projectPath-$LatestVersion.zip"
		}
		Write-LogMessage -Tag 'INFO' -Message 'Remove Updater.ps1.'
		Remove-Item -LiteralPath $PSCommandPath -Force

		# Report result
		Write-LogMessage -Tag 'INFO' -Message "Update result: $result"

		# Stop logging
		Write-LogMessage -Tag 'INFO' -Message 'Stop logging.'
		Stop-Logging $logFile

		# Move log file
		Write-Output 'Move log file to log directory in VeeamNotify.'
		Move-Item $logFile "$projectPath\log\"

		# Exit script
		Write-Output 'Exiting.'
		Exit
	}
}

# Pull current config to variable
Try {
	Write-LogMessage -Tag 'INFO' -Message 'Pull current config to variable.'
	$currentConfig = (Get-Content "$projectPath\config\conf.json") -Join "`n" | ConvertFrom-Json
}
Catch {
	$errorVar = $_.CategoryInfo.Activity + ' : ' + $_.ToString()
	Write-LogMessage -Tag 'ERROR' -Message "$errorVar"
	Update-Fail
}

# Get currently downloaded version
Try {
	Write-LogMessage -Tag 'INFO' -Message 'Getting currently downloaded version of the script.'
	[String]$oldVersion = Get-Content "$projectPath\resources\version.txt" -Raw
}
Catch {
	$errorVar = $_.CategoryInfo.Activity + ' : ' + $_.ToString()
	Write-LogMessage -Tag 'ERROR' -Message "$errorVar"
	Update-Fail
}

# Wait until the alert sender has finished running, or quit this if it's still running after 60s. It should never take that long.
while (Get-CimInstance win32_process -Filter "name='powershell.exe' and commandline like '%AlertSender.ps1%'") {
	$timer++
	Start-Sleep -Seconds 1
	If ($timer -eq '90') {
		Write-LogMessage -Tag 'INFO' -Message "Timeout reached. Updater quitting as AlertSender.ps1 is still running after $timer seconds."
	}
	Update-Fail
}

# Pull latest version of script from GitHub
Try {
	Write-LogMessage -Tag 'INFO' -Message 'Pull latest version of script from GitHub.'
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	Invoke-WebRequest -Uri `
		https://github.com/tigattack/VeeamNotify/releases/download/$LatestVersion/VeeamNotify-$LatestVersion.zip `
		-OutFile $projectPath-$LatestVersion.zip
}
Catch {
	$errorVar = $_.CategoryInfo.Activity + ' : ' + $_.ToString()
	Write-LogMessage -Tag 'ERROR' -Message "$errorVar"
	$fail = 'download'
	Update-Fail
}

# Expand downloaded ZIP
Try {
	Write-LogMessage -Tag 'INFO' -Message 'Expand downloaded ZIP.'
	Expand-Archive $projectPath-$LatestVersion.zip -DestinationPath $PSScriptRoot
}
Catch {
	$errorVar = $_.CategoryInfo.Activity + ' : ' + $_.ToString()
	Write-LogMessage -Tag 'ERROR' -Message "$errorVar"
	$fail = 'unzip'
	Update-Fail
}

# Rename old version to keep as a backup while the update is in progress.
Try {
	Write-LogMessage -Tag 'INFO' -Message 'Rename current to avoid conflict with new version.'
	Rename-Item $projectPath $projectPath-old
}
Catch {
	$errorVar = $_.CategoryInfo.Activity + ' : ' + $_.ToString()
	Write-LogMessage -Tag 'ERROR' -Message "$errorVar"
	$fail = 'rename_old'
	Update-Fail
}

# Rename extracted update
Try {
	Write-LogMessage -Tag 'INFO' -Message 'Rename extracted download.'
	Rename-Item $projectPath-$LatestVersion $projectPath
}
Catch {
	$errorVar = $_.CategoryInfo.Activity + ' : ' + $_.ToString()
	Write-LogMessage -Tag 'ERROR' -Message "$errorVar"
	$fail = 'rename_new'
	Update-Fail
}

# Pull configuration from new conf file
Try {
	Write-LogMessage -Tag 'INFO' -Message 'Pull configuration from new conf file.'
	$newConfig = (Get-Content "$projectPath\config\conf.json") -Join "`n" | ConvertFrom-Json
}
Catch {
	$errorVar = $_.CategoryInfo.Activity + ' : ' + $_.ToString()
	Write-LogMessage -Tag 'ERROR' -Message "$errorVar"
	$fail = 'after_rename_new'
	Update-Fail
}

# Unblock script files
Write-LogMessage -Tag 'INFO' -Message 'Unblock script files.'

## Get script files
$pwshFiles = Get-ChildItem $projectPath\* -Recurse | Where-Object { $_.Name -match '^.*\.ps(m)?1$' }

## Unblock them
Try {
	foreach ($i in $pwshFiles) {
		Unblock-File -Path $i.FullName
	}
}
Catch {
	$errorVar = $_.CategoryInfo.Activity + ' : ' + $_.ToString()
	Write-LogMessage -Tag 'ERROR' -Message "$errorVar"
	$fail = 'unblock_scripts'
	Update-Fail
}

# Populate conf.json with previous configuration
Try {
	Write-LogMessage -Tag 'INFO' -Message 'Populate conf.json with previous configuration.'
	$newConfig.webhook = $currentConfig.webhook
	$newConfig.userid = $currentConfig.userid
	if ($currentConfig.mentions.on_fail -ne $newConfig.mentions.on_fail) {
		$newConfig.mentions.on_fail = $currentConfig.mentions.on_fail
	}
	if ($currentConfig.logging.enabled -ne $newConfig.logging.enabled) {
		$newConfig.logging.enabled = $currentConfig.logging.enabled
	}
	if ($currentConfig.auto_update -ne $newConfig.auto_update) {
		$newConfig.auto_update = $currentConfig.auto_update
	}
	ConvertTo-Json $newConfig | Set-Content "$projectPath\config\conf.json"
}
Catch {
	$errorVar = $_.CategoryInfo.Activity + ' : ' + $_.ToString()
	Write-LogMessage -Tag 'ERROR' -Message "$errorVar"
	$fail = 'after_rename_new'
	Update-Fail
}

# Get newly downloaded version
Try {
	Write-LogMessage -Tag 'INFO' -Message 'Get newly downloaded version.'
	[String]$newVersion = Get-Content "$projectPath\resources\version.txt" -Raw
}
Catch {
	$errorVar = $_.CategoryInfo.Activity + ' : ' + $_.ToString()
	Write-LogMessage -Tag 'ERROR' -Message "$errorVar"
	$fail = 'after_rename_new'
	Update-Fail
}

# Send notification
If ($newVersion -eq $LatestVersion) {
	Update-Success
}
Else {
	Update-Fail
}
