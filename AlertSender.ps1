# Define parameters
param(
	[String]$SessionId,
	[String]$JobType,
	$Config,
	$Logfile
)

# Function to get a session's bottleneck from the session logs
# See for more details:
# https://github.com/tigattack/VeeamNotify/issues/19
# https://forums.veeam.com/powershell-f26/accessing-bottleneck-info-via-veeam-backup-model-cbottleneckinfo-bottleneck-t80127.html
function Get-Bottleneck {
	param(
		$Logger
	)

	$bottleneck = $Logger.GetLog() |
		Select-Object -ExpandProperty UpdatedRecords |
			Where-Object {$_.Title -match 'Primary bottleneck:.*'} |
				Select-Object -ExpandProperty Title |
					-replace 'Primary bottleneck:', ''

	if ($bottleneck.Length -eq 0) {
		$bottleneck = 'Undetermined'
	}
	else {
		$bottleneck = $bottleneck.Trim()
	}

	return $bottleneck
}

# Convert config from JSON
$Config = $Config | ConvertFrom-Json

# Import modules.
Import-Module Veeam.Backup.PowerShell -DisableNameChecking
Get-Item "$PSScriptRoot\resources\*.psm1" | Import-Module
Add-Type -AssemblyName System.Web


# Start logging if logging is enabled in config
if ($Config.logging.enabled) {
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
			$logLocked = $(Test-FileLock -Path "$Logfile" -ErrorAction Stop).IsLocked
			Start-Sleep -Seconds 1
		}
		until (-not $logLocked)
	}
	catch [System.Management.Automation.ItemNotFoundException] {
		Write-LogMessage -Tag 'INFO' -Message 'Log file not found. Starting logging to new file.'
	}

	## Start logging to file
	Start-Logging -Path $Logfile
}


# Determine if an update is required
$updateStatus = Get-UpdateStatus


try {
	# Job info preparation

	## Get the backup session.
	$session = (Get-VBRSessionInfo -SessionId $SessionId -JobType $JobType).Session

	## Initiate logger variable
	$vbrSessionLogger = $session.Logger

	## Wait for the backup session to finish.
	if ($false -eq $session.Info.IsCompleted) {
		$timeout = New-TimeSpan -Minutes 5
		$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
		do {
			Write-LogMessage -Tag 'INFO' -Message 'Session not completed. Sleeping...'
			Start-Sleep -Seconds 10
			$session = (Get-VBRSessionInfo -SessionId $SessionId -JobType $JobType).Session
		}
		while ($false -eq $session.Info.IsCompleted -and $stopwatch.Elapsed -lt $timeout)
		$stopwatch.Stop()
	}

	## Quit if still not stopped
	if ($false -eq $session.Info.IsCompleted) {
		Write-LogMessage -Tag 'ERROR' -Message 'Session still not completed after timeout. Aborting.'
		exit 1
	}

	# Add Veeam session log entry.
	$logId_start = $vbrSessionLogger.AddLog('[VeeamNotify] Gathering session details...')

	## Gather generic session info.
	[String]$status = $session.Result

	# Decide whether to continue
	# Default to sending notification if unconfigured
	if (
		($status -eq 'Failed' -and -not $config.notifications.on_failure) -or
		($status -eq 'Warning' -and -not $config.notifications.on_warning) -or
		($status -eq 'Success' -and -not $config.notifications.on_success)
	) {
		Write-LogMessage -Tag 'info' -Message "Job $($status.ToLower()); per configured options, no notification will be sent."
		$vbrSessionLogger.UpdateSuccess($logId_start, "[VeeamNotify] Not configured to send notifications for $($status.ToLower()) status.") | Out-Null
		exit
	}


	# Define session statistics for the report.

	## If VM backup/replica, gather and include session info.
	if ($JobType -in 'Backup', 'Replica') {
		# Gather session data sizes and timing.
		[Float]$dataSize 		= $session.BackupStats.DataSize
		[Float]$transferSize 	= $session.BackupStats.BackupSize
		[Float]$speed 			= $session.Info.Progress.AvgSpeed
		[DateTime]$endTime 		= $session.Info.EndTime
		[DateTime]$startTime 	= $session.Info.CreationTime
		[string]$dedupRatio 	= $session.BackupStats.DedupRatio
		[string]$compressRatio	= $session.BackupStats.CompressRatio
		[string]$bottleneck 	= Get-Bottleneck -Logger $vbrSessionLogger

		# Convert bytes to closest unit.
		$dataSizeRound 		= Format-Bytes -Data $dataSize
		$transferSizeRound	= Format-Bytes -Data $transferSize
		$speedRound 		= (Format-Bytes -Data $speed) + '/s'

		# Set processing speed "Unknown" if 0B/s to avoid confusion.
		if ($speedRound -eq '0 B/s') {
			$speedRound = 'Unknown'
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
			if ($object.Status -eq 'Warning') {
				$sessionObjectWarns++
			}
			# TODO: check if 'Failed' is a valid state.
			if ($object.Status -eq 'Failed') {
				$sessionObjectFails++
			}
		}

		# Add object warns/fails to fieldArray if any.
		if ($sessionObjectWarns -gt 0) {
			$fieldArray += @(
				[PSCustomObject]@{
					name	= 'Warnings'
					value	= "$sessionObjectWarns/$sessionobjectsCount"
					inline	= 'true'
				}
			)
		}
		if ($sessionObjectFails -gt 0) {
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
	if ($JobType -in 'EpAgentBackup', 'BackupToTape', 'FileToTape') {
		# Gather session data sizes and timings.
		[Float]$processedSize	= $session.Info.Progress.ProcessedSize
		[Float]$transferSize 	= $session.Info.Progress.TransferedSize
		[Float]$speed			= $session.Info.Progress.AvgSpeed
		[DateTime]$endTime		= $session.EndTime
		[DateTime]$startTime	= $session.CreationTime
		[string]$bottleneck 	= Get-Bottleneck -Logger $vbrSessionLogger

		# Convert bytes to closest unit.
		$processedSizeRound	= Format-Bytes -Data $processedSize
		$transferSizeRound	= Format-Bytes -Data $transferSize
		$speedRound 		= (Format-Bytes -Data $speed) + '/s'

		# Set processing speed "Unknown" if 0B/s to avoid confusion.
		if ($speedRound -eq '0 B/s') {
			$speedRound = 'Unknown'
		}
	}

	# Update Veeam session log.
	$vbrSessionLogger.UpdateSuccess($logId_start, '[VeeamNotify] Successfully discovered session details.') | Out-Null
	$logId_notification = $vbrSessionLogger.AddLog('[VeeamNotify] Preparing to send notification(s)...')


	# Job timings

	## Calculate difference between job start and end time.
	$duration = $session.Info.Progress.Duration

	## Switch for job duration; define pretty output.
	switch ($duration) {
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
		default {
			$durationFormatted	= '{0}d {1}h {2}m {3}s' -f $_.Days, $_.Hours, $_.Minutes, $_.Seconds
		}
	}

	# Define nice job type name
	switch ($JobType) {
		Backup { $jobTypeNice = 'VM Backup' }
		Replica { $jobTypeNice = 'VM Replication' }
		EpAgentBackup	{
			switch ($session.Platform) {
				'ELinuxPhysical' { $jobTypeNice = 'Linux Agent Backup' }
				'EEndPoint' { $jobTypeNice = 'Windows Agent Backup' }
			}
		}
		FileToTape { $jobTypeNice = 'File Tape Backup' }
		BackupToTape { $jobTypeNice = 'Repo Tape Backup' }
	}

	# Decide whether to mention user
	$mention = $false
	## On fail
	try {
		if ($Config.mentions.on_failure -and $status -eq 'Failed') {
			$mention = $true
		}
	}
	catch {
		Write-LogMessage -Tag 'WARN' -Message "Unable to determine 'mention on fail' configuration. User will not be mentioned."
	}

	## On warning
	try {
		if ($Config.mentions.on_warning -and $status -eq 'Warning') {
			$mention = $true
		}
	}
	catch {
		Write-LogMessage -Tag 'WARN' -Message "Unable to determine 'mention on warning' configuration. User will not be mentioned."
	}


	# Define footer message.
	$footerMessage = "tigattack's VeeamNotify $($updateStatus.CurrentVersion)"
	switch ($updateStatus.Status) {
		Current {$footerMessage += ' - Up to date.'}
		Behind {$footerMessage += " - Update to $($updateStatus.LatestStable) is available!"}
		Ahead {$footerMessage += ' - Pre-release.'}
	}


	# Build embed parameters
	$payloadParams = [ordered]@{
		JobName       = $session.Name
		JobType       = $jobTypeNice
		Status        = $status
		Speed         = $speedRound
		Bottleneck    = $bottleneck
		Duration      = $durationFormatted
		StartTime     = $startTime
		EndTime       = $endTime
		Mention       = $mention
		ThumbnailUrl  = $Config.thumbnail
		FooterMessage = $footerMessage
	}

	if ($JobType -in 'EpAgentBackup', 'BackupToTape', 'FileToTape') {
		$payloadParams.Insert('3', 'ProcessedSize', $processedSizeRound)
		$payloadParams.Insert('4', 'TransferSize', $transferSizeRound)
	}
	else {
		$payloadParams.Insert('3', 'DataSize', $dataSizeRound)
		$payloadParams.Insert('4', 'TransferSize', $transferSizeRound)
		$payloadParams.Insert('5', 'DedupRatio', $dedupRatio)
		$payloadParams.Insert('6', 'CompressRatio', $compressRatio)
	}

	# Add update message if relevant.
	if ($config.update | Get-Member -Name 'notify') {
		$config.update.notify = $true
	}

	# Add update status
	$payloadParams.NotifyUpdate = $config.update.notify
	$payloadParams.UpdateAvailable	= $updateStatus.Status -eq 'Behind'

	# Add latest version if update is available
	if ($payloadParams.UpdateAvailable) {
		$payloadParams.LatestVersion = $updateStatus.LatestStable
	}


	# Build embed and send iiiit.
	try {
		$Config.services.PSObject.Properties | ForEach-Object {
			$service = $_

			# Make service name TitleCase
			$serviceName = (Get-Culture).TextInfo.ToTitleCase($service.Name)

			# Skip if service is not enabled
			if (-not $service.Value.enabled) {
				Write-LogMessage -Tag 'DEBUG' -Message "Skipping $($serviceName) notification as it is not enabled."
				return
			}

			# Log that we're attempting to send notification
			$logId_service = $vbrSessionLogger.AddLog("[VeeamNotify] Sending $($serviceName) notification...")

			# Call the appropriate notification sender function based on service name
			switch ($serviceName.ToLower()) {
				'discord' {
					$result = Send-WebhookNotification -Service 'Discord' -Parameters $payloadParams -ServiceConfig $service.Value
				}
				'slack' {
					$result = Send-WebhookNotification -Service 'Slack' -Parameters $payloadParams -ServiceConfig $service.Value
				}
				'teams' {
					$result = Send-WebhookNotification -Service 'Teams' -Parameters $payloadParams -ServiceConfig $service.Value
				}
				'telegram' {
					$result = Send-TelegramNotification -Parameters $payloadParams -ServiceConfig $service.Value
				}
				'http' {
					$result = Send-HttpNotification -Parameters $payloadParams -ServiceConfig $service.Value
				}
				default {
					Write-LogMessage -Tag 'WARN' -Message "Skipping unknown service: $serviceName"
				}
			}

			# Update the Veeam session log based on the result
			if ($result.Success) {
				$vbrSessionLogger.UpdateSuccess($logId_service, "[VeeamNotify] Sent notification to $($serviceName).") | Out-Null
				Write-LogMessage -Tag 'INFO' -Message "$serviceName notification sent successfully."
				if ($result.Message) {
					Write-LogMessage -Tag 'DEBUG' -Message "$serviceName notification response: $($result.Message)"
				}
				else {
					Write-LogMessage -Tag 'DEBUG' -Message "No response received from $serviceName notification."
				}
			}
			else {
				$vbrSessionLogger.UpdateErr($logId_service, "[VeeamNotify] $serviceName notification could not be sent.", "Please check the log: $Logfile") | Out-Null

				[System.Collections.ArrayList]$errors = @()
				$result.Detail.GetEnumerator().ForEach({ $errors.Add("$($_.Name)=$($_.Value)") | Out-Null })
				Write-LogMessage -Tag 'ERROR' -Message "$serviceName notification could not be sent: $($errors -Join '; ')"
			}
		}

		# Update Veeam session log.
		$vbrSessionLogger.UpdateSuccess($logId_notification, '[VeeamNotify] Notification(s) sent successfully.') | Out-Null
	}
	catch {
		Write-LogMessage -Tag 'WARN' -Message "Unable to send notification(s): ${_Exception.Message}"
		$_
		$vbrSessionLogger.UpdateErr($logId_notification, '[VeeamNotify] An error occured while sending notification(s).', "Please check the log: $Logfile") | Out-Null
	}

	# Clean up old log files if configured
	if ($Config.logging.max_age_days -ne 0) {
		Write-LogMessage -Tag 'DEBUG' -Message 'Running log cleanup.'

		if ($config.logging.level -eq 'debug') {
			$debug = $true
		}
		else {
			$debug = $false
		}

		Remove-OldLogs -Path "$PSScriptRoot\log" -MaxAgeDays $Config.logging.max_age_days -Verbose:$debug
	}

	# If newer version available...
	if ($updateStatus.Status -eq 'Behind') {

		# Add Veeam session log entry.
		if ($Config.update.notify) {
			$vbrSessionLogger.AddWarning("[VeeamNotify] A new version is available: $($updateStatus.LatestStable). Currently running: $($updateStatus.CurrentVersion)") | Out-Null
		}

		# Trigger update if configured to do so.
		if ($Config.update.auto_update) {
			Write-LogMessage -Tag 'WARN' -Message 'An update is available and auto_update was enabled in config, but the feature is not yet implemented.'

			# # Copy update script out of working directory.
			# Copy-Item $PSScriptRoot\Updater.ps1 $PSScriptRoot\..\VDNotifs-Updater.ps1
			# Unblock-File $PSScriptRoot\..\VDNotifs-Updater.ps1

			# # Run update script.
			# $updateArgs = "-file $PSScriptRoot\..\VDNotifs-Updater.ps1", "-LatestVersion $($updateStatus.LatestStable)"
			# Start-Process -FilePath 'powershell' -Verb runAs -ArgumentList $updateArgs -WindowStyle hidden
		}
	}
}
catch {
	Write-LogMessage -Tag 'ERROR' -Message "A terminating error occured: ${_Exception.Message}"
	$_
	# Add Veeam session log entry if logger is available
	if ($vbrSessionLogger) {
		$vbrSessionLogger.UpdateErr($logId_start, '[VeeamNotify] A terminating error occured.', "Please check the log: $Logfile") | Out-Null
	}
}
finally {
	# Stop logging.
	if ($Config.logging.enabled) {
		Stop-Logging
	}
}
