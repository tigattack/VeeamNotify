# Settings for PSScriptAnalyzer invocation.
@{
	ExcludeRules = @(
		'PSAvoidLongLines',
		'PSUseSingularNouns',
		'PSUseShouldProcessForStateChangingFunctions',
		'PSUseDeclaredVarsMoreThanAssignments', # Buggy - https://github.com/PowerShell/PSScriptAnalyzer/issues/1641
		'PSAvoidUsingWriteHost'
	)
	Rules        = @{
		PSAvoidUsingDoubleQuotesForConstantString = @{
			Enable = $true
		}
		PSAvoidUsingPositionalParameters          = @{
			Enable = $true
		}
		PSUseCompatibleCommands                   = @{
			Enable         = $true
			# PowerShell platforms we want to check compatibility with
			TargetProfiles = @(
				'win-8_x64_10.0.14393.0_7.0.0_x64_3.1.2_core', # PowerShell 7.0 on Windows Server 2016
				'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core', # PowerShell 7.0 on Server 2019
				'win-4_x64_10.0.18362.0_7.0.0_x64_3.1.2_core' # PowerShell 7.0 on Windows 10
			)
		}
		PSUseCompatibleSyntax                     = @{
			Enable         = $true
			# PowerShell versions we want to check compatibility with
			TargetVersions = @(
				'7.0'
			)
		}
		PSPlaceCloseBrace                         = @{
			Enable             = $true
			NoEmptyLineBefore  = $false
			IgnoreOneLineBlock = $true
			NewLineAfter       = $true
		}
		PSPlaceOpenBrace                          = @{
			Enable             = $true
			OnSameLine         = $true
			NewLineAfter       = $true
			IgnoreOneLineBlock = $true
		}
		PSUseConsistentIndentation                = @{
			Enable              = $true
			IndentationSize     = 4
			PipelineIndentation = 'IncreaseIndentationAfterEveryPipeline'
			Kind                = 'tab'
		}
		PSAvoidLongLines                          = @{
			Enable            = $true
			MaximumLineLength = 155
		}
		PSAlignAssignmentStatement                = @{
			Enable         = $true
			CheckHashtable = $true
		}
		PSUseCorrectCasing                        = @{
			Enable = $true
		}
		PSAvoidSemicolonsAsLineTerminators        = @{
			Enable = $true
		}
	}
}
