Function Get-VBRSessionInfo {
	param (
		[Parameter(Mandatory=$true)]$SessionId,
		[Parameter(Mandatory=$true)]$JobType
	)

	# Import VBR module
	Import-Module Veeam.Backup.PowerShell -DisableNameChecking

	If (($null -ne $SessionId) -and ($null -ne $JobType)) {

		# Switch on job type.
		Switch ($JobType) {

			# VM job
			{$_ -in 'Backup','Replica'} {

				# Get the session details.
				$session = Get-VBRBackupSession | Where-Object {$_.Id.Guid -eq $SessionId}

				# Get the job's name from the session details.
				$jobName = $session.Name
			}

			# Agent job
			{$_ -eq 'EpAgentBackup'} {
				# Fetch current session to load .NET module
                # It appears some of the underlying .NET items are lazy-loaded, so this is necessary
                # to load in whatever's required to utilise the GetByOriginalSessionId method.
                # See https://forums.veeam.com/powershell-f26/want-to-capture-running-jobs-by-session-type-i-e-sobr-tiering-t75583.html#p486295
				Get-VBRSession -Id $SessionId | Out-Null
				# Get the session details.
				$session = [Veeam.Backup.Core.CBackupSession]::GetByOriginalSessionId($SessionId)

				# Copy the job's name to it's own variable.
				$jobName = $job.Info.Name
			}
		}

		# Create PSObject to return.
		New-Object PSObject -Property @{
			Session = $session
			JobName = $jobName
		}
	}

	Elseif ($null -eq $SessionId) {
		Write-LogMessage -Tag 'WARN' -Message 'SessionId is null.'
	}

	Elseif ($null -eq $JobType) {
		Write-LogMessage -Tag 'WARN' -Message 'JobType is null.'
	}
}
