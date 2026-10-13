#lang "fb"

#include once "sha256.bas"
#include once "ir_lex.bas"
#include once "ir_parse.bas"
#include once "ir_vm.bas"

Function ReadFileText(ByRef path As String, ByRef text As String) As Integer
    Dim f As Integer
    Dim s As String
    f = FreeFile
    If Open(path For Input As #f) <> 0 Then Return 1
    text = ""
    While Not Eof(f)
        Line Input #f, s
        text &= s & Chr(10)
    Wend
    Close #f
    Return 0
End Function

Function Expect(ByVal cond As Integer, ByRef labelText As String) As Integer
    If cond = 0 Then
        Print "FAIL: "; labelText
        If gFault <> "" Then Print "  fault: "; gFault
        If gParseErr <> "" Then Print "  parse: "; gParseErr
        Return 1
    End If
    Print "PASS: "; labelText
    Return 0
End Function

Function RunSource(ByRef src As String) As Integer
    If ParseProgram(src) <> 0 Then Return 1
    If ExecuteProgram() <> 0 Then Return 1
    Return 0
End Function

Function SelfTest() As Integer
    Dim failed As Integer
    Dim src As String
    Dim outp(0 To 31) As UByte
    Dim empty(0 To 0) As UByte
    Dim abc(0 To 2) As UByte
    Dim i As Integer
    Dim digest As String
    failed = 0
    Sha256Digest(empty(), 0, outp())
    digest = ""
    For i = 0 To 31
        digest &= Hex(outp(i), 2)
    Next
    failed += Expect(IIf(digest = "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855", 1, 0), "sha256 empty")
    abc(0) = Asc("a")
    abc(1) = Asc("b")
    abc(2) = Asc("c")
    Sha256Digest(abc(), 3, outp())
    digest = ""
    For i = 0 To 31
        digest &= Hex(outp(i), 2)
    Next
    failed += Expect(IIf(digest = "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD", 1, 0), "sha256 abc")

    src = "10 LOAD R0, 17" & Chr(10) & "20 LOAD R1, 23" & Chr(10) & "30 MUL R2, R0, R1" & Chr(10) & "40 ADD R3, R2, 41" & Chr(10) & "50 CHECK R3" & Chr(10) & "60 SYSCALL CALCULATE, R3" & Chr(10) & "70 SEAL" & Chr(10) & "80 HALT" & Chr(10)
    failed += Expect(IIf(RunSource(src) = 0, 1, 0), "sample executes")
    failed += Expect(IIf(gReg(3) = 432, 1, 0), "sample result 432")
    failed += Expect(IIf(gRecN = 8, 1, 0), "sample record count")
    failed += Expect(VerifyMagazine(), "sample chain")

    src = "10 UNKNOWN R0, 1" & Chr(10)
    failed += Expect(IIf(ParseProgram(src) <> 0, 1, 0), "unknown opcode rejected")

    src = "10 LOAD R0, 1" & Chr(10) & "20 LOAD R1, 0" & Chr(10) & "30 DIV R2, R0, R1" & Chr(10) & "40 HALT" & Chr(10)
    failed += Expect(IIf(RunSource(src) <> 0, 1, 0), "division by zero rejected")

    src = "10 LOAD R0, 5" & Chr(10) & "20 STOREM R0, 4" & Chr(10) & "30 LOADM R1, 4" & Chr(10) & "40 HALT" & Chr(10)
    failed += Expect(IIf(RunSource(src) = 0 And gReg(1) = 5, 1, 0), "store and load memory")

    src = "10 LOAD R0, 1" & Chr(10) & "20 CMP R0, 1" & Chr(10) & "30 JZ 50" & Chr(10) & "40 LOAD R2, 9" & Chr(10) & "50 HALT" & Chr(10)
    failed += Expect(IIf(RunSource(src) = 0 And gReg(2) = 0, 1, 0), "jz taken skips load")

    src = "10 LOAD R0, 432" & Chr(10) & "20 SYSCALL CHECKSUM, R0" & Chr(10) & "30 HALT" & Chr(10)
    failed += Expect(IIf(RunSource(src) = 0, 1, 0), "checksum syscall runs")
    failed += Expect(IIf(CULngInt(gReg(0)) = (CULngInt(432) Xor ((CULngInt(&hA5A5A5A5) Shl 32) Or CULngInt(&hA5A5A5A5))), 1, 0), "checksum xor")

    src = "10 LOAD R0, 1" & Chr(10) & "20 HALT" & Chr(10)
    If RunSource(src) = 0 Then
        gMag(60) = gMag(60) Xor 1
        failed += Expect(IIf(VerifyMagazine() = 0, 1, 0), "tampered checksum rejected")
    Else
        failed += Expect(0, "tampered setup")
    End If

    If failed = 0 Then
        Print "summary pass"
        Return 0
    End If
    Print "summary fail "; failed
    Return 1
End Function

Sub Usage()
    Print "basic-ir run <program> [magazine]"
    Print "basic-ir verify <magazine>"
    Print "basic-ir selftest"
End Sub

Dim cmd As String
Dim path As String
Dim text As String
Dim code As Integer

cmd = Command(1)
If cmd = "selftest" Then
    End SelfTest()
ElseIf cmd = "run" Then
    path = Command(2)
    If path = "" Then
        Usage()
        End 1
    End If
    If ReadFileText(path, text) <> 0 Then
        Print "cannot read "; path
        End 1
    End If
    If ParseProgram(text) <> 0 Then
        Print gParseErr
        End 1
    End If
    If ExecuteProgram() <> 0 Then
        Print "fault: "; gFault
        End 1
    End If
    If VerifyMagazine() = 0 Then
        Print "fault: magazine chain"
        End 1
    End If
    Print "instructions "; gRecN
    Print "terminal "; Hex64(gChain)
    If Command(3) <> "" Then
        If SaveMagazine(Command(3)) <> 0 Then
            Print "cannot write magazine"
            End 1
        End If
    End If
    End 0
ElseIf cmd = "verify" Then
    path = Command(2)
    If path = "" Then
        Usage()
        End 1
    End If
    If LoadMagazine(path) <> 0 Then
        Print "cannot read magazine"
        End 1
    End If
    If VerifyMagazine() = 0 Then
        Print "verify: FAIL"
        End 1
    End If
    Print "verify: PASS"
    Print "records "; gRecN
    Print "terminal "; Hex64(GetU64At(gMag(), (gRecN - 1) * REC_SIZE + 60))
    End 0
Else
    Usage()
    End 1
End If
