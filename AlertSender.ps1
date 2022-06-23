# Define parameters
Param(
	[String]$jobName,
	[String]$id,
	[String]$jobType,
	$Config,
	$Logfile
)

# Function to get a session's bottleneck from the session logs
# See https://github.com/tigattack/VeeamNotify/issues/19 for more details.
Function Get-Bottleneck {
	param(
		$Logger
	)

	$bottleneck = ($Logger.GetLog() | `
				Select-Object -ExpandProperty UpdatedRecords | `
				Where-Object {$_.Title -match 'Primary bottleneck:.*'} | `
				Select-Object -ExpandProperty Title) `
		-replace 'Primary bottleneck:',''

	If ($bottleneck.Length -eq 0) {
		$bottleneck = 'Undetermined'
	}
	Else {
		$bottleneck = $bottleneck.Trim()
	}

	return $bottleneck
}

# Convert config from JSON
$Config = $Config | ConvertFrom-Json

# Import modules.
Import-Module Veeam.Backup.PowerShell -DisableNameChecking
Get-Item "$PSScriptRoot\resources\*.psm1" | Import-Module


# Start logging if logging is enabled in config
If ($Config.logging.enabled) {
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


try {
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
	if ($jobType -in 'Backup', 'Replica') {
		# Gather session data sizes and timing.
		[Float]$dataSize 		= $session.BackupStats.DataSize
		[Float]$transferSize 	= $session.BackupStats.BackupSize
		[Float]$speed 			= $session.Info.Progress.AvgSpeed
		$endTime 				= $session.Info.EndTime
		$startTime 				= $session.Info.CreationTime
		[string]$dedupRatio 	= $session.BackupStats.DedupRatio
		[string]$compressRatio	= $session.BackupStats.CompressRatio
		[string]$bottleneck 	= Get-Bottleneck -Logger $vbrSessionLogger

		# Convert bytes to closest unit.
		$dataSizeRound 		= ConvertTo-ByteUnit -Data $dataSize
		$transferSizeRound	= ConvertTo-ByteUnit -Data $transferSize
		$speedRound 		= (ConvertTo-ByteUnit -Data $speed).ToString() + '/s'

		# Set processing speed "Unknown" if 0B/s to avoid confusion.
		If ($speedRound -eq '0 B/s') {
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
		[Float]$processedSize	= $session.Info.Progress.ProcessedSize
		[Float]$transferSize 	= $session.Info.Progress.TransferedSize
		[Float]$speed			= $session.Info.Progress.AvgSpeed
		$endTime				= $session.EndTime
		$startTime				= $session.CreationTime
		[string]$bottleneck 	= Get-Bottleneck -Logger $vbrSessionLogger

		# Convert bytes to closest unit.
		$processedSizeRound	= ConvertTo-ByteUnit -Data $processedSize
		$transferSizeRound	= ConvertTo-ByteUnit -Data $transferSize
		$speedRound 		= (ConvertTo-ByteUnit -Data $speed).ToString() + '/s'

		# Set processing speed "Unknown" if 0B/s to avoid confusion.
		If ($speedRound -eq '0 B/s') {
			$speedRound = 'Unknown'
		}
	}

	# Update Veeam session log.
	$vbrSessionLogger.UpdateSuccess($logId_start, '[VeeamNotify] Gathered session details.') | Out-Null
	$logId_notification = $vbrSessionLogger.AddLog('[VeeamNotify] Preparing to send notification(s)...')


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
		If ($Config.mentions.on_failure -and $status -eq 'Failed') {
			$mention = $true
		}
	}
	Catch {
		Write-LogMessage -Tag 'WARN' -Message "Unable to determine 'mention on fail' configuration. User will not be mentioned."
	}

	## On warning
	Try {
		If ($Config.mentions.on_warning -and $status -eq 'Warning') {
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
			$footerMessage = "tigattack's VeeamNotify $($updateStatus.CurrentVersion)"
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
	If ($config.update | Get-Member -Name 'notify') {
		$config.update.notify = $true
	}
	If ($updateStatus.Status -eq 'Behind' -and $config.update.notify) {
		$payloadParams += @{
			UpdateNotification = $true
			LatestVersion      = $updateStatus.LatestStable
		}
	}


	# Build embed and send iiiit.
	Try {
		$Config.services.PSObject.Properties | ForEach-Object {

			# Create variable from current pipeline object to simplify usability.
			$service = $_

			# Create variable for service name in TitleCase format.
			$textInfo = (Get-Culture).TextInfo
			$serviceName = $textInfo.ToTitleCase($service.Name)

			If ($service.Value.webhook.StartsWith('https')) {
				Write-LogMessage -Tag 'INFO' -Message "Sending notification to $($serviceName)."
				$logId_service = $vbrSessionLogger.AddLog("[VeeamNotify] Sending notification to $($serviceName)...")

				# Add user information for mention if relevant.
				Write-LogMessage -Tag 'DEBUG' -Message 'Determining if user should be mentioned.'
				If ($mention) {
					Write-LogMessage -Tag 'DEBUG' -Message 'Getting user ID for mention.'
					$payloadParams.UserId = $service.Value.user_id

					# Get username if Teams
					If ($service.Value.user_name -and $service.Value.user_name -ne 'Your Name') {
						Write-LogMessage -Tag 'DEBUG' -Message 'Getting Teams user name for mention.'
						$payloadParams.UserName = $service.Value.user_name
					}
				}

				Try {
					New-Payload -Service $service.Name -Parameters $payloadParams | Send-Payload -Uri $service.Value.webhook | Out-Null

					Write-LogMessage -Tag 'INFO' -Message "Notification sent to $serviceName successfully."
					$vbrSessionLogger.UpdateSuccess($logId_service, "[VeeamNotify] Sent notification to $($serviceName).") | Out-Null
				}
				Catch {
					Write-LogMessage -Tag 'ERROR' -Message "Unable to send $serviceName notification: $_"
					$vbrSessionLogger.UpdateErr($logId_service, "[VeeamNotify] $serviceName notification could not be sent.", "Please check the log: $Logfile") | Out-Null
				}
			}
			Else {
				Write-LogMessage -Tag 'DEBUG' -Message "$serviceName is unconfigured (invalid URL). Skipping $serviceName notification."
			}
		}

		# Update Veeam session log.
		$vbrSessionLogger.AddSuccess('[VeeamNotify] Notification(s) sent successfully.') | Out-Null
	}
	Catch {
		Write-LogMessage -Tag 'WARN' -Message "Unable to send notification(s): $_"
		$vbrSessionLogger.AddErr('[VeeamNotify] An error occured while sending notification(s).', "Please check the log: $Logfile") | Out-Null
	}
	Finally {
		$vbrSessionLogger.RemoveRecord($logId_notification) | Out-Null
	}

	# Clean up old log files if configured
	if ($Config.logging.max_age_days -ne 0) {
		Write-LogMessage -Tag 'DEBUG' -Message 'Running log cleanup.'

		If ($config.logging.level -eq 'debug') {
			$debug = $true
		}
		else {
			$debug = $false
		}

		Remove-OldLogs -Path "$PSScriptRoot\log" -MaxAgeDays $Config.logging.max_age_days -Verbose:$debug
	}

	# If newer version available...
	If ($updateStatus.Status -eq 'Behind') {

		# Add Veeam session log entry.
		If ($Config.update.notify) {
			$vbrSessionLogger.AddWarning("[VeeamNotify] A new version is available: $($updateStatus.LatestStable). Currently running: $($updateStatus.CurrentVersion)") | Out-Null
		}

		# Trigger update if configured to do so.
		If ($Config.update.auto_update) {

			# Copy update script out of working directory.
			Copy-Item $PSScriptRoot\Updater.ps1 $PSScriptRoot\..\VDNotifs-Updater.ps1
			Unblock-File $PSScriptRoot\..\VDNotifs-Updater.ps1

			# Run update script.
			$updateArgs = "-file $PSScriptRoot\..\VDNotifs-Updater.ps1", "-LatestVersion $($updateStatus.LatestStable)"
			Start-Process -FilePath 'powershell' -Verb runAs -ArgumentList $updateArgs -WindowStyle hidden
		}
	}
}
catch {
	Write-LogMessage -Tag 'ERROR' -Message 'A terminating error occured:'
	$vbrSessionLogger.UpdateErr($logId_start, '[VeeamNotify] An error occured.', "Please check the log: $Logfile") | Out-Null
	$_
}
finally {
	# Stop logging.
	If ($Config.logging.enabled) {
		Stop-Logging
	}
}
