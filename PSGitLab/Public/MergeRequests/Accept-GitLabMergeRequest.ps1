Function Accept-GitLabMergeRequest {
    [cmdletbinding()]
    param(
        [Alias('project_id')]
        [ValidateNotNullOrEmpty()]
        [Parameter(ValueFromPipelineByPropertyName,Mandatory)]
        [string]$ProjectId,

        [ValidateNotNullOrEmpty()]
        [Parameter(ValueFromPipelineByPropertyName,Mandatory)]
        [string[]]$ID,

        [switch]$MergeWhenBuildSucceeds,

        [switch]$Passthru

    )

BEGIN {} 

PROCESS {

    foreach ( $MergeRequestID in $ID ) {
        $Project = $Project = Get-GitlabProject -Id $ProjectId;

        $MergeRequest = Get-GitLabMergeRequest -ProjectId $ProjectId -Id $MergeRequestID

        Write-Verbose "Project Name: $($Project.Name), Merge Request Name: $($MergeRequest.Name)"

        $GetUrlParameters = @()

        if ($MergeWhenBuildSucceeds) {
            $GetUrlParameters += @{merge_when_build_succeeds=$true}
        }
        
        $URLParameters = GetMethodParameters -GetURLParameters $GetUrlParameters

        $Request = @{
            URI = "/projects/$($Project.ID)/merge_requests/$($MergeRequest.ID)/merge$URLParameters"
            Method = 'PUT'
        }

        $Results = QueryGitLabAPI -Request $Request -ObjectType 'GitLab.MergeRequest'

        if ( $Passthru.isPresent ) {
            $Results
        }
    }
}

END {}

}