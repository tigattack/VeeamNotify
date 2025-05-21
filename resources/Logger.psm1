# This function log messages with a type tag
function Write-LogMessage {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'Low'
	)]
	param (
		[ValidateSet('Debug', 'Info', 'Warn', 'Error')]
		[Parameter(Mandatory)]
		[String]$Tag,
		[Parameter(Mandatory)]
		$Message,
		[switch]$FirstLog
	)

	# Get current timestamp
	$time = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')

	# Creates hash table with severities
	$Severities = @{
		Error = 1
		Warn  = 2
		Info  = 3
		Debug = 4
	}

	# Pull config if necessary to correlate logging level
	if (-not (Get-Variable -Name 'config' -ErrorAction SilentlyContinue)) {
		$configPath = Split-Path $PSScriptRoot -Parent | Join-Path -ChildPath 'config\conf.json'
		$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
	}

	# If config is not found, default to info
	if ($config.logging.level -notin $Severities.Keys) {
		# Set if property exists
		if ($config.logging | Get-Member -Name level) {
			$config.logging.level = 'Info'
		}
		# Otherwise add property
		else {
			$config.logging | Add-Member -MemberType NoteProperty -Name level -Value 'Info'
		}

		# Warn if this is the first log entry
		if ($FirstLog) {
			Write-Output "$time [WARNING] Logging level unset or set incorrectly in config.json. Defaulting to info level."
		}
	}

	# Gets correct severity integer dependant on Tag.
	$Severity = $Severities[$Tag]

	# Gets correct severity integer dependant on severity in config.
	$ConfigSeverity = $Severities[$config.logging.level]

	if (($PSCmdlet.ShouldProcess('Output stream', 'Write log message')) -and ($ConfigSeverity -ge $Severity)) {
		Write-Output "$time [$($Tag.ToUpper())] $Message"
	}
}

# These functions handle the initiation and termination of transcript logging.
function Start-Logging {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'Low'
	)]
	param(
		[Parameter(Mandatory)]
		[String]$Path
	)
	if ($PSCmdlet.ShouldProcess($Path, 'Start-Transcript')) {
		try {
			Start-Transcript -Path $Path -Force -Append | Out-Null
			Write-LogMessage -Tag 'INFO' -Message "Transcript is being logged to '$Path'." -FirstLog
		}
		catch [System.IO.IOException] {
			Write-LogMessage -Tag 'INFO' -Message "Transcript start attemped but transcript is already being logged to '$Path'."
		}
	}
}

function Stop-Logging {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'Low'
	)]
	param()
	if ($PSCmdlet.ShouldProcess('log file', 'Stop-Transcript')) {
		Write-LogMessage -Tag 'INFO' -Message 'Stopping transcript logging.'
		try {
			Stop-Transcript
		}
		catch {
			Write-LogMessage -Tag 'ERROR' -Message 'Failed to stop transcript logging.'
		}
	}
}

function Remove-OldLogs {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'Low'
	)]
	param(
		[Parameter(Mandatory)]
		[String]$Path,
		[Parameter(Mandatory)]
		[int]$MaxAgeDays
	)

	if ($PSCmdlet.ShouldProcess($Path, 'Remove expired log files')) {

		Write-LogMessage -Tag 'DEBUG' -Message "Searching for log files older than $MaxAgeDays days."

		$oldLogs = (Get-ChildItem $Path | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-$MaxAgeDays)})

		if ($($oldLogs.Count) -ne 0) {
			Write-LogMessage -Tag 'DEBUG' -Message "Found $($oldLogs.Count) log files to remove."
			try {
				$oldLogs | Remove-Item -Force -Verbose:$VerbosePreference
				Write-LogMessage -Tag 'INFO' -Message "Removed $($oldLogs.Count) expired log files."
			}
			catch {
				Write-LogMessage -Tag 'ERROR' -Message 'Failed to remove some/all log files.'
			}
		}
		else {
			Write-LogMessage -Tag 'DEBUG' -Message 'Found 0 logs files exceeding retention period.'
		}
	}
}
