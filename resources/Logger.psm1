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

	$time = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')

	If ($PSCmdlet.ShouldProcess('Output stream', 'Write log message')) {
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
