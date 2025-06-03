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
		[string]$JobType,
		[Parameter(Mandatory)][ValidateNotNullOrEmpty()]
		[string]$JobId
	)

	# Import VBR module
	Import-Module Veeam.Backup.PowerShell -DisableNameChecking

	switch ($JobType) {
		# VM job
		{$_ -in 'Backup', 'Replica'} {

			# Get the session details.
			$session = Get-VBRBackupSession -Id $SessionId

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
			$session = [Veeam.Backup.Core.CBackupSession]::GetByJob($JobId) | Select-Object -Last 1

			if ($null -eq $session) {
				throw "$JobType job session with ID '$SessionId' could not be found."
			}

			# Extract the job name from the session
			$jobName = $session.Name
		}
	}

	# Create PSObject to return.
	return [VBRSessionInfo]@{
		Session = $session
		JobName = $jobName
	}
}
