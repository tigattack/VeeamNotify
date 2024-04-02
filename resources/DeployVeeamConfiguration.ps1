param(
	[String]$InstallParentPath = 'C:\VeeamScripts'
)

$issuesUrl = 'https://github.com/tigattack/VeeamNotify/issues'

#region Prompt definitions TODO: move these somewhere else?
$backupChoiceParams = @{
	caption       = 'Create a Veeam Configuration Backup?'
	message       = 'This script can create a Veeam configuration backup for you before making any changes.'
	choices       = [System.Management.Automation.Host.ChoiceDescription[]](
		[System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Create a Veeam configuration backup.'),
		[System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Do not create a Veeam configuration backup.')
	)
	defaultChoice = 0
}

$backupErrorParams = @{
	caption       = 'Backup Failed'
	message       = 'Do you want to continue anyway?'
	choices       = [System.Management.Automation.Host.ChoiceDescription[]](
		[System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Continue anyway.'),
		[System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Exit now.')
	)
	defaultChoice = -1
}

$configChoiceParams = @{
	caption       = 'Job Configuration Selection'
	message       = 'Do you wish to configure all supported jobs, make a decision for each job, or configure none?'
	choices       = [System.Management.Automation.Host.ChoiceDescription[]](
		[System.Management.Automation.Host.ChoiceDescription]::new('&All', 'Configure all supported jobs automatically.'),
		[System.Management.Automation.Host.ChoiceDescription]::new('&Decide', 'Make a decision for each job.'),
		[System.Management.Automation.Host.ChoiceDescription]::new('&None', 'Do not configure any jobs.')
	)
	defaultChoice = 0
}

$launchIssuesPromptParams = @{
	caption       = "Please raise an issue at ${issuesUrl}"
	message       = 'Do you wish to open the new issue page in your browser?'
	choices       = [System.Management.Automation.Host.ChoiceDescription[]](
		[System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Open a new issue'),
		[System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Do nothing')
	)
	defaultChoice = -1
}

$overwriteCurrentCmdParams = @{
	caption       = 'Overwrite Job Configuration'
	message       = 'Do you wish to overwrite the existing post-job script?'
	choices       = [System.Management.Automation.Host.ChoiceDescription[]](
		[System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Overwrite the current post-job script.'),
		[System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Skip configuration of this job, leaving it as-is.')
	)
	defaultChoice = -1
}

$setNewPostScriptParams = @{
	caption       = 'Send notifications for this job?'
	message       = ''
	choices       =  [System.Management.Automation.Host.ChoiceDescription[]](
		[System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Configure this job to send notifications.'),
		[System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Skip configuration of this job, leaving it as-is.')
	)
	defaultChoice = -1
}
#endregion

#region Functions
function DoPrompt ($params) {
	return $host.UI.PromptForChoice($params.caption, $params.message, $params.choices, $params.defaultChoice)
}

function DeploymentError {
	$errorPosition = $_.InvocationInfo.PSCommandPath, $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.OffsetInLine -join ':'
	$errorFunction = $_.InvocationInfo.MyCommand
	$errorException = $_.Exception.Message

	if ($errorFunction) {
		Write-Output "An error occurred in ${errorFunction} at ${errorPosition}: ${errorException}" | Out-Host
	}
	else {
		Write-Output "An error occurred at ${errorPosition}: ${errorException}" | Out-Host
	}

	$launchIssuesPromptResp = DoPrompt($launchIssuesPromptParams)
	if ($launchIssuesPromptResp -eq 0) {
		Add-Type -AssemblyName System.Web
		$title = [System.Web.HttpUtility]::UrlEncode('[BUG] Veeam configuration deployment error')

		$formatString = 'Exception:
```ps1
{0} : {1}
{2}
	+ CategoryInfo          : {3}
	+ FullyQualifiedErrorId : {4}
```'
		$fields = $_.InvocationInfo.MyCommand.Name, $_.Exception.Message, $_.InvocationInfo.PositionMessage, $_.CategoryInfo.ToString(), $_.FullyQualifiedErrorId
		$errorString = [System.Web.HttpUtility]::UrlEncode($formatString -f $fields)

		$veeamBuild = (Get-Item 'C:\Program Files\Veeam\Backup and Replication\Backup\Packages\VeeamDeploymentDll.dll').VersionInfo.ProductVersion

		Start-Process "$issuesUrl/new?labels=bug&template=bug_report.yml&title=${title}&veeam_version=${veeamBuild}&logs=${errorString}"
	}
	Write-Output "`nExiting." | Out-Host
	Start-Sleep 3
	exit
}

function GetJobScriptOptions ($job) {
	switch ($job.GetType().Name) {
		'CBackupJob' {
			$opts = $job.GetOptions()
			return @{
				'jobOptions'            = $opts;
				'PostScriptEnabled'     = $opts.JobScriptCommand.PostScriptEnabled;
				'PostScriptCommandLine' = $opts.JobScriptCommand.PostScriptCommandLine
			}
		}
		'VBRComputerBackupJob' {
			$opts = $job.ScriptOptions
			return @{
				'jobOptions'            = $opts;
				'PostScriptEnabled'     = $opts.PostScriptEnabled;
				'PostScriptCommandLine' = $opts.PostCommand
			}
		}
	}
}

function PatchJobScriptOptions ($job, $newPostScriptCmd, $jobOptions) {
	switch ($job.GetType().Name) {
		'CBackupJob' {
			$jobOptions.JobScriptCommand.PostScriptEnabled = $true
			$jobOptions.JobScriptCommand.PostScriptCommandLine = $newPostScriptCmd
			return Set-VBRJobOptions -Job $job -Options $jobOptions
		}
		'VBRComputerBackupJob' {
			$newScriptOptions = Set-VBRJobScriptOptions -JobScriptOptions $job.ScriptOptions -PostScriptEnabled -PostCommand $newPostScriptCmd
			return Set-VBRComputerBackupJob -Job $job -ScriptOptions $newScriptOptions
		}
	}
}

function ConfigureJob ($job, [string]$newPostScriptCmd, [switch]$nonInteractive) {
	# Get post-job script options for job
	$opts = GetJobScriptOptions -job $job
	$jobOptions = $opts.jobOptions
	$postScriptEnabled = $opts.PostScriptEnabled
	$postScriptCmd = $opts.PostScriptCommandLine

	# Check if job is already configured for VeeamNotify
	if ($postScriptCmd -eq $newPostScriptCmd) {
		Write-Output "$($job.Name) is already configured for VeeamNotify; Skipping."
		return
	}

	elseif ($postScriptEnabled) {
		Write-Output "`n$($job.Name) has an existing post-job script.`nScript: $postScriptCmd"

		if (-not $nonInteractive) {
			Write-Output "`nIf you wish to receive notifications for this job, you must overwrite the existing post-job script."
			$overwriteCurrentCmdResp = DoPrompt($overwriteCurrentCmdParams)
			if ($overwriteCurrentCmdResp -eq 1) {
				Write-Output "`nSkipping job $($job.Name)`n"
			}
		}

		if ($nonInteractive -or $overwriteCurrentCmdResp -eq 0) {
			try {
				PatchJobScriptOptions -job $job -newPostScriptCmd $newPostScriptCmd -jobOptions $jobOptions | Out-Null
				Write-Output "Updated post-job script for job $($job.Name).`nOld: $postScriptCmd`nNew: $newPostScriptCmd"
				Write-Output "$($job.Name) is now configured for VeeamNotify."
			}
			catch {
				DeploymentError
			}
		}
	}

	else {
		if (-not $nonInteractive) {
			$setNewPostScriptResp = DoPrompt($setNewPostScriptParams)
			if ($setNewPostScriptResp -eq 1) {
				Write-Output "`nSkipping job $($job.Name)`n"
			}
		}

		if ($nonInteractive -or $setNewPostScriptResp -eq 0) {
			try {
				PatchJobScriptOptions -job $job -newPostScriptCmd $newPostScriptCmd -jobOptions $jobOptions | Out-Null
				Write-Output "`n$($job.Name) is now configured for VeeamNotify."
			}
			catch {
				DeploymentError
			}
		}
	}
}

function ConfigureJobs ([array]$backupJobs, [string]$newPostScriptCmd, [switch]$nonInteractive) {
	foreach ($job in $backupJobs) {
		Write-Output "`nChecking job '$($job.Name)'..."
		ConfigureJob -job $job -newPostScriptCmd $newPostScriptCmd -nonInteractive:$nonInteractive
	}
}

function GetJobs {
	$jobs = @()
	try {
		$jobs += Get-VBRJob | Where-Object {
			$_.JobType -in 'Backup', 'Replica'
		}
		$jobs += Get-VBRComputerBackupJob | Where-Object {
			$_.Mode -eq 'ManagedByBackupServer'
		}
		return ($jobs | Sort-Object -Property Name)
	}
	catch {
		DeploymentError
	}
}
#endregion

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

if ($MyInvocation.ScriptName -notlike '*Installer.ps1') {
	Write-Output "
__     __                        _   _       _   _  __
\ \   / /__  ___  __ _ _ __ ___ | \ | | ___ | |_(_)/ _|_   _
 \ \ / / _ \/ _ \/ _` | '_ ` _ \|  \| |/ _ \| __| | |_| | | |
  \ V /  __/  __/ (_| | | | | | | |\  | (_) | |_| |  _| |_| |
   \_/ \___|\___|\__,_|_| |_| |_|_| \_|\___/ \__|_|_|  \__, |
                                                       |___/
"
}

# Get all supported jobs
Write-Output 'Discovering supported jobs...'
$backupJobs = GetJobs

if ($backupJobs.Count -gt 0) {
	Write-Output "Found $($backupJobs.count) supported jobs:"
	$type = if ($backupJobs[0].JobType -eq 'Backup') { 'Backup' } elseif ($backupJobs[0].JobType -eq 'Replica') { 'Replication' }

	$backupJobs | Format-Table -AutoSize -Property Name, @{Name = 'Type'; Expression = {
			if ($_.Mode -eq 'ManagedByBackupServer') { 'Agent' }
			elseif ($_.JobType -eq 'Backup') { 'VM Backup' }
			elseif ($_.JobType -eq 'Replica') { 'VM Replication' }
			else { 'Unknown' }
		}
	}
}
else {
	Write-Output 'No supported jobs found; Exiting.'
	Start-Sleep 3
	exit
}

# Do config backup if user wishes
$backupChoiceResp = DoPrompt($backupChoiceParams)
if ($backupChoiceResp -eq 0) {
	# Run backup
	Write-Output "`nCreating backup, please wait..."
	($backupResult = Start-VBRConfigurationBackupJob) | Out-Null

	if ($backupResult.Result -ne 'Failed') {
		Write-Output 'Backup completed successfully.'
	}

	# Backup failed, exit/continue depending on user's wish
	else {
		$backupErrorResp = DoPrompt($backupErrorParams)
		if ($backupChoiceResp -eq 1) {
			Write-Output 'Exiting.'
			Start-Sleep 3
			exit
		}
		else {
			Write-Output 'Continuing anyway.'
		}
	}
}

# Query configure all or selected jobs
switch (DoPrompt($configChoiceParams)) {
	0 { ConfigureJobs -backupJobs $backupJobs -newPostScriptCmd $newPostScriptCmd -nonInteractive }
	1 { ConfigureJobs -backupJobs $backupJobs -newPostScriptCmd $newPostScriptCmd }
	2 { Write-Output 'Skipping VeeamNotify configuration deployment for all jobs.' }
}

if ($MyInvocation.ScriptName -notlike '*Installer.ps1') {
	Write-Output "`n`Finished. Exiting."
	Start-Sleep 3
}

exit
