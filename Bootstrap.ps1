# Import modules
Import-Module Veeam.Backup.PowerShell -DisableNameChecking
Import-Module "$PSScriptRoot\resources\Logger.psm1"
Import-Module "$PSScriptRoot\resources\VBRSessionInfo.psm1"

# Set vars
$configFile = "$PSScriptRoot\config\conf.json"
$date = (Get-Date -UFormat %Y-%m-%d_%T).Replace(':','.')
$logFile = "$PSScriptRoot\log\$($date)_Bootstrap.log"
$idRegex = '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}'
$supportedTypes = 'Backup', 'EpAgentBackup','Replica'

# Start logging to file
Start-Logging -Path $logFile

# Log version
Write-LogMessage -Tag 'INFO' -Message "Version: $(Get-Content "$PSScriptRoot\resources\version.txt" -Raw)"

# Retrieve configuration.
## Pull config to PSCustomObject
$config = Get-Content -Raw $configFile | ConvertFrom-Json # TODO: import config from param instead of later as file. Can then improve logging flow.

# Stop logging and remove log file if logging is disable in config.
If (-not $config.debug_log) {
	Stop-Logging
	Remove-Item $logFile -Force -ErrorAction SilentlyContinue
}

## Pull raw config and format for later.
## This is necessary since $config as a PSCustomObject was not passed through correctly with Start-Process and $powershellArguments.
$configRaw = (Get-Content -Raw $configFile).Replace('"','\"').Replace("`n",'').Replace("`t",'').Replace('  ',' ')

## Test config.
Try {
	$configSchema = Get-Content -Raw "$PSScriptRoot\config\conf.schema.json" | ConvertFrom-Json
	foreach ($i in $configSchema.required) {
		If (-not (Get-Member -InputObject $config -Name "$i" -Membertype NoteProperty)) {
			throw "Required configuration property is missing. Property: $i"
		}
	}
}
Catch {
	Write-LogMessage -Tag 'ERROR' -Message "Failed to validate configuration: $_"
}

# Get the command line used to start the Veeam session.
$parentPid = (Get-CimInstance Win32_Process -Filter "processid='$PID'").parentprocessid.ToString()
$parentCmd = (Get-CimInstance Win32_Process -Filter "processid='$parentPID'").CommandLine

# Get the Veeam job and session IDs
$jobId = ([regex]::Matches($parentCmd, $idRegex)).Value[0]
$sessionId = ([regex]::Matches($parentCmd, $idRegex)).Value[1]

# Get the Veeam job details and hide warnings to mute the warning regarding deprecation of the use of some cmdlets to get certain job type details.
# At time of writing, there is no alternative way to discover the job time.
$job = Get-VBRJob -WarningAction SilentlyContinue | Where-Object {$_.Id.Guid -eq $jobId}

# Quit if job type is not supported.
If ($job.JobType -notin $supportedTypes) {
	Write-LogMessage -Tag 'ERROR' -Message "Job type '$($job.JobType)' is not supported."
	Exit 1
}

# Get the session information and name.
$sessionInfo = Get-VBRSessionInfo -SessionID $sessionId -JobType $job.JobType
$jobName = $sessionInfo.JobName

Write-LogMessage -Tag 'INFO' -Message "Bootstrap script for Veeam job '$jobName' (job $jobId session $sessionId) - Session & job detection complete."

# Set log file name based on job
## Replace spaces if any in the job name
If ($jobName -match ' ') {
	$logJobName = $jobName.Replace(' ', '_')
}
Else {
	$logJobName = $jobName
}
$newLogfile = "$PSScriptRoot\log\$($date)-$($logJobName).log"

# Build argument string for the alert sender script.
$powershellArguments = "-file $PSScriptRoot\AlertSender.ps1", "-JobName `"$jobName`"", "-Id `"$sessionId`"","-JobType `"$($job.JobType)`"", `
	"-Config `"$($configRaw)`"", "-Logfile `"$newLogfile`""

# Start a new new script in a new process with some of the information gathered here.
# This allows Veeam to finish the current session faster and allows us gather information from the completed job.
Start-Process -FilePath 'powershell' -Verb runAs -ArgumentList $powershellArguments -WindowStyle hidden

# Stop logging.
If ($config.debug_log) {
	Stop-Logging

	# Rename log file to include the job name.
	Try {
		Rename-Item -Path $logFile -NewName "$(Split-Path $newLogfile -Leaf)"
	}
	Catch {
		Write-LogMessage -Tag 'ERROR' -Message "Failed to rename log file: $_"
	}
}
