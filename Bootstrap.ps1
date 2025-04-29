# Import modules
Import-Module Veeam.Backup.PowerShell -DisableNameChecking
Import-Module "$PSScriptRoot\resources\Logger.psm1"
Import-Module "$PSScriptRoot\resources\JsonValidator.psm1"
Import-Module "$PSScriptRoot\resources\VBRSessionInfo.psm1"

# Set vars
$configFile = "$PSScriptRoot\config\conf.json"
$date = (Get-Date -UFormat %Y-%m-%d_%T).Replace(':', '.')
$logFile = "$PSScriptRoot\log\$($date)_Bootstrap.log"
$idRegex = '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}'
$supportedTypes = 'Backup', 'EpAgentBackup', 'Replica', 'BackupToTape', 'FileToTape'

# Start logging to file
Start-Logging -Path $logFile

# Log version
Write-LogMessage -Tag 'INFO' -Message "Version: $(Get-Content "$PSScriptRoot\resources\version.txt" -Raw)"

# Retrieve configuration.
## Pull config to PSCustomObject
$config = Get-Content -Raw $configFile | ConvertFrom-Json # TODO: import config from param instead of later as file. Can then improve logging flow.

# Stop logging and remove log file if logging is disable in config.
if (-not $config.logging.enabled) {
	Stop-Logging
	Remove-Item $logFile -Force -ErrorAction SilentlyContinue
}

## Pull raw config and format for later.
## This is necessary since $config as a PSCustomObject was not passed through correctly with Start-Process and $powershellArguments.
$configRaw = (Get-Content -Raw $configFile).Replace('"', '\"').Replace("`n", '').Replace("`t", '').Replace('  ', ' ')

## Test config.
$validationResult = Test-JsonValid -JsonPath $configFile -SchemaPath "$PSScriptRoot\config\schema.json"
if ($validationResult.IsValid) {
	Write-LogMessage -Tag 'INFO' -Message 'Configuration validated successfully.'
}
else {
	Write-LogMessage -Tag 'ERROR' -Message "Failed to validate configuration: $($validationResult.Message)"
}

# Get the command line used to start the Veeam session.
$parentPid = (Get-CimInstance Win32_Process -Filter "processid='$PID'").parentprocessid.ToString()
$parentCmd = (Get-CimInstance Win32_Process -Filter "processid='$parentPID'").CommandLine

# Get the Veeam job and session IDs
$jobId = ([regex]::Matches($parentCmd, $idRegex)).Value[0]
$sessionId = ([regex]::Matches($parentCmd, $idRegex)).Value[1]

# Get the Veeam job details and hide warnings to mute the warning regarding deprecation of the use of some cmdlets to get certain job type details.
# At time of writing, there is no alternative way to discover the job time.
Write-LogMessage -Tag 'INFO' -Message 'Getting VBR job details'
$job = Get-VBRJob -WarningAction SilentlyContinue | Where-Object {$_.Id.Guid -eq $jobId}
if (!$job) {
	# Can't locate non tape job so check if it's a tape job
	$job = Get-VBRTapeJob -WarningAction SilentlyContinue | Where-Object {$_.Id.Guid -eq $jobId}
	$JobType = $job.Type
}
else {
	$JobType = $job.JobType
}


# Get the session information and name.
Write-LogMessage -Tag 'INFO' -Message 'Getting VBR session information'
$sessionInfo = Get-VBRSessionInfo -SessionId $sessionId -JobType $JobType
$jobName = $sessionInfo.JobName
$vbrSessionLogger = $sessionInfo.Session.Logger

$vbrLogEntry = $vbrSessionLogger.AddLog('[VeeamNotify] Parsing job & session information...')

# Quit if job type is not supported.
if ($JobType -notin $supportedTypes) {
	Write-LogMessage -Tag 'ERROR' -Message "Job type '$($JobType)' is not supported."
	exit 1
}

Write-LogMessage -Tag 'INFO' -Message "Bootstrap script for Veeam job '$jobName' (job $jobId session $sessionId) - Session & job detection complete."

# Set log file name based on job
## Replace spaces if any in the job name
if ($jobName -match ' ') {
	$logJobName = $jobName.Replace(' ', '_')
}
else {
	$logJobName = $jobName
}
$newLogfile = "$PSScriptRoot\log\$($date)-$($logJobName).log"

# Build argument string for the alert sender script.
$powershellArguments = "-NoProfile -File $PSScriptRoot\AlertSender.ps1", `
	"-SessionId `"$sessionId`"", `
	"-JobType `"$JobType`"", `
	"-Config `"$configRaw`"", `
	"-Logfile `"$newLogfile`""

$vbrSessionLogger.UpdateSuccess($vbrLogEntry, '[VeeamNotify] Parsed job & session information.') | Out-Null

# Start a new new script in a new process with some of the information gathered here.
# This allows Veeam to finish the current session faster and allows us gather information from the completed job.
try {
	$powershellExePath = (Get-Command -Name 'powershell.exe' -ErrorAction Stop).Path
	Write-LogMessage -Tag 'INFO' -Message 'Launching AlertSender.ps1...'
	$vbrLogEntry = $vbrSessionLogger.AddLog('[VeeamNotify] Launching Alert Sender...')
	Start-Process -FilePath "$powershellExePath" -Verb runAs -ArgumentList $powershellArguments -WindowStyle hidden -ErrorAction Stop
	Write-LogMessage -Tag 'INFO' -Message 'AlertSender.ps1 launched successfully.'
	$vbrSessionLogger.UpdateSuccess($vbrLogEntry, '[VeeamNotify] Launched Alert Sender.') | Out-Null
}
catch {
	Write-LogMessage -Tag 'ERROR' -Message "Failed to launch AlertSender.ps1: $_"
	$vbrSessionLogger.UpdateErr($vbrLogEntry, '[VeeamNotify] Failed to launch Alert Sender.', "Please check the log: $newLogfile") | Out-Null
	exit 1
}

# Stop logging.
if ($config.logging.enabled) {
	Stop-Logging

	# Rename log file to include the job name.
	try {
		Rename-Item -Path $logFile -NewName "$(Split-Path $newLogfile -Leaf)"
	}
	catch {
		Write-Output "ERROR: Failed to rename log file: $_" | Out-File $logFile -Append
	}
}
