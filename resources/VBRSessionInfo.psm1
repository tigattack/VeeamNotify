class VBRSessionInfo {
	[ValidateNotNullOrEmpty()][Veeam.Backup.Core.CBackupSession]$Session
	[ValidateNotNullOrEmpty()][string]$JobName
}

function Get-VBRSessionInfo {
	[OutputType([VBRSessionInfo])]
	param (
		[Parameter(Mandatory)][ValidateNotNullOrEmpty()]
		[string]$SessionId,
		[Parameter(Mandatory)][ValidateNotNullOrEmpty()]
		[string]$JobType
	)

	# Import VBR module
	Import-Module Veeam.Backup.PowerShell -DisableNameChecking

	switch ($JobType) {
		# VM job
		{$_ -in 'Backup', 'Replica'} {

			# Get the session details.
			$session = Get-VBRBackupSession | Where-Object {$_.Id.Guid -eq $SessionId}

			# Get the job's name from the session details.
			$jobName = $session.Name
		}

		# Agent or tape job
		{$_ -in 'EpAgentBackup', 'BackupToTape', 'FileToTape'} {
			# Fetch current session to load .NET module
			# It appears some of the underlying .NET items are lazy-loaded, so this is necessary
			# to load in whatever's required to utilise the GetByOriginalSessionId method.
			# See https://forums.veeam.com/powershell-f26/want-to-capture-running-jobs-by-session-type-i-e-sobr-tiering-t75583.html#p486295
			Get-VBRSession -Id $SessionId | Out-Null
			# Get the session details.
			$session = [Veeam.Backup.Core.CBackupSession]::GetByOriginalSessionId($SessionId)

			# Copy the job's name to it's own variable.
			if ($JobType -eq 'EpAgentBackup') {
				$jobName = $job.Info.Name
			}
			elseif ($JobType -in 'BackupToTape', 'FileToTape') {
				$jobName = $job.Name
			}
		}
	}

	# Create PSObject to return.
	return [VBRSessionInfo]@{
		Session = $session
		JobName = $jobName
	}
}
