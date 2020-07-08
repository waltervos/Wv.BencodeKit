class BencodedFile {
    [System.IO.FileStream] $Stream
    [System.IO.BinaryReader] $Reader
    [System.IO.FileInfo] $File
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
    }

    [Void] Dispose() {
        $this.Reader.Dispose()
    }

    [Void] WritePosition($From) {
        Write-Host "Offset/Position in $From is $($this.Stream.Position)"
    }

    [System.Object] DoDecode() {
        $this.WritePosition('DoDecode')
        switch ($this.GetCharAsString()) {
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
                if ([char]::IsDigit($this.GetChar())) {
                    return $this.DecodeString()
                }
            }
        }
        throw "Unknown entity found at offset $($this.Stream.Position)"
        return $False # PS was complaining
    }

    [void] AdvancePosition([Int]$Offset) {
        $this.WritePosition('AdvancePosition')
        $this.Stream.Position =  $this.Stream.Position + $Offset
    }

    [void] AdvancePosition() {
        $this.AdvancePosition(1)
    }

    [char] GetChar($Offset, $Position) {
        $this.WritePosition('GetChar')
        $InitialPosition = $this.Stream.Position
        $This.Stream.Position = $Offset + $Position
        $Char = [char] $this.Reader.PeekChar()
        $This.Stream.Position = $InitialPosition
        return $Char
    }

    [char] GetChar($Offset) {
        return $this.GetChar($Offset, $this.Stream.Position)
    }

    [char] GetChar() {
        return $this.GetChar(0, $this.Stream.Position)
    }

    [string] GetCharAsString([int] $Offset) {
        return ($this.GetChar($Offset)).ToString()
    }

    [string] GetCharAsString() {
        return $this.GetCharAsString(0)
    }

    [int32] GetCharAsInt([int] $Offset) {
        return [char]::GetNumericValue($this.GetChar($Offset))
    }

    [int32] GetCharAsInt() {
        return $this.GetCharAsInt(0)
    }

    [char[]] GetChars([int] $Count, [int] $Offset, [int] $Position) {
        $this.WritePosition("GetChars with count $Count, from position $Position with offset $Offset")
        $InitialPosition = $this.Stream.Position
        $This.Stream.Position = $Position + $Offset
        [char[]] $Chars = $this.Reader.ReadChars($Count)
        $This.Stream.Position = $InitialPosition
        return $Chars
    }

    [char[]] GetChars([int] $Count, [int] $Offset) {
        return $this.GetChars($Count, $Offset, $this.Stream.Position)
    }

    [char[]] GetChars([int] $Count) {
        return $this.GetChars($Count, 0, $this.Stream.Position)
    }

    [char[]] GetChars() {
        return $this.GetChar()
    }

    [System.Collections.Hashtable] DecodeDictionary() {
        $this.WritePosition('DecodeDictionary')
        $Dictionary = [System.Collections.Hashtable]::new()
        [bool] $Terminated = $False
        [int] $DictionaryOffset = $this.Stream.Position
        while ($False -ne $this.GetChar()) {
            if ($this.GetCharAsString() -eq 'e') {
                $Terminated = $True
                break
            }

            $KeyOffset = $this.Stream.Position
            if (![char]::IsDigit($this.GetChar())) {
                throw "Invalid dictionary key at offset $KeyOffset"
            }

            $Key = $this.DecodeString()
            if ($Dictionary.ContainsKey($Key)) {
                throw "Duplicate dictionary key at offset $KeyOffset"
            }

            $Dictionary.Add($Key, $this.DoDecode())
        }

        if (($Terminated -eq $False) -and ($False -ne $this.GetChar())) {
            throw "Unterminated dictionary definition at offset $DictionaryOffset"
        }

        $this.AdvancePosition()

        return $Dictionary
    }

    [System.Collections.Generic.List[PSObject]] DecodeList() {
        $this.WritePosition('DecodeList')
        $List = [System.Collections.Generic.List[PSObject]]::new()
        [bool] $Terminated = $False
        [int] $ListOffset = $this.Stream.Position
        while ($False -ne $this.GetChar()) {
            if ($this.GetCharAsString() -eq 'e') {
                $Terminated = $True
                break
            }

            $List.Add($this.DoDecode())
        }

        if (($Terminated -eq $False) -and ($False -ne $this.GetChar())) {
            throw "Unterminated list definition at offset $ListOffset"
        }

        $this.AdvancePosition()
        return $List
    }

    [System.Double] DecodeInteger() {
        $this.WritePosition('DecodeInteger')
        $Integer = [System.Double]::new()
        
        # Offset, position, figure it out!
        $OffsetOfE = $this.GetOffsetOfString('e')
        $PositionOfE = $this.Stream.Position + $OffsetOfE
        if ($False -eq $OffsetOfE) {
            throw "Unterminated integer entity at offset $($this.Stream.Position)"
        }

        $CurrentPosition = $this.Stream.Position
        if ($this.GetCharAsString() -eq '-') {
            $CurrentPosition++
        }

        # Not sure about this comparison
        if ($PositionOfE -eq $CurrentPosition) {
            throw "Empty integer entity at offset $($this.Stream.Position)"
        }

        while ($CurrentPosition -lt $PositionOfE) {
            if ($False -eq [char]::IsDigit($this.GetChar(0, $CurrentPosition))) {
                throw "Non-numeric character found in integer entity at offset $($this.Stream.Position)"
            }
            $CurrentPosition++
        }

        [char[]] $Chars = $this.GetChars($OffsetOfE)
        $Integer = $this.CharsToType($Chars, 'integer')

        $this.AdvancePosition($OffsetOfE + 1)

        return $Integer
    }

    [System.String] DecodeString() {
        $this.WritePosition('DecodeString')
        if (($this.GetCharAsInt() -eq 0) -and ($this.GetCharAsString(1) -ne ':')) {
            throw "Illegal zero-padding in string entity length declaration at offset $($this.Stream.Position)"
        }

        $OffsetOfColon = $this.GetOffsetOfString(':')
        if ($OffsetOfColon -eq $False) {
            throw "Unterminated string entity at offset $($this.Stream.Position)"
        }
        
        # Zoek hier een oplossing met substring
        [int32] $ContentLength = $Null
        $this.GetChars($OffsetOfColon, 0) | ForEach-Object {
            [int] $Digit = [char]::GetNumericValue($_)
            [int32] $ContentLength = "{0:d1}{1:d1}" -f $ContentLength, $Digit
        }
        Write-Host "ContentLength = $ContentLength"

        if (($ContentLength + 1) -gt $this.Stream.Length ) {
            throw "Unexpected end of string entity at offset $($this.Stream.Position)"
        }

        [System.String] $String = $Null
        $this.GetChars($ContentLength, $OffsetOfColon + 1) | ForEach-Object {
            [System.String] $CharAsString = $_.ToString()
            [System.String] $String = "{0}{1}" -f $String, $CharAsString
        }
        
        $this.AdvancePosition($OffsetOfColon + $ContentLength + 1)
        Write-Host "String is $String"
        return $String
    }

    [int] GetOffsetOfString([System.String] $String) {
        if ($String.Length -ne 1) {
            throw "$String has incompatible length of $($String.Length)"
        }

        $OffsetOfString = 1
        while ($True) {
            $StringChar = $this.GetCharAsString($OffsetOfString)
            if ($StringChar -eq $String) {
                break
            }
            elseif ($StringChar -eq $False) {
                $OffsetOfString = $False
                break
            }
            else {
                $OffsetOfString++
            }
        }
        Write-Host "Offset of $String is $OffsetOfString"
        return $OffsetOfString
    }

    [System.Object] CharsToType([char[]] $Chars, [string] $BencodeType) {
        [System.Object] $Value = $Null
        $Chars | ForEach-Object {
            $Char = $_
            switch ($BencodeType) {
                'string' {
                    [System.String] $String = $Char.ToString()
                    [System.String] $Value = "{0}{1}" -f $Value, $String
                    break
                }
                'integer' {
                    [double] $Integer = [char]::GetNumericValue($Char)
                    [double] $Value = "{0:G}{1:G}" -f $Value, $Integer
                    break
                }
                default {
                    throw "Unsupported type $BencodeType"
                }
            }
        }
        return $Value
    }
}