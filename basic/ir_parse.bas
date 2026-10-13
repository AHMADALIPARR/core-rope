Const OP_LOAD As Integer = 1
Const OP_MOVE As Integer = 2
Const OP_ADD As Integer = 3
Const OP_SUB As Integer = 4
Const OP_MUL As Integer = 5
Const OP_DIV As Integer = 6
Const OP_MOD As Integer = 7
Const OP_CMP As Integer = 8
Const OP_JMP As Integer = 9
Const OP_JZ As Integer = 10
Const OP_JNZ As Integer = 11
Const OP_LOADM As Integer = 12
Const OP_STOREM As Integer = 13
Const OP_CHECK As Integer = 14
Const OP_SYSCALL As Integer = 15
Const OP_SEAL As Integer = 16
Const OP_HALT As Integer = 255
Const MAX_INS As Integer = 256
Const MEM_WORDS As Integer = 4096

Type Ins
    lineNo As ULong
    opcode As Integer
    arg0 As LongInt
    arg1 As LongInt
    arg2 As LongInt
    flags As Integer
End Type

Dim Shared gIns(0 To MAX_INS - 1) As Ins
Dim Shared gInsN As Integer
Dim Shared gParseErr As String

Function NameToOpcode(ByRef nm As String) As Integer
    If nm = "LOAD" Then Return OP_LOAD
    If nm = "MOVE" Then Return OP_MOVE
    If nm = "ADD" Then Return OP_ADD
    If nm = "SUB" Then Return OP_SUB
    If nm = "MUL" Then Return OP_MUL
    If nm = "DIV" Then Return OP_DIV
    If nm = "MOD" Then Return OP_MOD
    If nm = "CMP" Then Return OP_CMP
    If nm = "JMP" Then Return OP_JMP
    If nm = "JZ" Then Return OP_JZ
    If nm = "JNZ" Then Return OP_JNZ
    If nm = "LOADM" Then Return OP_LOADM
    If nm = "STOREM" Then Return OP_STOREM
    If nm = "CHECK" Then Return OP_CHECK
    If nm = "SYSCALL" Then Return OP_SYSCALL
    If nm = "SEAL" Then Return OP_SEAL
    If nm = "HALT" Then Return OP_HALT
    Return 0
End Function

Function OpcodeName(ByVal op As Integer) As String
    If op = OP_LOAD Then Return "LOAD"
    If op = OP_MOVE Then Return "MOVE"
    If op = OP_ADD Then Return "ADD"
    If op = OP_SUB Then Return "SUB"
    If op = OP_MUL Then Return "MUL"
    If op = OP_DIV Then Return "DIV"
    If op = OP_MOD Then Return "MOD"
    If op = OP_CMP Then Return "CMP"
    If op = OP_JMP Then Return "JMP"
    If op = OP_JZ Then Return "JZ"
    If op = OP_JNZ Then Return "JNZ"
    If op = OP_LOADM Then Return "LOADM"
    If op = OP_STOREM Then Return "STOREM"
    If op = OP_CHECK Then Return "CHECK"
    If op = OP_SYSCALL Then Return "SYSCALL"
    If op = OP_SEAL Then Return "SEAL"
    If op = OP_HALT Then Return "HALT"
    Return "UNKNOWN"
End Function

Function SyscallIdOf(ByRef nm As String) As Integer
    If nm = "CALCULATE" Then Return 1
    If nm = "READ" Then Return 2
    If nm = "WRITE" Then Return 3
    If nm = "CHECKSUM" Then Return 4
    If nm = "SEAL" Then Return 5
    Return 0
End Function

Function ParseFail(ByRef msg As String, ByVal lineNo As Integer, ByVal col As Integer) As Integer
    gParseErr = "Parse error at " & Str(lineNo) & ":" & Str(col) & ": " & msg
    Return 1
End Function

Function ParseProgram(ByRef src As String) As Integer
    Dim i As Integer
    Dim lineNo As LongInt
    Dim nm As String
    Dim op As Integer
    gInsN = 0
    gParseErr = ""
    If LexSource(src) <> 0 Then
        gParseErr = gLexErr
        Return 1
    End If
    i = 0
    While i < gTokN And gTok(i).kind = TK_NL
        i += 1
    Wend
    While i < gTokN And gTok(i).kind <> TK_EOF
        If gTok(i).kind <> TK_NUM Then
            Return ParseFail("expected line number", gTok(i).line, gTok(i).col)
        End If
        lineNo = gTok(i).num
        If lineNo < 0 Or lineNo > 65535 Then
            Return ParseFail("line number out of range", gTok(i).line, gTok(i).col)
        End If
        Dim d As Integer
        For d = 0 To gInsN - 1
            If gIns(d).lineNo = CULng(lineNo) Then
                Return ParseFail("duplicate line number", gTok(i).line, gTok(i).col)
            End If
        Next
        i += 1
        If i >= gTokN Or gTok(i).kind <> TK_IDENT Then
            Return ParseFail("expected opcode", gTok(i).line, gTok(i).col)
        End If
        nm = gTok(i).text
        op = NameToOpcode(nm)
        If op = 0 Then
            Return ParseFail("unknown opcode: " & nm, gTok(i).line, gTok(i).col)
        End If
        i += 1
        If gInsN >= MAX_INS Then
            Return ParseFail("too many instructions", gTok(i).line, gTok(i).col)
        End If
        gIns(gInsN).lineNo = CULng(lineNo)
        gIns(gInsN).opcode = op
        gIns(gInsN).arg0 = 0
        gIns(gInsN).arg1 = 0
        gIns(gInsN).arg2 = 0
        gIns(gInsN).flags = 0
        If op = OP_LOAD Then
            If gTok(i).kind <> TK_REG Then Return ParseFail("expected register", gTok(i).line, gTok(i).col)
            gIns(gInsN).arg0 = gTok(i).num
            i += 1
            If gTok(i).kind <> TK_NUM Then Return ParseFail("expected immediate", gTok(i).line, gTok(i).col)
            gIns(gInsN).arg1 = gTok(i).num
            i += 1
        ElseIf op = OP_MOVE Or op = OP_CHECK Then
            If gTok(i).kind <> TK_REG Then Return ParseFail("expected register", gTok(i).line, gTok(i).col)
            gIns(gInsN).arg0 = gTok(i).num
            i += 1
            If op = OP_MOVE Then
                If gTok(i).kind <> TK_REG Then Return ParseFail("expected register", gTok(i).line, gTok(i).col)
                gIns(gInsN).arg1 = gTok(i).num
                i += 1
            End If
        ElseIf op = OP_ADD Or op = OP_SUB Or op = OP_MUL Or op = OP_DIV Or op = OP_MOD Then
            If gTok(i).kind <> TK_REG Then Return ParseFail("expected register", gTok(i).line, gTok(i).col)
            gIns(gInsN).arg0 = gTok(i).num
            i += 1
            If gTok(i).kind <> TK_REG Then Return ParseFail("expected register", gTok(i).line, gTok(i).col)
            gIns(gInsN).arg1 = gTok(i).num
            i += 1
            If gTok(i).kind = TK_REG Then
                gIns(gInsN).arg2 = gTok(i).num
                gIns(gInsN).flags = 0
                i += 1
            ElseIf gTok(i).kind = TK_NUM Then
                gIns(gInsN).arg2 = gTok(i).num
                gIns(gInsN).flags = 1
                i += 1
            Else
                Return ParseFail("expected register or number", gTok(i).line, gTok(i).col)
            End If
        ElseIf op = OP_CMP Then
            If gTok(i).kind <> TK_REG Then Return ParseFail("expected register", gTok(i).line, gTok(i).col)
            gIns(gInsN).arg0 = gTok(i).num
            i += 1
            If gTok(i).kind = TK_REG Then
                gIns(gInsN).arg1 = gTok(i).num
                gIns(gInsN).flags = 0
                i += 1
            ElseIf gTok(i).kind = TK_NUM Then
                gIns(gInsN).arg1 = gTok(i).num
                gIns(gInsN).flags = 1
                i += 1
            Else
                Return ParseFail("expected register or number", gTok(i).line, gTok(i).col)
            End If
        ElseIf op = OP_JMP Or op = OP_JZ Or op = OP_JNZ Then
            If gTok(i).kind <> TK_NUM Then Return ParseFail("expected line number", gTok(i).line, gTok(i).col)
            gIns(gInsN).arg0 = gTok(i).num
            i += 1
        ElseIf op = OP_LOADM Or op = OP_STOREM Then
            If gTok(i).kind <> TK_REG Then Return ParseFail("expected register", gTok(i).line, gTok(i).col)
            gIns(gInsN).arg0 = gTok(i).num
            i += 1
            If gTok(i).kind = TK_REG Then
                gIns(gInsN).arg1 = gTok(i).num
                gIns(gInsN).flags = 0
                i += 1
            ElseIf gTok(i).kind = TK_NUM Then
                gIns(gInsN).arg1 = gTok(i).num
                gIns(gInsN).flags = 1
                i += 1
            Else
                Return ParseFail("expected register or number", gTok(i).line, gTok(i).col)
            End If
        ElseIf op = OP_SYSCALL Then
            If gTok(i).kind <> TK_IDENT Then Return ParseFail("expected syscall nm", gTok(i).line, gTok(i).col)
            Dim sid As Integer
            sid = SyscallIdOf(gTok(i).text)
            If sid = 0 Then Return ParseFail("unknown syscall: " & gTok(i).text, gTok(i).line, gTok(i).col)
            gIns(gInsN).arg0 = sid
            i += 1
            If gTok(i).kind <> TK_REG Then Return ParseFail("expected register", gTok(i).line, gTok(i).col)
            gIns(gInsN).arg1 = gTok(i).num
            i += 1
        ElseIf op = OP_SEAL Or op = OP_HALT Then
            ' no operands
        End If
        If gTok(i).kind <> TK_NL And gTok(i).kind <> TK_EOF Then
            Return ParseFail("trailing tokens", gTok(i).line, gTok(i).col)
        End If
        gInsN += 1
        While i < gTokN And gTok(i).kind = TK_NL
            i += 1
        Wend
    Wend
    If gInsN = 0 Then
        gParseErr = "empty program"
        Return 1
    End If
    Return 0
End Function
