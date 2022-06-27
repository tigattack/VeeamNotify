param(
	[String]$InstallParentPath = 'C:\VeeamScripts'
)

# Function to be used when an error is encountered
function DeploymentError {
	$issues = 'https://github.com/tigattack/VeeamNotify/issues'

	Write-Output "An error occured $($_.ScriptStackTrace.Split("`n")[0]): $($_.Exception.Message)"
	Write-Output "`nPlease raise an issue at $issues"

	$launchIssuesPrompt_yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Open a new issue'
	$launchIssuesPrompt_no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Do nothing'
	$launchIssuesPrompt_opts = [System.Management.Automation.Host.ChoiceDescription[]]($launchIssuesPrompt_Yes, $launchIssuesPrompt_No)
	$launchIssuesPrompt_result = $host.UI.PromptForChoice('Open a new issue', 'Do you wish to open the new issue page in your browser?', $launchIssuesPrompt_opts, -1)

	If ($launchIssuesPrompt_result -eq 1) {
		Start-Process "$issues/new?assignees=tigattack&labels=bug&template=bug_report.yml&title=[BUG]+Veeam%20configuration%20deployment%20error"
	}
}

# Post-job script for VeeamNotify
# Get PowerShell path
try {
	$powershellExePath = (Get-Command -Name 'powershell.exe' -ErrorAction Stop).Path
}
catch {
	DeploymentError
}

$newPostScriptCmd = "$powershellExePath -ExecutionPolicy Bypass -File $(Join-Path -Path "$InstallParentPath" -ChildPath 'VeeamNotify\Bootstrap.ps1')"

# Import Veeam module
Import-Module Veeam.Backup.PowerShell -DisableNameChecking

# Get all supported jobs
$backupJobs = Get-VBRJob -WarningAction SilentlyContinue | Where-Object {
	$_.JobType -in 'Backup', 'Replica', 'EpAgentBackup'
} | Sort-Object -Property Name, Type

# Make sure we found some jobs
if ($backupJobs.Count -eq 0) {
	Write-Output 'No supported jobs found; Exiting.'
	Start-Sleep 10
	exit
}
else {
	Write-Output "Found $($backupJobs.count) supported jobs:"
	$backupJobs | Format-Table -Property Name, @{Name = 'Type'; Expression = { $_.TypeToString } } -AutoSize
}

# Query config backup
$backupChoice_yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Create a Veeam configuration backup.'
$backupChoice_no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Do not create a Veeam configuration backup.'
$backupChoice_opts = [System.Management.Automation.Host.ChoiceDescription[]]($backupChoice_yes, $backupChoice_no)
$backupChoice_message = 'This script can create a Veeam configuration backup for you before making any changes. Do you want to create a backup now?'
$backupChoice_result = $host.UI.PromptForChoice('Veeam Configuration Backup', $backupChoice_message, $backupChoice_opts, 0)

If ($backupChoice_result -eq 0) {
	# Run backup
	Write-Output "`nCreating backup, please wait..."
	($backupResult = Start-VBRConfigurationBackupJob) | Out-Null
	if ($backupResult.Result -ne 'Failed') {
		Write-Output 'Backup completed successfully.'
	}
	else {
		$continueChoice_yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Continue anyway.'
		$continueChoice_no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Exit now.'
		$continueChoice_opts = [System.Management.Automation.Host.ChoiceDescription[]]($continueChoice_yes, $continueChoice_no)
		$continueChoice_result = $host.UI.PromptForChoice('Backup Failed', 'Do you want to continue anyway', $continueChoice_opts, -1)

		if ($continueChoice_result -eq 1) {
			Write-Output 'Exiting.'
			Start-Sleep 10
			exit
		}
		else {
			Write-Output 'Continuing anyway.'
		}
	}
}

# Query configure all or selected jobs
$configChoice_all = New-Object System.Management.Automation.Host.ChoiceDescription '&All', 'Configure all supported jobs automatically.'
$configChoice_decide = New-Object System.Management.Automation.Host.ChoiceDescription '&Decide', 'Make a decision for each job.'
$configChoice_none = New-Object System.Management.Automation.Host.ChoiceDescription '&None', 'Do not configure any jobs.'
$configChoice_opts = [System.Management.Automation.Host.ChoiceDescription[]]($configChoice_all, $configChoice_decide, $configChoice_none)
$configChoice_message = 'Do you wish to configure all supported jobs, make a decision for each job, or configure none?'
$configChoice_result = $host.UI.PromptForChoice('Job Configuration Selection', $configChoice_message, $configChoice_opts, 0)

If ($configChoice_result -eq 1) {
	# Run foreach loop for all found backup jobs
	foreach ($job in $backupJobs) {
		# Set name string
		$jobName = "`"$($job.Name)`""

		# Get post-job script options for job
		$jobOptions = $job.GetOptions()
		$postScriptEnabled = $jobOptions.JobScriptCommand.PostScriptEnabled
		$postScriptCmd = $jobOptions.JobScriptCommand.PostScriptCommandLine

		# Check if job is already configured for VeeamNotify
		if ($postScriptCmd.EndsWith('\Bootstrap.ps1') -or $postScriptCmd.EndsWith("\Bootstrap.ps1'")) {

			# Check if job has full PowerShell.exe path
			if ($postScriptCmd.StartsWith('powershell.exe', 'CurrentCultureIgnoreCase')) {
				Write-Output "`n$($jobName) is already configured for VeeamNotify, but does not have a full path to Powershell. Updating..."
				try {
					# Replace Powershell.exe with full path in a new variable for update.
					$PostScriptFullPSPath = $postScriptCmd -replace 'Powershell.exe', 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
					# Set job to use modified post script path
					$jobOptions.JobScriptCommand.PostScriptCommandLine = $PostScriptFullPSPath
					Set-VBRJobOptions -Job $job -Options $jobOptions | Out-Null

					Write-Output "$($jobName) is now updated."
					Continue
				}
				catch {
					DeploymentError
				}
			}

			# skip if all correct
			else {
				Write-Output "`n$($jobName) is already configured for VeeamNotify; Skipping."
				Continue
			}
		}

		# Different actions whether post-job script is already enabled. If yes we ask to modify it, if not we ask to enable & set it.
		if ($postScriptEnabled) {
			Write-Output "`n$($jobName) has an existing post-job script.`nScript: $postScriptCmd"
			Write-Output "`nIf you wish to receive notifications for this job, you must overwrite the existing post-job script."

			$overwriteCurrentCmd_yes = New-Object System.Management.Automation.Host.ChoiceDescription '&yes', 'Overwrite the current post-job script.'
			$overwriteCurrentCmd_no = New-Object System.Management.Automation.Host.ChoiceDescription '&no', 'Skip configuration of this job, leaving it as-is.'
			$overwriteCurrentCmd_opts = [System.Management.Automation.Host.ChoiceDescription[]]($overwriteCurrentCmd_yes, $overwriteCurrentCmd_no)
			$overwriteCurrentCmd_result = $host.UI.PromptForChoice('Overwrite Job Configuration', 'Do you wish to overwrite the existing post-job script?', $overwriteCurrentCmd_opts, -1)

			switch ($overWriteCurrentCmd_result) {
				# Overwrite current post-job script
				0 {
					try {
						# Check to see if the script has even changed
						if ($postScriptCmd -ne $newPostScriptCmd) {

							# Script is not the same. Update the script command line.
							$jobOptions.JobScriptCommand.PostScriptCommandLine = $newPostScriptCmd
							Set-VBRJobOptions -Job $job -Options $jobOptions | Out-Null

							Write-Output "Updated post-job script for job $($jobName).`nOld: $postScriptCmd`nNew: $newPostScriptCmd"
							Write-Output "$($jobName) is now configured for VeeamNotify."
						}
						else {
							# Script hasn't changed. Notify user of this and continue.
							Write-Output "$($jobName) is already configured for VeeamNotify; Skipping."
						}
					}
					catch {
						DeploymentError
					}
				}
				# Skip configuration of this job
				1 { Write-Output "`nSkipping job $($jobName)`n" }
				# Default action will be to skip the job.
				default { Write-Output "`nSkipping job $($jobName)`n" }
			}
		}
		else {
			$setNewPostScript_yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Configure this job to send notifications.'
			$setNewPostScript_no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Skip configuration of this job, leaving it as-is.'
			$setNewPostScript_opts = [System.Management.Automation.Host.ChoiceDescription[]]($setNewPostScript_yes, $setNewPostScript_no)
			$setNewPostScript_message = "Do you wish to receive notifications for $($jobName) ($($job.TypeToString))?"
			$setNewPostScript_result = $host.UI.PromptForChoice('Configure Job', $setNewPostScript_message, $setNewPostScript_opts, -1)

			Switch ($setNewPostScript_result) {
				# Overwrite current post-job script
				0 {
					try {
						# Sets post-job script to Enabled and sets the command line to full command including path.
						$jobOptions.JobScriptCommand.PostScriptEnabled = $true
						$jobOptions.JobScriptCommand.PostScriptCommandLine = $newPostScriptCmd
						Set-VBRJobOptions -Job $job -Options $jobOptions | Out-Null

						Write-Output "`n$($jobName) is now configured for VeeamNotify."
					}
					catch {
						DeploymentError
					}
				}
				# Skip configuration of this job
				1 { Write-Output "`nSkipping job $($jobName)`n" }
				# Default action will be to skip the job.
				default { Write-Output "`nSkipping job $($jobName)`n" }
			}
		}
	}
}

elseif ($configChoice_result -eq 0) {
	# Run foreach loop for all found backup jobs
	foreach ($job in $backupJobs) {
		# Set name string
		$jobName = "`"$($job.Name)`""

		# Get post-job script options for job
		$jobOptions = $job.GetOptions()
		$postScriptEnabled = $jobOptions.JobScriptCommand.PostScriptEnabled
		$postScriptCmd = $jobOptions.JobScriptCommand.PostScriptCommandLine

		# Check if job is already configured for VeeamNotify
		if ($postScriptCmd.EndsWith('\Bootstrap.ps1') -or $postScriptCmd.EndsWith("\Bootstrap.ps1'")) {

			# Check if job has full PowerShell.exe path
			if ($postScriptCmd.StartsWith('powershell.exe', 'CurrentCultureIgnoreCase')) {
				Write-Output "`n$($jobName) is already configured for VeeamNotify, but does not have a full path to Powershell. Updating..."
				try {
					# Replace Powershell.exe with full path in a new variable for update.
					$PostScriptFullPSPath = $postScriptCmd -replace 'Powershell.exe', 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
					# Set job to use modified post script path
					$jobOptions.JobScriptCommand.PostScriptCommandLine = $PostScriptFullPSPath
					Set-VBRJobOptions -Job $job -Options $jobOptions | Out-Null

					Write-Output "$($jobName) is now updated."
					Continue
				}
				catch {
					DeploymentError
				}
			}

			# skip if all correct
			else {
				Write-Output "`n$($jobName) is already configured for VeeamNotify; Skipping."
				Continue
			}
		}

		# Different actions whether post-job script is already enabled. If yes we ask to modify it, if not we ask to enable & set it.
		if ($postScriptEnabled) {
			Write-Output "`n$($jobName) has an existing post-job script.`nScript: $postScriptCmd"
			Write-Output "`nIf you wish to receive notifications for this job, you must overwrite the existing post-job script."

			try {
				# Check to see if the script has even changed
				if ($postScriptCmd -ne $newPostScriptCmd) {

					# Script is not the same. Update the script command line.
					$jobOptions.JobScriptCommand.PostScriptCommandLine = $newPostScriptCmd
					Set-VBRJobOptions -Job $job -Options $jobOptions | Out-Null

					Write-Output "Updated post-job script for job $($jobName).`nOld: $postScriptCmd`nNew: $newPostScriptCmd"
					Write-Output "$($jobName) is now configured for VeeamNotify."
				}
				else {
					# Script hasn't changed. Notify user of this and continue.
					Write-Output "$($jobName) is already configured for VeeamNotify; Skipping."
				}
			}
			catch {
				DeploymentError
			}
		}
		else {
			try {
				# Sets post-job script to Enabled and sets the command line to full command including path.
				$jobOptions.JobScriptCommand.PostScriptEnabled = $true
				$jobOptions.JobScriptCommand.PostScriptCommandLine = $newPostScriptCmd
				Set-VBRJobOptions -Job $job -Options $jobOptions | Out-Null

				Write-Output "`n$($jobName) is now configured for VeeamNotify."
			}
			catch {
				DeploymentError
			}
		}
	}
}

elseif ($configChoice_result -eq 2) {
	Write-Output 'Skipping VeeamNotify configuration deployment for all jobs.'
}

If ($MyInvocation.ScriptName -notlike '*Installer.ps1') {
	Write-Output "`n`Finished. Exiting."
	Start-Sleep 10
}

exit
