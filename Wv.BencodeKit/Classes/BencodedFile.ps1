class BencodedFile {
    [System.IO.FileStream] $Stream
    [System.IO.BinaryReader] $Reader
    [System.IO.FileInfo] $File
    [System.Object] $BencodedData
    [System.Text.Encoding] $Encoding = [System.Text.Encoding]::UTF8

    BencodedFile([String] $FilePath) {
        $this.Init($FilePath)
    }
    
    BencodedFile([String] $FilePath, [System.Text.Encoding] $Encoding) {
        $this.Encoding = $Encoding
        $this.Init($FilePath)
    }

    [Void] Init([String] $FilePath) {
        if (!(Test-Path -Path $FilePath -PathType leaf)) {
            throw "$FilePath is not a valid path to a file"
        }

        $this.File = Get-Item -Path $FilePath
        $this.Stream = [System.IO.FileStream]::new([string]$FilePath, 'Open')
        $this.Reader = [System.IO.BinaryReader]::new($this.Stream, $this.Encoding)
        $this.BencodedData = $this.DoDecode()
    }

    [Void] Dispose() {
        $this.Reader.Dispose()
    }

    [System.Object] DoDecode() {
        switch ($this.GetByteAsString()) {
            'd' {
                $this.AdvancePosition()
                return $this.DecodeDictionary()
            }
            'l' {
                $this.AdvancePosition()
                return $this.DecodeList()
            }
            'i' {
                $this.AdvancePosition()
                return $this.DecodeInteger()
            }
            default {
                if ([char]::IsDigit($this.GetByte())) {
                    return $this.DecodeByteString()
                }
            }
        }
        throw "Unknown entity found at offset $($this.Stream.Position)"
        return $False # PS was complaining
    }

    [void] AdvancePosition([int64]$Offset) {
        $this.Stream.Position =  $this.Stream.Position + $Offset
    }

    [void] AdvancePosition() {
        $this.AdvancePosition(1)
    }

    [byte[]] GetBytes([int64] $Count, [int64] $Offset, [int64] $Position) {
        $InitialPosition = $this.Stream.Position
        $This.Stream.Position = $Position + $Offset
        [byte[]] $Bytes = $this.Reader.ReadBytes($Count)
        $This.Stream.Position = $InitialPosition
        return $Bytes
    }

    [byte] GetByte($Offset, $Position) {
        $InitialPosition = $this.Stream.Position
        $This.Stream.Position = $Offset + $Position
        $Byte = [byte] $this.Reader.ReadByte()
        $This.Stream.Position = $InitialPosition
        return $Byte
    }

    [byte[]] GetBytes([int64] $Count, [int64] $Offset) {
        return $this.GetBytes($Count, $Offset, $this.Stream.Position)
    }

    [byte] GetByte($Offset) {
        return $this.GetByte($Offset, $this.Stream.Position)
    }

    [byte[]] GetBytes([int64] $Count) {
        return $this.GetBytes($Count, 0, $this.Stream.Position)
    }

    [byte] GetByte() {
        return $this.GetByte(0, $this.Stream.Position)
    }

    [string] GetByteAsString([int64] $Offset) {
        return [string] $this.Encoding.GetString($this.GetByte($Offset))
    }

    [string] GetByteAsString() {
        return $this.GetByteAsString(0)
    }

    [int64] GetByteAsInt() {
        $String = $this.GetByteAsString()
        return [int64] [System.Convert]::ToInt64($String)
    }

    [System.Collections.Hashtable] DecodeDictionary() {
        $Dictionary = [System.Collections.Hashtable]::new()
        [bool] $Terminated = $False
        [int64] $DictionaryOffset = $this.Stream.Position
        while ($False -ne $this.GetByte()) {
            if ($this.GetByteAsString() -eq 'e') {
                $Terminated = $True
                break
            }

            $KeyOffset = $this.Stream.Position
            if (![char]::IsDigit($this.GetByte())) {
                throw "Invalid dictionary key at offset $KeyOffset"
            }

            $Key = $this.DecodeString()
            if ($Dictionary.ContainsKey($Key)) {
                throw "Duplicate dictionary key at offset $KeyOffset"
            }

            $Dictionary.Add($Key, $this.DoDecode())
        }

        if (($Terminated -eq $False) -and ($False -ne $this.GetByte())) {
            throw "Unterminated dictionary definition at offset $DictionaryOffset"
        }

        $this.AdvancePosition()

        return $Dictionary
    }

    [System.Collections.Generic.List[PSObject]] DecodeList() {
        $List = [System.Collections.Generic.List[PSObject]]::new()
        [bool] $Terminated = $False
        [int64] $ListOffset = $this.Stream.Position
        while ($False -ne $this.GetByte()) {
            if ($this.GetByteAsString() -eq 'e') {
                $Terminated = $True
                break
            }

            $List.Add($this.DoDecode())
        }

        if (($Terminated -eq $False) -and ($False -ne $this.GetByte())) {
            throw "Unterminated list definition at offset $ListOffset"
        }

        $this.AdvancePosition()
        return $List
    }

    [System.Double] DecodeInteger() {        
        $OffsetOfE = $this.GetOffsetOfString('e')
        $PositionOfE = $this.Stream.Position + $OffsetOfE
        if ($False -eq $OffsetOfE) {
            throw "Unterminated integer entity at offset $($this.Stream.Position)"
        }

        $CurrentPosition = $this.Stream.Position
        if ($this.GetByteAsString() -eq '-') {
            $CurrentPosition++
        }

        # Not sure about this comparison
        if ($PositionOfE -eq $CurrentPosition) {
            throw "Empty integer entity at offset $($this.Stream.Position)"
        }

        while ($CurrentPosition -lt $PositionOfE) {
            $Byte = $this.GetByte(0, $CurrentPosition)
            $Char = $this.Encoding.GetChars($Byte)
            if (($this.Encoding.GetCharCount($Byte) -ne 1) -or ($False -eq [char]::IsDigit($Char[0]))) {
                throw "Non-numeric character found in integer entity at offset $($this.Stream.Position)"
            }

            $CurrentPosition++
        }

        [byte[]] $Bytes = $this.GetBytes($OffsetOfE)
        $Integer = $this.Encoding.GetString($Bytes)

        $this.AdvancePosition($OffsetOfE + 1)

        return [double] $Integer
    }

    [System.String] DecodeString() {
        $ContentLength = $this.GetByteStringLength()
        $OffsetOfColon = $this.GetOffsetOfColon()

        $Bytes = $this.GetBytes($ContentLength, $OffsetOfColon + 1)
        $String = $this.Encoding.GetString($Bytes)
        
        $this.AdvancePosition($OffsetOfColon + $ContentLength + 1)
        Write-Host "String is $String"
        return $String
    }

    [hashtable] DecodeByteString() {
        $Hashtable = @{}
        $ContentLength = $this.GetByteStringLength()
        $OffsetOfColon = $this.GetOffsetOfColon()

        $Bytes = $this.GetBytes($ContentLength, $OffsetOfColon + 1)
        $Hashtable.Add('bytestring', $Bytes)
        $Hashtable.Add('string', $this.Encoding.GetString($Bytes))
        
        $this.AdvancePosition($OffsetOfColon + $ContentLength + 1)
        Write-Host "ByteString length is $($Bytes.Length)"
        return $Hashtable
    }

    [int64] GetOffsetOfColon() {
        $OffsetOfColon = $this.GetOffsetOfString(':')
        if ($OffsetOfColon -eq $False) {
            throw "Unterminated string entity at offset $($this.Stream.Position)"
        }
        return $OffsetOfColon
    }
    
    [Int64] GetByteStringLength() {
        if (($this.GetByteAsInt() -eq 0) -and ($this.GetByteAsString(1) -ne ':')) {
            throw "Illegal zero-padding in string entity length declaration at offset $($this.Stream.Position)"
        }

        $OffsetOfColon = $this.GetOffsetOfColon()
        
        $ByteString = $this.GetBytes($OffsetOfColon, 0)
        $ByteStringChars = $this.Encoding.GetChars($ByteString)
        $ContentLength = [System.Convert]::ToInt64([System.String]::new($ByteStringChars))

        if (($ContentLength + 1) -gt $this.Stream.Length ) {
            throw "Unexpected end of string entity at offset $($this.Stream.Position)"
        }

        return $ContentLength
    }

    [int64] GetOffsetOfString([System.String] $String) {
        if ($String.Length -ne 1) {
            throw "$String has incompatible length of $($String.Length)"
        }

        $OffsetOfString = 1
        while ($True) {
            $StringByte = $this.GetByteAsString($OffsetOfString)
            if ($StringByte -eq $String) {
                break
            }
            elseif ($StringByte -eq $False) {
                $OffsetOfString = $False
                break
            }
            else {
                $OffsetOfString++
            }
        }
        return $OffsetOfString
    }
}