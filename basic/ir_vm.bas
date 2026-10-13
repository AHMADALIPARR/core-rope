Const REC_SIZE As Integer = 68
Const MAX_STEPS As Integer = 10000
Const MAG_BYTES As Integer = REC_SIZE * MAX_INS

Dim Shared gReg(0 To 31) As LongInt
Dim Shared gMem(0 To MEM_WORDS - 1) As LongInt
Dim Shared gCmpFlag As LongInt
Dim Shared gHalted As Integer
Dim Shared gSealed As Integer
Dim Shared gFault As String
Dim Shared gMag(0 To MAG_BYTES - 1) As UByte
Dim Shared gRecN As Integer
Dim Shared gChain As ULongInt

Function H0Value() As ULongInt
    Return (CULngInt(&hDEADBEEF) Shl 32) Or CULngInt(&hCAFEBABE)
End Function

Sub PutU16At(buf() As UByte, ByVal at As Integer, ByVal v As Integer)
    buf(at) = CUByte(v And &hFF)
    buf(at + 1) = CUByte((v Shr 8) And &hFF)
End Sub

Sub PutU32At(buf() As UByte, ByVal at As Integer, ByVal v As ULong)
    Dim i As Integer
    Dim u As ULong
    u = v
    For i = 0 To 3
        buf(at + i) = CUByte(u And &hFF)
        u = u Shr 8
    Next
End Sub

Sub PutU64At(buf() As UByte, ByVal at As Integer, ByVal v As ULongInt)
    Dim i As Integer
    Dim u As ULongInt
    u = v
    For i = 0 To 7
        buf(at + i) = CUByte(u And &hFF)
        u = u Shr 8
    Next
End Sub

Sub PutI64At(buf() As UByte, ByVal at As Integer, ByVal v As LongInt)
    PutU64At(buf(), at, CULngInt(v))
End Sub

Function GetU64At(buf() As UByte, ByVal at As Integer) As ULongInt
    Dim i As Integer
    Dim u As ULongInt
    u = 0
    For i = 7 To 0 Step -1
        u = (u Shl 8) Or CULngInt(buf(at + i))
    Next
    Return u
End Function

Function GetI64At(buf() As UByte, ByVal at As Integer) As LongInt
    Return CLngInt(GetU64At(buf(), at))
End Function

Function GetU32At(buf() As UByte, ByVal at As Integer) As ULong
    Return CULng(buf(at)) Or (CULng(buf(at + 1)) Shl 8) Or (CULng(buf(at + 2)) Shl 16) Or (CULng(buf(at + 3)) Shl 24)
End Function

Function GetU16At(buf() As UByte, ByVal at As Integer) As Integer
    Return buf(at) Or (buf(at + 1) Shl 8)
End Function

Function ChecksumOf(ByVal prev As ULongInt, ByVal seq As ULongInt, ByVal pc As ULong, ByVal opcode As Integer, ByVal a0 As LongInt, ByVal a1 As LongInt, ByVal a2 As LongInt, ByVal result As LongInt) As ULongInt
    Dim msg(0 To 53) As UByte
    Dim outp(0 To 31) As UByte
    Dim i As Integer
    For i = 0 To 53
        msg(i) = 0
    Next
    PutU64At(msg(), 0, prev)
    PutU32At(msg(), 8, pc)
    PutU16At(msg(), 12, opcode)
    PutI64At(msg(), 14, a0)
    PutI64At(msg(), 22, a1)
    PutI64At(msg(), 30, a2)
    PutI64At(msg(), 38, result)
    PutU64At(msg(), 46, seq)
    Sha256Digest(msg(), 54, outp())
    Return DigestPrefix(outp())
End Function

Sub ClearMachine()
    Dim i As Integer
    For i = 0 To 31
        gReg(i) = 0
    Next
    For i = 0 To MEM_WORDS - 1
        gMem(i) = 0
    Next
    gCmpFlag = 0
    gHalted = 0
    gSealed = 0
    gFault = ""
    gRecN = 0
    gChain = H0Value()
    For i = 0 To MAG_BYTES - 1
        gMag(i) = 0
    Next
End Sub

Function FindLineIndex(ByVal lineNo As LongInt) As Integer
    Dim i As Integer
    For i = 0 To gInsN - 1
        If gIns(i).lineNo = CULng(lineNo) Then Return i
    Next
    Return -1
End Function

Function RegOk(ByVal r As LongInt) As Integer
    If r >= 0 And r <= 31 Then Return 1
    Return 0
End Function

Function AppendRecord(ByVal pc As ULong, ByVal opcode As Integer, ByVal flags As Integer, ByVal a0 As LongInt, ByVal a1 As LongInt, ByVal a2 As LongInt, ByVal result As LongInt) As Integer
    Dim seq As ULongInt
    Dim prev As ULongInt
    Dim cs As ULongInt
    Dim at As Integer
    If gRecN >= MAX_INS Then
        gFault = "magazine full"
        Return 1
    End If
    seq = CULngInt(gRecN + 1)
    prev = gChain
    cs = ChecksumOf(prev, seq, pc, opcode, a0, a1, a2, result)
    at = gRecN * REC_SIZE
    PutU32At(gMag(), at, 1)
    PutU64At(gMag(), at + 4, seq)
    PutU32At(gMag(), at + 12, pc)
    PutU16At(gMag(), at + 16, opcode)
    PutU16At(gMag(), at + 18, flags)
    PutI64At(gMag(), at + 20, a0)
    PutI64At(gMag(), at + 28, a1)
    PutI64At(gMag(), at + 36, a2)
    PutI64At(gMag(), at + 44, result)
    PutU64At(gMag(), at + 52, prev)
    PutU64At(gMag(), at + 60, cs)
    gChain = cs
    gRecN += 1
    Return 0
End Function

Function OperandValue(ByVal flags As Integer, ByVal regOrImm As LongInt) As LongInt
    If (flags And 1) <> 0 Then Return regOrImm
    Return gReg(CInt(regOrImm))
End Function

Function ExecuteProgram() As Integer
    Dim pc As Integer
    Dim steps As Integer
    Dim op As Integer
    Dim dest As Integer
    Dim a As LongInt
    Dim b As LongInt
    Dim result As LongInt
    Dim addr As LongInt
    Dim nextPc As Integer
    Dim sid As Integer
    ClearMachine()
    pc = 0
    steps = 0
    While pc < gInsN And gHalted = 0
        steps += 1
        If steps > MAX_STEPS Then
            gFault = "step limit"
            Return 1
        End If
        op = gIns(pc).opcode
        nextPc = pc + 1
        result = 0
        If op = OP_LOAD Then
            If RegOk(gIns(pc).arg0) = 0 Then
                gFault = "invalid register"
                Return 1
            End If
            dest = CInt(gIns(pc).arg0)
            result = gIns(pc).arg1
            gReg(dest) = result
        ElseIf op = OP_MOVE Then
            If RegOk(gIns(pc).arg0) = 0 Or RegOk(gIns(pc).arg1) = 0 Then
                gFault = "invalid register"
                Return 1
            End If
            result = gReg(CInt(gIns(pc).arg1))
            gReg(CInt(gIns(pc).arg0)) = result
        ElseIf op = OP_ADD Or op = OP_SUB Or op = OP_MUL Or op = OP_DIV Or op = OP_MOD Then
            If RegOk(gIns(pc).arg0) = 0 Or RegOk(gIns(pc).arg1) = 0 Then
                gFault = "invalid register"
                Return 1
            End If
            If (gIns(pc).flags And 1) = 0 And RegOk(gIns(pc).arg2) = 0 Then
                gFault = "invalid register"
                Return 1
            End If
            a = gReg(CInt(gIns(pc).arg1))
            b = OperandValue(gIns(pc).flags, gIns(pc).arg2)
            If (op = OP_DIV Or op = OP_MOD) And b = 0 Then
                gFault = "division by zero"
                Return 1
            End If
            If op = OP_ADD Then
                result = a + b
            ElseIf op = OP_SUB Then
                result = a - b
            ElseIf op = OP_MUL Then
                result = a * b
            ElseIf op = OP_DIV Then
                result = a \ b
            Else
                result = a Mod b
            End If
            gReg(CInt(gIns(pc).arg0)) = result
        ElseIf op = OP_CMP Then
            If RegOk(gIns(pc).arg0) = 0 Then
                gFault = "invalid register"
                Return 1
            End If
            If (gIns(pc).flags And 1) = 0 And RegOk(gIns(pc).arg1) = 0 Then
                gFault = "invalid register"
                Return 1
            End If
            a = gReg(CInt(gIns(pc).arg0))
            If (gIns(pc).flags And 1) <> 0 Then
                b = gIns(pc).arg1
            Else
                b = gReg(CInt(gIns(pc).arg1))
            End If
            If a > b Then
                result = 1
            ElseIf a < b Then
                result = -1
            Else
                result = 0
            End If
            gCmpFlag = result
        ElseIf op = OP_JMP Or op = OP_JZ Or op = OP_JNZ Then
            Dim take As Integer
            take = 0
            If op = OP_JMP Then take = 1
            If op = OP_JZ And gCmpFlag = 0 Then take = 1
            If op = OP_JNZ And gCmpFlag <> 0 Then take = 1
            If take = 1 Then
                nextPc = FindLineIndex(gIns(pc).arg0)
                If nextPc < 0 Then
                    gFault = "jump to missing line"
                    Return 1
                End If
                result = gIns(pc).arg0
            Else
                result = 0
            End If
        ElseIf op = OP_LOADM Then
            If RegOk(gIns(pc).arg0) = 0 Then
                gFault = "invalid register"
                Return 1
            End If
            If (gIns(pc).flags And 1) <> 0 Then
                addr = gIns(pc).arg1
            Else
                If RegOk(gIns(pc).arg1) = 0 Then
                    gFault = "invalid register"
                    Return 1
                End If
                addr = gReg(CInt(gIns(pc).arg1))
            End If
            If addr < 0 Or addr >= MEM_WORDS Then
                gFault = "invalid memory address"
                Return 1
            End If
            result = gMem(CInt(addr))
            gReg(CInt(gIns(pc).arg0)) = result
        ElseIf op = OP_STOREM Then
            If RegOk(gIns(pc).arg0) = 0 Then
                gFault = "invalid register"
                Return 1
            End If
            If (gIns(pc).flags And 1) <> 0 Then
                addr = gIns(pc).arg1
            Else
                If RegOk(gIns(pc).arg1) = 0 Then
                    gFault = "invalid register"
                    Return 1
                End If
                addr = gReg(CInt(gIns(pc).arg1))
            End If
            If addr < 0 Or addr >= MEM_WORDS Then
                gFault = "invalid memory address"
                Return 1
            End If
            result = gReg(CInt(gIns(pc).arg0))
            gMem(CInt(addr)) = result
        ElseIf op = OP_CHECK Then
            If RegOk(gIns(pc).arg0) = 0 Then
                gFault = "invalid register"
                Return 1
            End If
            result = gReg(CInt(gIns(pc).arg0))
        ElseIf op = OP_SYSCALL Then
            If RegOk(gIns(pc).arg1) = 0 Then
                gFault = "invalid register"
                Return 1
            End If
            sid = CInt(gIns(pc).arg0)
            a = gReg(CInt(gIns(pc).arg1))
            If sid = 1 Then
                result = a
            ElseIf sid = 2 Then
                If a < 0 Or a >= MEM_WORDS Then
                    gFault = "READ invalid address"
                    Return 1
                End If
                result = a
            ElseIf sid = 3 Then
                result = a
            ElseIf sid = 4 Then
                result = CLngInt(CULngInt(a) Xor ((CULngInt(&hA5A5A5A5) Shl 32) Or CULngInt(&hA5A5A5A5)))
            ElseIf sid = 5 Then
                result = a
                gSealed = 1
            Else
                gFault = "unknown syscall"
                Return 1
            End If
            gReg(CInt(gIns(pc).arg1)) = result
        ElseIf op = OP_SEAL Then
            result = 1
            gSealed = 1
        ElseIf op = OP_HALT Then
            result = 0
            gHalted = 1
        Else
            gFault = "invalid opcode"
            Return 1
        End If
        If AppendRecord(gIns(pc).lineNo, op, gIns(pc).flags, gIns(pc).arg0, gIns(pc).arg1, gIns(pc).arg2, result) <> 0 Then
            Return 1
        End If
        pc = nextPc
    Wend
    Return 0
End Function

Function VerifyMagazine() As Integer
    Dim i As Integer
    Dim at As Integer
    Dim prev As ULongInt
    Dim seq As ULongInt
    Dim pc As ULong
    Dim opcode As Integer
    Dim flags As Integer
    Dim a0 As LongInt
    Dim a1 As LongInt
    Dim a2 As LongInt
    Dim result As LongInt
    Dim storedPrev As ULongInt
    Dim storedCs As ULongInt
    Dim expect As ULongInt
    Dim version As ULong
    prev = H0Value()
    For i = 0 To gRecN - 1
        at = i * REC_SIZE
        version = GetU32At(gMag(), at)
        If version <> 1 Then Return 0
        seq = GetU64At(gMag(), at + 4)
        If seq <> CULngInt(i + 1) Then Return 0
        pc = GetU32At(gMag(), at + 12)
        opcode = GetU16At(gMag(), at + 16)
        flags = GetU16At(gMag(), at + 18)
        a0 = GetI64At(gMag(), at + 20)
        a1 = GetI64At(gMag(), at + 28)
        a2 = GetI64At(gMag(), at + 36)
        result = GetI64At(gMag(), at + 44)
        storedPrev = GetU64At(gMag(), at + 52)
        storedCs = GetU64At(gMag(), at + 60)
        If storedPrev <> prev Then Return 0
        expect = ChecksumOf(prev, seq, pc, opcode, a0, a1, a2, result)
        If expect <> storedCs Then Return 0
        prev = storedCs
    Next
    Return 1
End Function

Function Hex64(ByVal v As ULongInt) As String
    Dim s As String
    Dim i As Integer
    Dim nib As Integer
    s = ""
    For i = 15 To 0 Step -1
        nib = CInt((v Shr (i * 4)) And &hF)
        If nib < 10 Then
            s &= Chr(Asc("0") + nib)
        Else
            s &= Chr(Asc("a") + nib - 10)
        End If
    Next
    Return s
End Function

Function SaveMagazine(ByRef path As String) As Integer
    Dim f As Integer
    Dim n As Integer
    f = FreeFile
    If Open(path For Binary Access Write As #f) <> 0 Then Return 1
    n = gRecN * REC_SIZE
    If n > 0 Then Put #f, , gMag(0), n
    Close #f
    Return 0
End Function

Function LoadMagazine(ByRef path As String) As Integer
    Dim f As Integer
    Dim n As Long
    f = FreeFile
    If Open(path For Binary Access Read As #f) <> 0 Then Return 1
    n = Lof(f)
    If n < 0 Or (n Mod REC_SIZE) <> 0 Or n > MAG_BYTES Then
        Close #f
        Return 1
    End If
    gRecN = CInt(n \ REC_SIZE)
    If n > 0 Then Get #f, , gMag(0), CInt(n)
    Close #f
    Return 0
End Function
