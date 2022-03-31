# This function log messages with a type tag
Function Write-LogMessage {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'Low'
	)]
	Param (
		[ValidateSet('Debug', 'Info', 'Warn', 'Error')]
		[Parameter(Mandatory)]
		[String]$Tag,
		[Parameter(Mandatory)]
		$Message
	)
	# Reads config file to correlate log severity level.
	$config = Get-Content -Raw "$PSScriptRoot\..\config\conf.json" | ConvertFrom-Json
	# Creates hash table with severities
	$Severities = @{}
	$Severities.Error = 1
	$Severities.Warn = 2
	$Severities.Info = 3
	$Severities.Debug = 4
	# Gets correct severity integer dependant on Tag.
	$Severity = $Severities[$Tag]
	# Gets correct severity integer dependant on severity in config.
	$ConfigSeverity = $Severities[$config.log_severity]
	$time = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')

	If (($PSCmdlet.ShouldProcess('Output stream', 'Write log message')) -and ($ConfigSeverity -ge $Severity)) {
		Write-Output "$time [$($Tag.ToUpper())] $Message"
	}
}

# These functions handle the initiation and termination of transcript logging.
Function Start-Logging {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'Low'
	)]
	Param(
		[Parameter(Mandatory)]
		$Path,
		[Switch]
		$Append
	)
	If ($PSCmdlet.ShouldProcess($Path, 'Start-Transcript')) {
		Try {
			Start-Transcript -Path $Path -Force -Append | Out-Null
			Write-LogMessage -Tag 'INFO' -Message "Transcript is being logged to '$Path'."
		}
		Catch [System.IO.IOException] {
			Write-LogMessage -Tag 'INFO' -Message "Transcript start attemped but transcript is already being logged to '$Path'."
		}
	}
}

Function Stop-Logging {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'Low'
	)]
	Param()
	If ($PSCmdlet.ShouldProcess('log file', 'Stop-Transcript')) {
		Write-LogMessage -Tag 'INFO' -Message 'Stopping transcript logging.'
		Stop-Transcript
	}
}

Function Remove-OldLogs {
	[CmdletBinding(
		SupportsShouldProcess,
		ConfirmImpact = 'Low'
	)]
	Param(
		[Parameter(Mandatory)]
		[String]$Path,
		[Parameter(Mandatory)]
		[int]$MaximumAgeDays
	)

	If ($PSCmdlet.ShouldProcess($Path, 'Remove expired log files')) {

		Write-LogMessage -Tag 'DEBUG' -Message "Searching for log files older than $MaximumAgeDays days."

		$oldLogs = (Get-ChildItem $Path | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-$Config.log_expiry_days)})

		if ($($oldLogs.Count) -ne 0) {
			Write-LogMessage -Tag 'DEBUG' -Message "Found $($oldLogs.Count) log files to remove."
			Try {
				$oldLogs | Remove-Item -Force -Verbose:$VerbosePreference
				Write-LogMessage -Tag 'INFO' -Message "Removed $($oldLogs.Count) expired log files."
			}
			Catch {
				Write-LogMessage -Tag 'ERROR' -Message 'Failed to remove some/all log files.'
			}
		}
		else {
			Write-LogMessage -Tag 'DEBUG' -Message 'Found 0 logs files exceeding retention period.'
		}
	}
}
