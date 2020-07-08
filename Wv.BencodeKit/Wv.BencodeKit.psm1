Write-Verbose "Importing Functions"

# Import everything in these folders
foreach($Folder in @('Private', 'Public', 'Classes')) {
    $Root = Join-Path -Path $PSScriptRoot -ChildPath $Folder
    if(Test-Path -Path $Root) {
        Write-Verbose "Processing folder $Root"
        
        # dot source each file
        Get-ChildItem -Path $Root -Filter *.ps1 | 
            Where-Object{ $_.name -NotLike '*.Tests.ps1'} | 
                ForEach-Object { 
                    Write-Verbose "Dot-sourcing file $($_.name)"
                    . $_.FullName
                }
    }
}

Export-ModuleMember -Function (Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1").basename