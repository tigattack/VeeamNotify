param(
	[String]$InstallParentPath = 'C:\VeeamScripts'
)

# Function to be used when an error is encountered
function DeploymentError {
	$issues = 'https://github.com/tigattack/VeeamNotify/issues'

	Write-Host -ForegroundColor Red "An error occured $($_.ScriptStackTrace.Split("`n")[0]): $($_.Exception.Message)"
	Write-Host "`nPlease raise an issue at $issues"

	$launchIssuesPrompt_yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Open a new issue'
	$launchIssuesPrompt_no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Do nothing'
	$launchIssuesPrompt_opts = [System.Management.Automation.Host.ChoiceDescription[]]($launchIssuesPrompt_yes, $launchIssuesPrompt_no)
	$launchIssuesPrompt_result = $host.UI.PromptForChoice('Open a new issue', 'Do you wish to open the new issue page in your browser?', $launchIssuesPrompt_opts, -1)

	if ($launchIssuesPrompt_result -eq 0) {
		Start-Process "$issues/new?assignees=tigattack&labels=bug&template=bug_report.yml&title=[BUG]+Veeam%20configuration%20deployment%20error"
	}
	exit 1
}

function Set-VeeamJobOptions {
	param(
		[Parameter(Mandatory)]$Job,
		[Parameter(Mandatory)]$Options
	)

	try {
		# Agent jobs require their own cmdlet
		if ($Job.JobType -eq 'EpAgentBackup') {
			Set-VBRComputerBackupJob -Job $Job -ScriptOptions $Options.JobScriptCommand | Out-Null
		}
		else {
			# For 'regular' (e.g. backup, replica) jobs
			Set-VBRJobOptions -Job $Job -Options $Options | Out-Null
		}
	}
	catch {
		DeploymentError
	}
}

function New-PromptChoice {
	param(
		[string]$Label,
		[string]$HelpMessage
	)

	return New-Object System.Management.Automation.Host.ChoiceDescription $Label, $HelpMessage
}

function Show-Prompt {
	param(
		[string]$Title,
		[string]$Message,
		[System.Management.Automation.Host.ChoiceDescription[]]$Choices,
		[int]$DefaultOption = -1
	)

	return $host.UI.PromptForChoice($Title, $Message, $Choices, $DefaultOption)
}

function Update-JobWithFullPowershellPath {
	param(
		[Parameter(Mandatory)]$Job,
		[string]$PowershellPath,
		[string]$PostScriptCmd
	)

	$jobName = "'$($Job.Name)'"
	Write-Host -ForegroundColor Yellow "`n$($jobName) is already configured for VeeamNotify, but does not have a full path to Powershell. Updating..."

	try {
		$jobOptions = $Job.GetOptions()
		# Replace Powershell.exe with full path in a new variable for update.
		$PostScriptFullPSPath = $PostScriptCmd -replace 'Powershell.exe', "$PowershellPath"
		# Set job to use modified post script path
		$jobOptions.JobScriptCommand.PostScriptCommandLine = $PostScriptFullPSPath
		$null = Set-VeeamJobOptions -Job $Job -Options $jobOptions

		Write-Host -ForegroundColor Green "$($jobName) is now updated."
	}
	catch {
		DeploymentError
	}
}

function Update-ExistingPostScript {
	param(
		[Parameter(Mandatory)]$Job,
		[string]$NewPostScriptCmd,
		[string]$CurrentPostScriptCmd,
		[bool]$AskBeforeOverwriting = $true
	)

	$jobName = "'$($Job.Name)'"
	Write-Host -ForegroundColor Yellow "`n$jobName has an existing post-job script:"
	Write-Host $CurrentPostScriptCmd

	$shouldUpdate = $true

	if ($AskBeforeOverwriting) {
		Write-Host "`nIf you wish to receive notifications for this job, you must overwrite the existing post-job script."

		$overwriteYes = New-PromptChoice -Label '&Yes' -HelpMessage 'Overwrite the current post-job script.'
		$overwriteNo = New-PromptChoice -Label '&No' -HelpMessage 'Skip configuration of this job, leaving it as-is.'
		$overwriteOptions = @($overwriteYes, $overwriteNo)

		$overwriteResult = Show-Prompt -Title 'Overwrite Job Configuration' -Message 'Do you wish to overwrite the existing post-job script?' -Choices $overwriteOptions -DefaultOption 1

		switch ($overwriteResult) {
			0 { $shouldUpdate = $true }
			1 {
				$shouldUpdate = $false
				Write-Host "`nSkipping job $($jobName)`n"
			}
		}
	}
	else {
		$shouldUpdate = $true
	}

	if ($shouldUpdate) {
		try {
			# Check to see if the script has even changed
			if ($CurrentPostScriptCmd -ne $NewPostScriptCmd) {
				# Script is not the same. Update the script command line.
				$jobOptions = $Job.GetOptions()
				$jobOptions.JobScriptCommand.PostScriptCommandLine = $NewPostScriptCmd
				Set-VeeamJobOptions -Job $Job -Options $jobOptions

				Write-Host "Updated post-job script for job $($jobName).`nOld: $CurrentPostScriptCmd`nNew: $NewPostScriptCmd"
				Write-Host -ForegroundColor Green "$($jobName) is now configured for VeeamNotify."
			}
			else {
				# Script hasn't changed. Notify user of this and continue.
				Write-Host -ForegroundColor Yellow "$($jobName) is already configured for VeeamNotify; Skipping."
			}
		}
		catch {
			DeploymentError
		}
	}
}

function Enable-PostScript {
	param(
		[Parameter(Mandatory)]$Job,
		[string]$NewPostScriptCmd,
		[bool]$AskBeforeEnabling = $true
	)

	$jobName = "'$($Job.Name)'"

	if ($AskBeforeEnabling) {
		$setNewYes = New-PromptChoice -Label '&Yes' -HelpMessage 'Configure this job to send notifications.'
		$setNewNo = New-PromptChoice -Label '&No' -HelpMessage 'Skip configuration of this job, leaving it as-is.'
		$setNewOptions = @($setNewYes, $setNewNo)

		$setNewMessage = "Do you wish to receive notifications for this job?"
		$setNewResult = Show-Prompt -Title "Configure $jobName ($($Job.TypeToString))" -Message $setNewMessage -Choices $setNewOptions

		switch ($setNewResult) {
			0 { $shouldEnable = $true }
			1 {
				$shouldEnable = $false
				Write-Host "`nSkipping job $($jobName)`n"
			}
		}
	}
	else {
		$shouldEnable = $true
	}

	if ($shouldEnable) {
		try {
			# Sets post-job script to Enabled and sets the command line to full command including path.
			$jobOptions = $Job.GetOptions()
			$jobOptions.JobScriptCommand.PostScriptEnabled = $true
			$jobOptions.JobScriptCommand.PostScriptCommandLine = $NewPostScriptCmd
			Set-VeeamJobOptions -Job $Job -Options $jobOptions

			Write-Host -ForegroundColor Green "`n$($jobName) is now configured for VeeamNotify."
		}
		catch {
			DeploymentError
		}
	}
}

function Set-BackupJobPostScript {
	param(
		[Parameter(Mandatory)]$Job,
		[string]$NewPostScriptCmd,
		[string]$PowershellPath,
		[bool]$AskBeforeConfiguring = $true
	)

	$jobName = "'$($Job.Name)'"

	# Get post-job script options for job
	$jobOptions = $Job.GetOptions()
	$postScriptEnabled = $jobOptions.JobScriptCommand.PostScriptEnabled
	$postScriptCmd = $jobOptions.JobScriptCommand.PostScriptCommandLine

	# Check if job is already configured for VeeamNotify
	if ($postScriptCmd -eq $NewPostScriptCmd) {
		# Check if job has full PowerShell.exe path
		if ($postScriptCmd.StartsWith('powershell.exe', 'CurrentCultureIgnoreCase')) {
			return Update-JobWithFullPowershellPath -Job $Job -PowershellPath $PowershellPath -PostScriptCmd $postScriptCmd
		}

		# skip if all correct
		Write-Host -ForegroundColor Yellow "`n$($jobName) is already configured for VeeamNotify; Skipping."
		return
	}

	# Different actions whether post-job script is already enabled
	if ($postScriptEnabled) {
		return Update-ExistingPostScript -Job $Job -NewPostScriptCmd $NewPostScriptCmd -CurrentPostScriptCmd $postScriptCmd -AskBeforeOverwriting $AskBeforeConfiguring
	}
	else {
		return Enable-PostScript -Job $Job -NewPostScriptCmd $NewPostScriptCmd -AskBeforeEnabling $AskBeforeConfiguring
	}
}

# Main script execution starts here

# Get PowerShell path
try {
	$powershellExePath = (Get-Command -Name 'powershell.exe' -ErrorAction Stop).Path
}
catch {
	DeploymentError
}

$newPostScriptCmd = "$powershellExePath -NoProfile -ExecutionPolicy Bypass -File $(Join-Path -Path "$InstallParentPath" -ChildPath 'VeeamNotify\Bootstrap.ps1')"

Write-Host "Importing Veeam module and discovering supported jobs, please wait...`n"

# Import Veeam module
Import-Module Veeam.Backup.PowerShell -DisableNameChecking

# Get all supported jobs
$backupJobs = Get-VBRJob -WarningAction SilentlyContinue | Where-Object {
	$_.JobType -in 'Backup', 'Replica', 'EpAgentBackup'
} | Sort-Object -Property Name, Type

# Make sure we found some jobs
if ($backupJobs.Count -eq 0) {
	Write-Host 'No supported jobs found; Exiting.'
	Start-Sleep 10
	exit
}
else {
	Write-Host "Found $($backupJobs.count) supported jobs:"
	$backupJobs | Format-Table -Property Name, @{Name = 'Type'; Expression = { $_.TypeToString } } -AutoSize
}

# Query config backup
$backupYes = New-PromptChoice -Label '&Yes' -HelpMessage 'Create a Veeam configuration backup.'
$backupNo = New-PromptChoice -Label '&No' -HelpMessage 'Do not create a Veeam configuration backup.'
$backupOptions = @($backupYes, $backupNo)
$backupMessage = "This script can create a Veeam configuration backup for you before making any changes.`nDo you want to create a backup now?"
$backupResult = Show-Prompt -Title 'Veeam Configuration Backup' -Message $backupMessage -Choices $backupOptions -DefaultOption 0

if ($backupResult -eq 0) {
	# Run backup
	Write-Host "`nCreating backup, please wait..."
	$backupExecution = Start-VBRConfigurationBackupJob | Out-Null
	if ($backupExecution.Result -ne 'Failed') {
		Write-Host 'Backup completed successfully.'
	}
	else {
		$continueYes = New-PromptChoice -Label '&Yes' -HelpMessage 'Continue anyway.'
		$continueNo = New-PromptChoice -Label '&No' -HelpMessage 'Exit now.'
		$continueOptions = @($continueYes, $continueNo)
		$continueResult = Show-Prompt -Title 'Backup Failed' -Message 'Do you want to continue anyway' -Choices $continueOptions

		if ($continueResult -eq 1) {
			Write-Host 'Exiting.'
			Start-Sleep 10
			exit
		}
		else {
			Write-Host 'Continuing anyway.'
		}
	}
}

# Query configure all or selected jobs
$configChoose = New-PromptChoice -Label '&Choose' -HelpMessage 'Choose how to configure each job.'
$configAll = New-PromptChoice -Label '&All' -HelpMessage 'Configure all supported jobs automatically.'
$configNone = New-PromptChoice -Label '&None' -HelpMessage 'Do not configure any jobs.'
$configOptions = @($configChoose, $configAll, $configNone)
$configMessage = 'Do you wish to make a choice for each job, configure all supported jobs, or configure none?'
$configResult = Show-Prompt -Title 'Job Configuration Selection' -Message $configMessage -Choices $configOptions -DefaultOption 0

switch ($configResult) {
	# Choose how to configure each job
	0 {
		do {
		# Create a job selection menu instead of iterating through each job
		$jobMenu = @{}
		$menuIndex = 1

		Write-Host "`nAvailable jobs:"
		foreach ($job in $backupJobs) {
			Write-Host "$menuIndex. $($job.Name) ($($job.TypeToString))"
			$jobMenu.Add($menuIndex, $job)
			$menuIndex++
		}

		Write-Host "`n0. Exit job configuration"

			$selectedJobIndex = Read-Host "`nEnter the job number to configure (0 to exit)"

			if ($selectedJobIndex -eq "0") {
				Write-Host "Exiting job configuration."
				break
			}

			if ($jobMenu.ContainsKey([int]$selectedJobIndex)) {
				$selectedJob = $jobMenu[[int]$selectedJobIndex]
				Set-BackupJobPostScript -Job $selectedJob -NewPostScriptCmd $newPostScriptCmd -PowershellPath $powershellExePath -AskBeforeConfiguring $true
			} else {
				Write-Host "Invalid selection. Please enter a valid job number."
			}
		} while ($true)
	}
	# Configure all jobs
	1 {
		foreach ($job in $backupJobs) {
			Set-BackupJobPostScript -Job $job -NewPostScriptCmd $newPostScriptCmd -PowershellPath $powershellExePath -AskBeforeConfiguring $false
		}
	}

	# Configure none
	2 {
		Write-Host 'Skipping VeeamNotify configuration deployment for all jobs.'
	}
}

if ($MyInvocation.ScriptName -notlike '*Installer.ps1') {
	Write-Host "`n`Finished. Exiting."
	Start-Sleep 10
}

exit
