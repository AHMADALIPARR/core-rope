import unittest
from rope import assemble,wiring,verify,run
class TestRope(unittest.TestCase):
    def test_demo(self):
        words=assemble('LDA VALUE\nADD ONE\nSTA RESULT\nHLT\nVALUE: DAT 41\nONE: DAT 1\nRESULT: DAT 0')
        self.assertTrue(verify(words,wiring(words)))
        result=run(words)
        self.assertEqual(result['ram'][6],42)
        self.assertEqual(words[6],0)
    def test_patterns(self):
        for word in [0,0xfff,0xaaa,0x555,1,0x800]:
            words=[word]*16
            self.assertTrue(verify(words,wiring(words)))
    def test_bounds(self):
        with self.assertRaises(ValueError): assemble('DAT 4096')
        with self.assertRaises(ValueError): assemble('JMP 16')
if __name__=='__main__':unittest.main()
