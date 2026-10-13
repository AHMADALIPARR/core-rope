Function Rotr32(ByVal x As ULong, ByVal n As Integer) As ULong
    Return (x Shr n) Or (x Shl (32 - n))
End Function

Function Shr32(ByVal x As ULong, ByVal n As Integer) As ULong
    Return x Shr n
End Function

Sub Sha256Init(ByRef h0 As ULong, ByRef h1 As ULong, ByRef h2 As ULong, ByRef h3 As ULong, ByRef h4 As ULong, ByRef h5 As ULong, ByRef h6 As ULong, ByRef h7 As ULong)
    h0 = &h6a09e667
    h1 = &hbb67ae85
    h2 = &h3c6ef372
    h3 = &ha54ff53a
    h4 = &h510e527f
    h5 = &h9b05688c
    h6 = &h1f83d9ab
    h7 = &h5be0cd19
End Sub

Sub Sha256LoadK(k() As ULong)
    k(0) = &h428a2f98
    k(1) = &h71374491
    k(2) = &hb5c0fbcf
    k(3) = &he9b5dba5
    k(4) = &h3956c25b
    k(5) = &h59f111f1
    k(6) = &h923f82a4
    k(7) = &hab1c5ed5
    k(8) = &hd807aa98
    k(9) = &h12835b01
    k(10) = &h243185be
    k(11) = &h550c7dc3
    k(12) = &h72be5d74
    k(13) = &h80deb1fe
    k(14) = &h9bdc06a7
    k(15) = &hc19bf174
    k(16) = &he49b69c1
    k(17) = &hefbe4786
    k(18) = &h0fc19dc6
    k(19) = &h240ca1cc
    k(20) = &h2de92c6f
    k(21) = &h4a7484aa
    k(22) = &h5cb0a9dc
    k(23) = &h76f988da
    k(24) = &h983e5152
    k(25) = &ha831c66d
    k(26) = &hb00327c8
    k(27) = &hbf597fc7
    k(28) = &hc6e00bf3
    k(29) = &hd5a79147
    k(30) = &h06ca6351
    k(31) = &h14292967
    k(32) = &h27b70a85
    k(33) = &h2e1b2138
    k(34) = &h4d2c6dfc
    k(35) = &h53380d13
    k(36) = &h650a7354
    k(37) = &h766a0abb
    k(38) = &h81c2c92e
    k(39) = &h92722c85
    k(40) = &ha2bfe8a1
    k(41) = &ha81a664b
    k(42) = &hc24b8b70
    k(43) = &hc76c51a3
    k(44) = &hd192e819
    k(45) = &hd6990624
    k(46) = &hf40e3585
    k(47) = &h106aa070
    k(48) = &h19a4c116
    k(49) = &h1e376c08
    k(50) = &h2748774c
    k(51) = &h34b0bcb5
    k(52) = &h391c0cb3
    k(53) = &h4ed8aa4a
    k(54) = &h5b9cca4f
    k(55) = &h682e6ff3
    k(56) = &h748f82ee
    k(57) = &h78a5636f
    k(58) = &h84c87814
    k(59) = &h8cc70208
    k(60) = &h90befffa
    k(61) = &ha4506ceb
    k(62) = &hbef9a3f7
    k(63) = &hc67178f2
End Sub

Sub Sha256Compress(ByRef h0 As ULong, ByRef h1 As ULong, ByRef h2 As ULong, ByRef h3 As ULong, ByRef h4 As ULong, ByRef h5 As ULong, ByRef h6 As ULong, ByRef h7 As ULong, block() As UByte, ByVal offset As Integer)
    Dim k(0 To 63) As ULong
    Dim w(0 To 63) As ULong
    Dim t As Integer
    Dim s0 As ULong
    Dim s1 As ULong
    Dim a As ULong
    Dim b As ULong
    Dim c As ULong
    Dim d As ULong
    Dim e As ULong
    Dim f As ULong
    Dim g As ULong
    Dim h As ULong
    Dim sig0 As ULong
    Dim sig1 As ULong
    Dim chv As ULong
    Dim majv As ULong
    Dim t1 As ULong
    Dim t2 As ULong
    Sha256LoadK(k())
    For t = 0 To 15
        w(t) = (CULng(block(offset + t * 4)) Shl 24) Or (CULng(block(offset + t * 4 + 1)) Shl 16) Or (CULng(block(offset + t * 4 + 2)) Shl 8) Or CULng(block(offset + t * 4 + 3))
    Next
    For t = 16 To 63
        s0 = Rotr32(w(t - 15), 7) Xor Rotr32(w(t - 15), 18) Xor Shr32(w(t - 15), 3)
        s1 = Rotr32(w(t - 2), 17) Xor Rotr32(w(t - 2), 19) Xor Shr32(w(t - 2), 10)
        w(t) = w(t - 16) + s0 + w(t - 7) + s1
    Next
    a = h0
    b = h1
    c = h2
    d = h3
    e = h4
    f = h5
    g = h6
    h = h7
    For t = 0 To 63
        sig1 = Rotr32(e, 6) Xor Rotr32(e, 11) Xor Rotr32(e, 25)
        chv = (e And f) Xor ((Not e) And g)
        t1 = h + sig1 + chv + k(t) + w(t)
        sig0 = Rotr32(a, 2) Xor Rotr32(a, 13) Xor Rotr32(a, 22)
        majv = (a And b) Xor (a And c) Xor (b And c)
        t2 = sig0 + majv
        h = g
        g = f
        f = e
        e = d + t1
        d = c
        c = b
        b = a
        a = t1 + t2
    Next
    h0 += a
    h1 += b
    h2 += c
    h3 += d
    h4 += e
    h5 += f
    h6 += g
    h7 += h
End Sub

Sub Sha256Digest(msg() As UByte, ByVal n As Integer, outp() As UByte)
    Dim h0 As ULong
    Dim h1 As ULong
    Dim h2 As ULong
    Dim h3 As ULong
    Dim h4 As ULong
    Dim h5 As ULong
    Dim h6 As ULong
    Dim h7 As ULong
    Dim bitLen As ULongInt
    Dim paddedLen As Integer
    Dim i As Integer
    Dim block(0 To 127) As UByte
    Dim b As Integer
    Sha256Init(h0, h1, h2, h3, h4, h5, h6, h7)
    bitLen = CULngInt(n) * 8
    paddedLen = ((n + 9 + 63) \ 64) * 64
    If paddedLen > 128 Then
        paddedLen = 128
    End If
    For i = 0 To paddedLen - 1
        block(i) = 0
    Next
    For i = 0 To n - 1
        block(i) = msg(i)
    Next
    block(n) = &h80
    For i = 0 To 7
        block(paddedLen - 1 - i) = CUByte((bitLen Shr (i * 8)) And &hFF)
    Next
    b = 0
    While b < paddedLen
        Sha256Compress(h0, h1, h2, h3, h4, h5, h6, h7, block(), b)
        b += 64
    Wend
    outp(0) = CUByte((h0 Shr 24) And &hFF)
    outp(1) = CUByte((h0 Shr 16) And &hFF)
    outp(2) = CUByte((h0 Shr 8) And &hFF)
    outp(3) = CUByte(h0 And &hFF)
    outp(4) = CUByte((h1 Shr 24) And &hFF)
    outp(5) = CUByte((h1 Shr 16) And &hFF)
    outp(6) = CUByte((h1 Shr 8) And &hFF)
    outp(7) = CUByte(h1 And &hFF)
    outp(8) = CUByte((h2 Shr 24) And &hFF)
    outp(9) = CUByte((h2 Shr 16) And &hFF)
    outp(10) = CUByte((h2 Shr 8) And &hFF)
    outp(11) = CUByte(h2 And &hFF)
    outp(12) = CUByte((h3 Shr 24) And &hFF)
    outp(13) = CUByte((h3 Shr 16) And &hFF)
    outp(14) = CUByte((h3 Shr 8) And &hFF)
    outp(15) = CUByte(h3 And &hFF)
    outp(16) = CUByte((h4 Shr 24) And &hFF)
    outp(17) = CUByte((h4 Shr 16) And &hFF)
    outp(18) = CUByte((h4 Shr 8) And &hFF)
    outp(19) = CUByte(h4 And &hFF)
    outp(20) = CUByte((h5 Shr 24) And &hFF)
    outp(21) = CUByte((h5 Shr 16) And &hFF)
    outp(22) = CUByte((h5 Shr 8) And &hFF)
    outp(23) = CUByte(h5 And &hFF)
    outp(24) = CUByte((h6 Shr 24) And &hFF)
    outp(25) = CUByte((h6 Shr 16) And &hFF)
    outp(26) = CUByte((h6 Shr 8) And &hFF)
    outp(27) = CUByte(h6 And &hFF)
    outp(28) = CUByte((h7 Shr 24) And &hFF)
    outp(29) = CUByte((h7 Shr 16) And &hFF)
    outp(30) = CUByte((h7 Shr 8) And &hFF)
    outp(31) = CUByte(h7 And &hFF)
End Sub

Function DigestPrefix(outp() As UByte) As ULongInt
    Dim v As ULongInt
    Dim i As Integer
    v = 0
    For i = 7 To 0 Step -1
        v = (v Shl 8) Or CULngInt(outp(i))
    Next
    Return v
End Function
