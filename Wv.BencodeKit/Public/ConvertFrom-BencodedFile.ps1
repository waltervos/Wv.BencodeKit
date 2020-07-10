function ConvertFrom-BencodedFile {
    [CmdletBinding(ConfirmImpact='Low')]
    param (
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)]
        [ValidateScript({ Test-Path -Path $_ })]
        [String] $FilePath,
        [Parameter(Mandatory=$False)]
        [System.Text.Encoding] $Encoding = [System.Text.Encoding]::UTF8
    )
    
    begin {

    }
    
    process {
        Write-Verbose "Starting conversion of $FilePath to PowerShell object."
        try {
            $BencodedFile = [BencodedFile]::new($FilePath, $Encoding)
            $BencodedFile.BencodedData
        }
        finally {
            $BencodedFile.Dispose()
        }
    }
    
    end {
        Write-Verbose "Finished."
    }
}