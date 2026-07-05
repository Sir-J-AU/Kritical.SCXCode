"""Offline unit tests for Invoke-KritScxMuxMatrix.py (SCX-drafted, operator-lensed .5231).

Pure-logic only — no SCX network calls. Run:  python mux/Invoke-KritScxMuxMatrix.test.py
Stdlib unittest (zero deps) so it runs anywhere. The module has an `if __name__ == "__main__"`
guard, so loading it by path does not fire main().
"""
import importlib.util
import pathlib
import unittest

MODULE_PATH = pathlib.Path(__file__).parent / "Invoke-KritScxMuxMatrix.py"
_spec = importlib.util.spec_from_file_location("invoke_mux", MODULE_PATH)
mux = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mux)


class TestModelCeilings(unittest.TestCase):
    def test_structure(self):
        required = {"real_ctx_tokens", "reserve_out", "safety_tokens", "chars_per_token"}
        self.assertTrue(mux.MODEL_CEILINGS)
        for model, spec in mux.MODEL_CEILINGS.items():
            self.assertIsInstance(model, str)
            self.assertTrue(required.issubset(spec.keys()), f"{model} missing keys")
            for k in required:
                self.assertIsInstance(spec[k], int)
                self.assertGreater(spec[k], 0)
            self.assertEqual(spec["chars_per_token"], 4)


class TestContextCharBudget(unittest.TestCase):
    def test_minimax_gets_more_than_gptoss(self):
        for question in ("short question", "x" * 5000):
            mini = mux.context_char_budget("MiniMax-M2.7", question, 700)
            gpt = mux.context_char_budget("gpt-oss-120b", question, 700)
            self.assertIsInstance(mini, int)
            self.assertIsInstance(gpt, int)
            self.assertGreaterEqual(mini, gpt, "MiniMax has the larger real ceiling")

    def test_zero_when_question_exceeds_ceiling(self):
        ceil = mux.MODEL_CEILINGS["gpt-oss-120b"]["real_ctx_tokens"]
        huge = "x" * (ceil * 4 + 1000)  # question alone blows the ceiling
        self.assertEqual(mux.context_char_budget("gpt-oss-120b", huge, 700), 0)

    def test_never_negative(self):
        self.assertGreaterEqual(mux.context_char_budget("DeepSeek-V3.1", "hi", 700), 0)


class TestTrimToBudget(unittest.TestCase):
    def test_basic_packing_smallest_first(self):
        blocks = [("a.txt", "a" * 50), ("b.txt", "b" * 100), ("c.txt", "c" * 200)]
        text, used, included = mux.trim_to_budget(blocks, 120)
        self.assertEqual(used, 50)
        self.assertEqual(included, ["a.txt"])
        self.assertEqual(text, "a" * 50)

    def test_exact_fit_then_skip_larger(self):
        blocks = [("small.txt", "x" * 30), ("exact.txt", "y" * 70), ("too_big.txt", "z" * 100)]
        text, used, included = mux.trim_to_budget(blocks, 100)
        self.assertEqual(used, 100)
        self.assertEqual(set(included), {"small.txt", "exact.txt"})
        self.assertEqual(text, "x" * 30 + "\n" + "y" * 70)

    def test_zero_budget(self):
        text, used, included = mux.trim_to_budget([("any.txt", "content")], 0)
        self.assertEqual(text, "")
        self.assertEqual(used, 0)
        self.assertEqual(included, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
