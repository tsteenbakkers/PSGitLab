Set-BuildEnvironment

$ModuleName = 'PSGitLab'
$projectRoot = $ENV:BHProjectPath
if(-not $projectRoot) {
	$projectRoot = $PSScriptRoot
}

$sut = "$projectRoot\$ModuleName"
$tests = "$projectRoot\Tests"

$ReleaseDirectory = join-path $projectRoot 'Release'

$psVersion = $PSVersionTable.PSVersion.Major

# Synopsis: Initalize the enviornment
task Init {
    "`nSTATUS: Testing with PowerShell {0}" -f $psVersion
    "Build System Details:"
    Get-Item ENV:BH*

    $modules = 'Pester', 'PSDeploy', 'PSScriptAnalyzer'
    Import-Module $modules -Verbose:$false -Force	
}

# Synopsis: PSScriptAnalyzer 
task Analyze {
    # Modify PSModulePath of the current PowerShell session.
    # We want to make sure we always test the development version of the resource
    # in the current build directory.
    $origModulePath = $env:PSModulePath
    $newModulePath = $origModulePath
    if (($newModulePath.Split(';') | Select-Object -First 1) -ne $projectRoot) {
        # Add the project root to the beginning if it is not already at the front.
        $env:PSModulePath = "$projectRoot;$env:PSModulePath"
    }

    $excludedRules = (
        'PSAvoidUsingConvertToSecureStringWithPlainText', # For private token information
        'PSAvoidUsingUserNameAndPassWordParams' # this refers to gitlab users and passwords
    )
    $saResults = Invoke-ScriptAnalyzer -Path $sut -Severity Error -ExcludeRule $excludedRules -Recurse -Verbose:$false

    # Restore PSModulePath
    if ($origModulePath -ne $env:PSModulePath) {
        $env:PSModulePath = $origModulePath
    }

    if ($saResults) {
        $saResults | Format-Table
        Write-Error -Message 'One or more Script Analyzer errors/warnings where found. Build cannot continue!'
    }    
}

# Synopsis: Pester Tests
Task Pester {
    if(-not $ENV:BHProjectPath) {
        Set-BuildEnvironment -Path $PSScriptRoot\..
    }
    Remove-Module $ENV:BHProjectName -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ENV:BHProjectPath $ENV:BHProjectName) -Force

    $testResults = Invoke-Pester -Path $tests -PassThru
    if ($testResults.FailedCount -gt 0) {
        $testResults | Format-List
        Write-Error -Message 'One or more Pester tests failed. Build cannot continue!'
    }    
}
# Synopsis: Merge private and public functions into one .psm1 file
task mergePSM1 {
    
    $ReleaseDirectory = join-path $projectRoot 'Release'
    if (Test-Path $ReleaseDirectory) {
        remove-item -Recurse -Force -Path $ReleaseDirectory
    }

    #Create Release Folder
    New-Item -Path $ReleaseDirectory -ItemType Directory | Out-Null
    
    #Copy Module Manifest
    Copy-Item "$projectRoot\$ModuleName\$ModuleName.psd1" -Destination $ReleaseDirectory

    #Copy Formats
    if (Test-Path "$projectRoot\$ModuleName\$ModuleName.Format.ps1xml") {
        Copy-Item "$projectRoot\$ModuleName\$ModuleName.Format.ps1xml" -Destination $ReleaseDirectory
    }

    # Merge PSM1
    $PSM1Path = "$ReleaseDirectory\$ModuleName.psm1"

    foreach ($Folder in @('Public','Private') ) {

        "##########################" | Add-Content $PSM1Path
        "#    $Folder Functions    " | Add-Content $PSM1Path
        "##########################" | Add-Content $PSM1Path

        foreach ($Function in (Get-ChildItem $projectRoot\$ModuleName\$Folder -Recurse -Include *.ps1) ) {
            Get-Content $Function.Fullname | Add-Content $PSM1Path
            "`r`n" | Add-Content $PSM1Path
        }

    }
    
}

# Synopsis: Remove the Release directory
Task Cleanup {
    if (Test-Path $ReleaseDirectory) {
        Remove-Item -Recurse -Force -Path $ReleaseDirectory
    }
}

# Synopsis: Run before commiting your code
task Pre-Commit init,pester,analyze

# Synopsis: Default Task - Alias for Pre-Commit
task . Pre-Commit

task psdeploy {
    Import-Module "$ReleaseDirectory\$ModuleName.psd1"
    
    # Gate deployment
    if( $ENV:BHBuildSystem -ne 'Unknown' -and
        $ENV:BHBranchName -eq "master" -and
        $ENV:BHCommitMessage -match '!deploy'
    ) {
        $params = @{
            Path = "$projectRoot\module.psdeploy.ps1"
            Force = $true
            Recurse = $false
        }
        
        Invoke-PSDeploy @Params
    } else {
        "Skipping deployment: To deploy, ensure that...`n" +
        "`t* You are in a known build system (Current: $ENV:BHBuildSystem)`n" +
        "`t* You are committing to the master branch (Current: $ENV:BHBranchName) `n" +
        "`t* Your commit message includes !deploy (Current: $ENV:BHCommitMessage)"
    }    
}

# Synopsis: Deploy to Powershell Gallery
task Deploy init,pester,analyze,mergePSM1,psdeploy 