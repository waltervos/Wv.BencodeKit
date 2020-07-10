# Wv.BencodeKit
Wv.Bencodekit was born because I wanted to work with torrent files in PowerShell. It was based on @rchouinard's bencode library for PHP. Eventhough it was meant for working with torrent files, it should work equally well for any file with bencoded data.

## Usage ##
To use Wv.Bencodekit, download this repo and place the Wv.Bencodekit subfolder anywhere you like on your system. Open a PowerShell session and import the module by typing `Import-Module 'Location\Of\Module\Wv.Bencodekit'`. Then parse a torrent file by entering `$Torrent = ConvertFrom-BencodedFile -FilePath 'Path\To\MyTorrentFile.torrent'`

Torrent files should be dictionaries, so `$Torrent` is now a hashtable with keys such as 'info', 'announce-list' and so on. Read more about the possible contents of a torrent file here: https://wiki.theory.org/index.php/BitTorrentSpecification#Metainfo_File_Structure.

Strings are represented as both an array of `[Byte]` objects, as well as a decoded string. So, to access the announce URL as text use `$Torrent.announce.string`, and to access the bytes contained in info.pieces use `$Torrent.info.pieces.bytestring`.

## To do's ##
* Write unit tests
* Create a CI pipeline to run unit tests
* Create a CD pipeline to publish the model to powershellgallery.com
