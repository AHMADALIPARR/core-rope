Const TK_EOF As Integer = 0
Const TK_NUM As Integer = 1
Const TK_IDENT As Integer = 2
Const TK_REG As Integer = 3
Const TK_NL As Integer = 4
Const TK_ERR As Integer = 5
Const MAX_TOK As Integer = 8192

Type Tok
    kind As Integer
    text As String
    num As LongInt
    line As Integer
    col As Integer
End Type

Dim Shared gTok(0 To MAX_TOK - 1) As Tok
Dim Shared gTokN As Integer
Dim Shared gLexErr As String

Function IsDigitCh(ByVal c As Integer) As Integer
    If c >= Asc("0") And c <= Asc("9") Then Return 1
    Return 0
End Function

Function IsAlphaCh(ByVal c As Integer) As Integer
    If c >= Asc("A") And c <= Asc("Z") Then Return 1
    If c >= Asc("a") And c <= Asc("z") Then Return 1
    If c = Asc("_") Then Return 1
    Return 0
End Function

Function IsAlnumCh(ByVal c As Integer) As Integer
    If IsAlphaCh(c) <> 0 Then Return 1
    If IsDigitCh(c) <> 0 Then Return 1
    Return 0
End Function

Function UpperCopy(ByRef s As String) As String
    Dim i As Integer
    Dim c As Integer
    Dim outp As String
    outp = s
    For i = 1 To Len(outp)
        c = Asc(Mid(outp, i, 1))
        If c >= Asc("a") And c <= Asc("z") Then
            Mid(outp, i, 1) = Chr(c - 32)
        End If
    Next
    Return outp
End Function

Sub PushTok(ByVal kind As Integer, ByRef text As String, ByVal num As LongInt, ByVal lineNo As Integer, ByVal col As Integer)
    If gTokN >= MAX_TOK Then
        gLexErr = "too many tokens"
        Return
    End If
    gTok(gTokN).kind = kind
    gTok(gTokN).text = text
    gTok(gTokN).num = num
    gTok(gTokN).line = lineNo
    gTok(gTokN).col = col
    gTokN += 1
End Sub

Function LexSource(ByRef src As String) As Integer
    Dim i As Integer
    Dim n As Integer
    Dim lineNo As Integer
    Dim col As Integer
    Dim c As Integer
    Dim startCol As Integer
    Dim text As String
    Dim sign As LongInt
    Dim value As LongInt
    Dim digit As Integer
    Dim regn As Integer
    Dim upper As String
    gTokN = 0
    gLexErr = ""
    i = 1
    n = Len(src)
    lineNo = 1
    col = 1
    While i <= n
        c = Asc(Mid(src, i, 1))
        If c = 32 Or c = 9 Or c = 13 Then
            i += 1
            col += 1
            Continue While
        End If
        If c = 10 Then
            PushTok(TK_NL, "", 0, lineNo, col)
            i += 1
            lineNo += 1
            col = 1
            Continue While
        End If
        If c = Asc("#") Then
            While i <= n And Asc(Mid(src, i, 1)) <> 10
                i += 1
            Wend
            Continue While
        End If
        If c = Asc(",") Then
            i += 1
            col += 1
            Continue While
        End If
        If (c = Asc("R") Or c = Asc("r")) And i + 2 <= n Then
            If (Asc(Mid(src, i + 1, 1)) = Asc("E") Or Asc(Mid(src, i + 1, 1)) = Asc("e")) And (Asc(Mid(src, i + 2, 1)) = Asc("M") Or Asc(Mid(src, i + 2, 1)) = Asc("m")) Then
                If i + 3 > n Or IsAlnumCh(Asc(Mid(src, i + 3, 1))) = 0 Then
                    i += 3
                    While i <= n And Asc(Mid(src, i, 1)) <> 10
                        i += 1
                    Wend
                    Continue While
                End If
            End If
        End If
        startCol = col
        If IsDigitCh(c) <> 0 Or ((c = Asc("+") Or c = Asc("-")) And i < n And IsDigitCh(Asc(Mid(src, i + 1, 1))) <> 0) Then
            sign = 1
            value = 0
            If c = Asc("+") Or c = Asc("-") Then
                If c = Asc("-") Then sign = -1
                i += 1
                col += 1
            End If
            While i <= n And IsDigitCh(Asc(Mid(src, i, 1))) <> 0
                digit = Asc(Mid(src, i, 1)) - Asc("0")
                If value > (&h7FFFFFFFFFFFFFFFLL \ 10) Then
                    gLexErr = "number out of range"
                    Return 1
                End If
                value = value * 10 + digit
                i += 1
                col += 1
            Wend
            value = value * sign
            PushTok(TK_NUM, Str(value), value, lineNo, startCol)
            Continue While
        End If
        If IsAlphaCh(c) <> 0 Then
            text = ""
            While i <= n And IsAlnumCh(Asc(Mid(src, i, 1))) <> 0
                text &= Mid(src, i, 1)
                i += 1
                col += 1
            Wend
            upper = UpperCopy(text)
            If Left(upper, 1) = "R" And Len(upper) > 1 Then
                regn = 0
                Dim okReg As Integer
                Dim k As Integer
                okReg = 1
                For k = 2 To Len(upper)
                    If IsDigitCh(Asc(Mid(upper, k, 1))) = 0 Then okReg = 0
                Next
                If okReg = 1 Then
                    regn = ValInt(Mid(upper, 2))
                    If regn >= 0 And regn <= 31 Then
                        PushTok(TK_REG, upper, regn, lineNo, startCol)
                    Else
                        PushTok(TK_ERR, text, 0, lineNo, startCol)
                        gLexErr = "invalid register " & upper
                        Return 1
                    End If
                    Continue While
                End If
            End If
            PushTok(TK_IDENT, upper, 0, lineNo, startCol)
            Continue While
        End If
        gLexErr = "bad character"
        PushTok(TK_ERR, Chr(c), 0, lineNo, col)
        Return 1
    Wend
    PushTok(TK_EOF, "", 0, lineNo, col)
    If gLexErr <> "" Then Return 1
    Return 0
End Function
