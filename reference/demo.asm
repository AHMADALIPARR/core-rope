; The immutable ROM contains code and constants; STA writes only to shadow RAM.
START: LDA VALUE
       ADD ONE
       STA RESULT
       HLT
VALUE: DAT 41
ONE:   DAT 1
RESULT: DAT 0
