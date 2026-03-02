# This exotic script was created by ChatGPT in 2026 after it was realised that trying to use
# the  Google GCSE script search was never going to work because Google was never going to
# index our archived pdf files. In any event, if we /did/ continue to use it, the website would
# be required to display a GDPR consent screen because GCSE introduces cookies.

# This script is parameterised and, for example, when run with a SourceFolder=newsletters parameter generates, for every
# newsletter pdf in Cloud storage, a corresponding entry in public/search_jsons/newsletters.json. Once deployed,
# this file is used to deliver an extremely fast in-core text search facility in Newsletters.jsx

# Permitted parameter values are:
#
#    newsletters
#    newslets
#    research_papers
#    minutes
#    event_writeups

# The first stage of the script refreshes a file of downloaded newsletter pdf files maintained
# in src/utilities/search_json_workfiles/newsletters/downloaded_pdfs. This adds any
# new files detected in the Firebase newsletters folder and replaces any that have changed

# The next stage is to use the pdftotext utility to create a text version of each newsletter pdf
# file and store this in src/utilities/search_json_workfiles/newsletters/downloaded_texts.

# But there's a snag. The earliest newsletter PDFs were scanned from paper copies rather
# than created by exporting word-processor docs. These newsletters are just pictures and
# can only be interpreted by OCR technology

# So, when the script detects a pdf file without obvious text content, it pre-processes it
# with an ocrmypdf utility that extracts text from graphic content and creates a "proper" pdf 
# pdf for pdftotext to process

# The result of all this is a src/utilities/search_json_workfiles/newsletters/downloaded_texts
# folder full of text files - one for each pdf newsletter in the AppArch newsletter archive. This
# is now turned into a public/search_jsons/newsletters.json file that is eventually made "live" by 
# rebuilding and redeploying the project.  Because the script only processes new or changed 
# files, the overheads thus created are minimal, so it forms part of the standard live build
# procedure

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "newsletters",
        "newslets",
        "research_papers",
        "minutes",
        "event_writeups"
    )]
    [string]$SourceFolder
)

function Convert-LayoutRunsToBlob([string]$s) {
    # Replace formatting characters by a "blob"
    if ([string]::IsNullOrEmpty($s)) { return $s }

    $blob = " ⟦…⟧ "

    # 1) Normalise NBSP to a regular space (common in PDF extraction)
    $s = $s -replace [char]0x00A0, ' '

    # 2) Replace any run that includes non-space whitespace (CR/LF/TAB/FF)
    #    optionally surrounded by spaces, with a blob.
    $s = $s -replace '[ ]*[\r\n\t\f]+[ \r\n\t\f]*', $blob

    # 3) Replace runs of 2+ spaces with a blob (keeps single spaces intact)
    $s = $s -replace '[ ]{2,}', $blob

    # 4) Collapse repeated blobs (in case rules above create adjacency)
    $escapedBlob = [regex]::Escape($blob.Trim())
    $s = $s -replace "(?:\s*$escapedBlob\s*){2,}", $blob

    # 5) Tidy ends
    return $s.Trim()
}

$projectRoot = "C:\Users\mjoyc\Desktop\GitProjects\apparchlive"
$workfileFolder = Join-Path `
    -Path "$projectRoot\src\utilities\search_json_workfiles" `
    -ChildPath $SourceFolder
$Bucket = "apparchlive.appspot.com"

$PdfRoot = "$workfileFolder\downloaded_pdfs"
$TextRoot = "$workfileFolder\downloaded_texts"

# $OutJson = "$projectRoot\public\search_jsons\downloaded_texts.json"
$OutJson = Join-Path `
    "$projectRoot\public\search_jsons" `
    "$SourceFolder.json"

$ErrorActionPreference = "Stop"

# Optional log
$logPath = "$workfileFolder\build_index.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"Log started at $timestamp" | Out-File -FilePath $logPath -Force

function Log($msg) {
    $line = "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")  $msg"
    $line | Out-File -FilePath $logPath -Append -Encoding UTF8
    Write-Host $msg
}

# --- Tool checks ---
if (-not (Get-Command gsutil -ErrorAction SilentlyContinue)) {
    throw "gsutil not found. Install Google Cloud SDK and ensure gsutil is on PATH."
}
if (-not (Get-Command pdftotext -ErrorAction SilentlyContinue)) {
    throw "pdftotext not found. Install Poppler/Xpdf tools and ensure pdftotext is on PATH."
}

# --- Ensure folders exist ---
New-Item -ItemType Directory -Force -Path $PdfRoot  | Out-Null
New-Item -ItemType Directory -Force -Path $TextRoot | Out-Null

# --- 1) Download PDFs recursively ---
# Mirrors bucket prefix into: newsletters\downloaded_pdfs\
# 
New-Item -ItemType Directory -Force -Path $PdfRoot | Out-Null

# Log "Downloading PDFs 
Log "Downloading PDFs from gs://$Bucket/$SourceFolder to $PdfRoot"

# rsync is repeatable and only transfers changes
& gsutil -m rsync -r "gs://$Bucket/$SourceFolder" "$PdfRoot" 2>&1 | ForEach-Object { Log $_ }

# --- 2) Run pdftotext for each PDF (only if needed) ---
Log "Extracting text with pdftotext into $TextRoot"

# Find all PDFs under downloaded_pdfs\newsletters
$pdfFiles = Get-ChildItem -Path $PdfRoot -Recurse -Filter *.pdf

foreach ($pdf in $pdfFiles) {

    # Relative path under downloaded_pdfs (e.g. newsletters\2024\foo.pdf)
    $relPdf = $pdf.FullName.Substring($PdfRoot.Length + 1)

    # Map to output text path (e.g. downloaded_texts\newsletters\2024\foo.txt)
    $txtPath = Join-Path $TextRoot ($relPdf -replace '\.pdf$', '.txt')

    # Ensure destination directory exists
    $txtDir = Split-Path -Parent $txtPath
    New-Item -ItemType Directory -Force -Path $txtDir | Out-Null

    # Only regenerate if missing or older than PDF
    $needs = $true
    if (Test-Path $txtPath) {
        $pdfTime = (Get-Item $pdf.FullName).LastWriteTimeUtc
        $txtTime = (Get-Item $txtPath).LastWriteTimeUtc
        if ($txtTime -ge $pdfTime) { $needs = $false }
    }

    if ($needs) {
        Log "pdftotext: $relPdf -> $($txtPath.Substring($TextRoot.Length + 1))"
        # -layout keeps something closer to the PDF’s layout; remove if you prefer plain flow
        # 1) Run pdftotext first
        & pdftotext -layout "$($pdf.FullName)" "$txtPath"

        # 2) Test output
        $raw = Get-Content -Path $txtPath -Raw
        $meaningful = $raw -replace '[\s\f]+', ''

        if ($meaningful.Length -eq 0) {

            Log "OCR required: $relPdf"

            $ocrPdf = Join-Path $pdf.DirectoryName ("ocr_" + $pdf.Name)

            # 3) Run OCR
            & ocrmypdf --tagged-pdf-mode ignore --force-ocr "$($pdf.FullName)" "$ocrPdf"
            # 4) Re-run pdftotext on OCR’d PDF
            & pdftotext -layout "$ocrPdf" "$txtPath"
        }
    }
    else {
        Log "Skipping (up-to-date): $relPdf"
    }
}

# --- 3) Build JSON index from downloaded_texts ---
Log "Building JSON index at $OutJson"

# Get all .txt files recursively
$files = Get-ChildItem -Path $TextRoot -Recurse -Filter *.txt

# Open output file and start JSON array
"[" | Out-File -FilePath $OutJson -Encoding UTF8 -Force

$first = $true

foreach ($file in $files) {

    # Read extracted text and replace formatting code
    $textRaw = Get-Content -Path $file.FullName -Raw
    $text = Convert-LayoutRunsToBlob $textRaw

    # Build filename: downloaded_texts\newsletters\2024\foo.txt -> newsletters/2024/foo.pdf
    $relative = $file.FullName.Substring($TextRoot.Length + 1)
    $filename = ($relative -replace '\\', '/') -replace '\.txt$', '.pdf'

    # Build object
    $obj = @{
        filename = $filename
        text     = $text
    }

    # Serialize
    $json = $obj | ConvertTo-Json -Compress

    # Write comma if needed
    if (-not $first) {
        "," | Out-File -FilePath $OutJson -Append -Encoding UTF8
    }
    $first = $false

    $json | Out-File -FilePath $OutJson -Append -Encoding UTF8

    Log "Indexed $filename"
}

# Close JSON array
"]" | Out-File -FilePath $OutJson -Append -Encoding UTF8

Log "Completed indexing $($files.Count) text files"
