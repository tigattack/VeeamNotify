# Define parameters
Param(
	[String]$jobName,
	[String]$id,
	[String]$jobType,
	$Config,
	$Logfile
)

# Convert config from JSON
$Config = $Config | ConvertFrom-Json

# Create hash table for later use
$hash = @{}

# Import modules.
Import-Module Veeam.Backup.PowerShell -DisableNameChecking
Import-Module "$PSScriptRoot\resources\ConvertTo-ByteUnit.psm1"
Import-Module "$PSScriptRoot\resources\Logger.psm1"
Import-Module "$PSScriptRoot\resources\NotificationHandler.psm1"
Import-Module "$PSScriptRoot\resources\Test-FileIsLocked.psm1"
Import-Module "$PSScriptRoot\resources\UpdateInfo.psm1"
Import-Module "$PSScriptRoot\resources\VBRSessionInfo.psm1"


# Start logging if logging is enabled in config
If ($Config.debug_log) {
	## Wait until log file is closed by Bootstrap.ps1
	try {
		$count = 1
		do {
			$logExist = Test-Path -Path $Logfile
			$count++
			Start-Sleep -Seconds 1
		}
		until ($logExist -eq $true -or $count -ge 10)
		do {
			$logLocked = $(Test-FileIsLocked -Path "$Logfile" -ErrorAction Stop).IsLocked
			Start-Sleep -Seconds 1
		}
		until (-not $logLocked)
	}
	catch [System.Management.Automation.ItemNotFoundException] {
		Write-LogMessage -Tag 'INFO' -Message 'Log file not found. Starting logging to new file.'
	}

	## Start logging to file
	Start-Logging -Path $Logfile -Append
}


# Determine if an update is required
$updateStatus = Get-UpdateStatus


# Job info preparation

## Get the backup session.
$session = (Get-VBRSessionInfo -SessionId $id -JobType $jobType).Session
## Initiate logger variable
$vbrSessionLogger = $session.Logger

## Wait for the backup session to finish.
If ($session.State -ne 'Stopped') {
	$nonStoppedStates = 'Idle', 'Pausing', 'Postprocessing', 'Resuming', 'Starting', 'Stopping', 'WaitingRepository', 'WaitingTape ', 'Working'
	$timeout = New-TimeSpan -Minutes 5
	$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
	Do {
		Write-LogMessage -Tag 'INFO' -Message 'Session not finished. Sleeping...'
		Start-Sleep -Seconds 10
		$session = (Get-VBRSessionInfo -SessionId $id -JobType $jobType).Session
	}
	While ($session.State -in $nonStoppedStates -and $stopwatch.elapsed -lt $timeout)
	$stopwatch.Stop()
}

## Quit if still not stopped
If ($session.State -ne 'Stopped') {
	Write-LogMessage -Tag 'ERROR' -Message 'Session not stopped. Aborting.'
	Exit 1
}

# Add Veeam session log
$logId_start = $vbrSessionLogger.AddLog('[VeeamNotify] Script running...')

## Gather generic session info.
[String]$status = $session.Result


# Define session statistics for the report.

## If VM backup/replica, gather and include session info.
if ($jobType -in 'Backup', 'Replica') {
	# Gather session data sizes and timing.
	[Float]$dataSize = $session.BackupStats.DataSize
	[Float]$transferSize = $session.BackupStats.BackupSize
	[Float]$speed = $session.Info.Progress.AvgSpeed
	$endTime = $session.Info.EndTime
	$startTime = $session.Info.CreationTime
	[string]$dedupRatio = $session.BackupStats.DedupRatio
	[string]$compressRatio	= $session.BackupStats.CompressRatio

	# Convert bytes to closest unit.
	$dataSizeRound = ConvertTo-ByteUnit -Data $dataSize
	$transferSizeRound	= ConvertTo-ByteUnit -Data $transferSize
	$speedRound = (ConvertTo-ByteUnit -Data $speed).ToString() + '/s'

	# Set processing speed "Unknown" if 0B/s to avoid confusion.
	If ($speedRound -eq '0 B/s') {
		$speedRound = 'Unknown'
	}

	# Define bottleneck
	Switch ($session.Info.Progress.BottleneckInfo.Bottleneck) {
		'NotDefined' {
			$bottleneck = 'Undefined'
		}
		Default {
			$bottleneck = $_
		}
	}

	<# TODO: utilise this.
	# Get objects in session.
	$sessionObjects = $session.GetTaskSessions()

	## Count total
	$sessionObjectsCount = $sessionObjects.Count

	## Count warns and fails
	$sessionObjectWarns = 0
	$sessionObjectFails = 0

	foreach ($object in $sessionObjects) {
		If ($object.Status -eq 'Warning') {
			$sessionObjectWarns++
		}
		# TODO: check if 'Failed' is a valid state.
		If ($object.Status -eq 'Failed') {
			$sessionObjectFails++
		}
	}
	#>

	<# TODO: utilise this.
	# Add object warns/fails to fieldArray if any.
	If ($sessionObjectWarns -gt 0) {
		$fieldArray += @(
			[PSCustomObject]@{
				name	= 'Warnings'
				value	= "$sessionObjectWarns/$sessionobjectsCount"
				inline	= 'true'
			}
		)
	}
	If ($sessionObjectFails -gt 0) {
		$fieldArray += @(
			[PSCustomObject]@{
				name	= 'Fails'
				value	= "$sessionObjectFails/$sessionobjectsCount"
				inline	= 'true'
			}
		)
	}
	#>
}

# If agent backup, gather and include session info.
If ($jobType -eq 'EpAgentBackup') {
	# Gather session data sizes and timings.
	[Float]$processedSize = $session.Info.Progress.ProcessedSize
	[Float]$transferSize = $session.Info.Progress.TransferedSize
	[Float]$speed = $session.Info.Progress.AvgSpeed
	$endTime = $session.EndTime
	$startTime = $session.CreationTime

	# Convert bytes to closest unit.
	$processedSizeRound = ConvertTo-ByteUnit -Data $processedSize
	$transferSizeRound	= ConvertTo-ByteUnit -Data $transferSize
	$speedRound = (ConvertTo-ByteUnit -Data $speed).ToString() + '/s'

	# Set processing speed "Unknown" if 0B/s to avoid confusion.
	If ($speedRound -eq '0 B/s') {
		$speedRound = 'Unknown'
	}

	# Define bottleneck
	Switch ($session.Info.Progress.BottleneckInfo.Bottleneck) {
		'NotDefined' {
			$bottleneck = 'Undefined'
		}
		Default {
			$bottleneck = $_
		}
	}
}


# Job timings

## Calculate difference between job start and end time.
$duration = $endTime - $startTime

## Switch for job duration; define pretty output.
Switch ($duration) {
	{ $_.Days -ge '1' } {
		$durationFormatted	= '{0}d {1}h {2}m {3}s' -f $_.Days, $_.Hours, $_.Minutes, $_.Seconds
		break
	}
	{ $_.Hours -ge '1' } {
		$durationFormatted	= '{0}h {1}m {2}s' -f $_.Hours, $_.Minutes, $_.Seconds
		break
	}
	{ $_.Minutes -ge '1' } {
		$durationFormatted	= '{0}m {1}s' -f $_.Minutes, $_.Seconds
		break
	}
	{ $_.Seconds -ge '1' } {
		$durationFormatted	= '{0}s' -f $_.Seconds
		break
	}
	Default {
		$durationFormatted	= '{0}d {1}h {2}m {3}s' -f $_.Days, $_.Hours, $_.Minutes, $_.Seconds
	}
}

# Define nice job type name
Switch ($jobType) {
	Backup { $jobTypeNice = 'VM Backup' }
	Replica { $jobTypeNice = 'VM Replication' }
	EpAgentBackup	{
		Switch ($session.Platform) {
			'ELinuxPhysical' { $jobTypeNice = 'Linux Agent Backup' }
			'EEndPoint' { $jobTypeNice = 'Windows Agent Backup' }
		}
	}
}

# Decide whether to mention user
$mention = $false
## On fail
Try {
	If ($Config.mention_on_fail -and $status -eq 'Failed') {
		$mention = $true
	}
}
Catch {
	Write-LogMessage -Tag 'WARN' -Message "Unable to determine 'mention on fail' configuration. User will not be mentioned."
}

## On warning
Try {
	If ($Config.mention_on_warning -and $status -eq 'Warning') {
		$mention = $true
	}
}
Catch {
	Write-LogMessage -Tag 'WARN' -Message "Unable to determine 'mention on warning' configuration. User will not be mentioned."
}


# Define footer message.
Switch ($updateStatus.Status) {
	Current {
		$footerMessage = "tigattack's VeeamNotify $($updateStatus.CurrentVersion) - Up to date."
	}
	Behind {
		$footerMessage = "tigattack's VeeamNotify $($updateStatus.CurrentVersion) - Update to $($updateStatus.LatestStable) is available!"
	}
	Ahead {
		$footerMessage = "tigattack's VeeamNotify $($updateStatus.CurrentVersion) - Pre-release."
	}
	Default {
		$footerMessage = "tigattack's VeeamNotify $($updateStatus.CurrentVersion)."
	}
}


# Build embed parameters
If ($jobType -ne 'EpAgentBackup') {
	$payloadParams = @{
		JobName       = $jobName
		JobType       = $jobTypeNice
		Status        = $status
		DataSize      = $dataSizeRound
		TransferSize  = $transferSizeRound
		DedupRatio    = $dedupRatio
		CompressRatio = $compressRatio
		Speed         = $speedRound
		Bottleneck    = $bottleneck
		Duration      = $durationFormatted
		StartTime     = $startTime
		EndTime       = $endTime
		Mention       = $mention
		ThumbnailUrl  = $Config.thumbnail
		FooterMessage = $footerMessage
	}
}

elseif ($jobType -eq 'EpAgentBackup') {
	$payloadParams = @{
		JobName       = $jobName
		JobType       = $jobTypeNice
		Status        = $status
		ProcessedSize = $processedSizeRound
		TransferSize  = $transferSizeRound
		Speed         = $speedRound
		Bottleneck    = $bottleneck
		Duration      = $durationFormatted
		StartTime     = $startTime
		EndTime       = $endTime
		Mention       = $mention
		ThumbnailUrl  = $Config.thumbnail
		FooterMessage = $footerMessage
	}
}

# Add update message if relevant.
If ($updateStatus.Status -eq 'Behind' -and $Config.notify_update) {
	$payloadParams += @{
		UpdateNotification = $true
		LatestVersion      = $updateStatus.LatestStable
	}
}

# Define services to be notified.
$services = @()
$Config.services.PSObject.Properties | ForEach-Object {
	If ($_.Value.webhook.StartsWith('http')) {
		$services += $_.Name
	}
}

# Build embed and send iiiit.
Switch ($services) {
	'discord' {
		Write-LogMessage -Tag 'INFO' -Message 'Sending notification to Discord.'
		$logId_discord = $vbrSessionLogger.AddLog('[VeeamNotify] Sending notification to Discord...')

		# Add user information for mention if relevant.
		If ($mention) {
			$payloadParams.UserId = $_.discord.user_id
		}

		try {
			New-DiscordPayload @payloadParams | Send-Payload -Uri $Config.services.discord.webhook
			Write-LogMessage -Tag 'INFO' -Message 'Discord notification sent successfully.'
			$vbrSessionLogger.UpdateSuccess($logId_discord, '[VeeamNotify] Discord notification sent successfully.')
			$hash["Discord"] = "Success"
		}
		catch {
			Write-LogMessage -Tag 'WARN' -Message "Unable to send Discord notification: $_"
			$vbrSessionLogger.UpdateErr($logId_discord, '[VeeamNotify] Discord notification could not be sent.', 'Please check logs at C:\VeeamScripts\VeeamNotify\log\')
			$hash["Discord"] = "Failure"
		}
	}

	'slack' {
		Write-LogMessage -Tag 'INFO' -Message 'Sending notification to Slack.'
		$logId_slack = $vbrSessionLogger.AddLog('[VeeamNotify] Sending notification to Slack...')

		# Add user information for mention if relevant.
		If ($mention) {
			$payloadParams.UserId = $_.slack.user_id
		}

		try {
			New-SlackPayload @payloadParams | Send-Payload -Uri $Config.services.slack.webhook
			Write-LogMessage -Tag 'INFO' -Message 'Slack notification sent successfully.'
			$vbrSessionLogger.UpdateSuccess($logId_slack, '[VeeamNotify] Slack notification sent successfully.')
			$hash["Slack"] = "Success"
		}
		catch {
			Write-LogMessage -Tag 'WARN' -Message "Unable to send Slack notification: $_"
			$vbrSessionLogger.UpdateErr($logId_slack, '[VeeamNotify] Slack notification could not be sent.', 'Please check logs at C:\VeeamScripts\VeeamNotify\log\')
			$hash["Slack"] = "Failure"
		}
	}

	'teams' {
		Write-LogMessage -Tag 'INFO' -Message 'Sending notification to Teams.'
		$logId_teams = $vbrSessionLogger.AddLog('[VeeamNotify] Sending notification to Teams...')

		# Add user information for mention if relevant.
		If ($mention) {
			$payloadParams.UserId = $_.teams.user_id
			If ($Config.teams_user_name -ne 'Your Name') {
				$payloadParams.UserName = $_.teams.user_name
			}
		}

		try {
			New-TeamsPayload @payloadParams | Send-Payload -Uri $Config.services.teams.webhook
			Write-LogMessage -Tag 'INFO' -Message 'Teams notification sent successfully.'
			$vbrSessionLogger.UpdateSuccess($logId_teams, '[VeeamNotify] Teams notification sent successfully.')
			$hash["Teams"] = "Success"
		}
		catch {
			Write-LogMessage -Tag 'WARN' -Message "Unable to send Teams notification: $_"
			$vbrSessionLogger.UpdateErr($logId_teams, '[VeeamNotify] Teams notification could not be sent.', 'Please check logs at C:\VeeamScripts\VeeamNotify\log\')
			$hash["Teams"] = "Failure"
		}
	}
}

if (($hash.Values).Contains('Success') -and -not ($hash.Values -contains('Failed'))) {
    $vbrSessionLogger.UpdateSuccess($logId_start, '[VeeamNotify] Script completed successfully.')
}
elseif (($hash.Values).Contains('Success') -and ($hash.Values -contains('Failed'))) {
    $vbrSessionLogger.UpdateWarning($logId_start, '[VeeamNotify] Script completed with some send failures.', 'Please check logs at C:\VeeamScripts\VeeamNotify\log\')
} else {
    $vbrSessionLogger.UpdateErr($logId_start, '[VeeamNotify] Script failed. Did not send any notifications.', 'Please check logs at C:\VeeamScripts\VeeamNotify\log\')
}

# If newer version available...
If ($updateStatus.Status -eq 'Behind') {

	If ($Config.notify_update) {
		$vbrSessionLogger.AddWarning("[VeeamNotify] A new version is available: $($updateStatus.LatestStable). Currently running: $($updateStatus.CurrentVersion)")
	}

	# Trigger update if configured to do so.
	If ($Config.self_update) {

		# Copy update script out of working directory.
		Copy-Item $PSScriptRoot\Updater.ps1 $PSScriptRoot\..\VDNotifs-Updater.ps1
		Unblock-File $PSScriptRoot\..\VDNotifs-Updater.ps1

		# Run update script.
		$updateArgs = "-file $PSScriptRoot\..\VDNotifs-Updater.ps1", "-LatestVersion $($updateStatus.LatestStable)"
		Start-Process -FilePath 'powershell' -Verb runAs -ArgumentList $updateArgs -WindowStyle hidden
	}
}

# Somehow get status of payload dispatch (hence refactor of service switch above, could use a boolean var per service to indicate success/failure) ideally overall status if possible, and then...
# if success:
# $vbrSessionLogger.UpdateSuccess($logId_start, '[VeeamNotify] Script completed successfully.')
# if error:
# $vbrSessionLogger.UpdateErr($logId_start, '[VeeamNotify] Script failed.', 'Please check logs at C:\VeeamScripts\VeeamNotify\log\')
# stretch, if warning:
# $vbrSessionLogger.UpdateWarning($logId_start, '[VeeamNotify] Script completed with warnings.', 'Please check logs at C:\VeeamScripts\VeeamNotify\log\')


# Stop logging.
If ($Config.debug_log) {
	Stop-Logging
}
