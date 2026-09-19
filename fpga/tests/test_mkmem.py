"""Capacity checks must catch uninitialized storage and noncolliding aliases."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("mkmem", Path(__file__).parents[1] / "mkmem.py")
mkmem = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mkmem)


class LayoutTests(unittest.TestCase):
    def test_benchmarks_fit_with_stack(self):
        for end in (0x80007040, 0x80005840):
            mkmem.validate_layout({0x80000000: 0x13, 0x80003813: 0}, 4096, 8192,
                                 {"_stack_top": end, "_end": end})

    def test_reject_alias_even_without_collision(self):
        for address in (0x7FFFFFFF, 0x80008000, 0x80010000):
            with self.subTest(address=address), self.assertRaises(ValueError):
                mkmem.validate_layout({address: 0}, 4096, 8192)

    def test_reject_stack_outside_memory_or_in_led_word(self):
        for end in (0x80008000, 0x80009000):
            with self.subTest(end=end), self.assertRaises(ValueError):
                mkmem.validate_layout({0x80000000: 0}, 4096, 8192, {"_stack_top": end})
        with self.assertRaises(ValueError):
            mkmem.validate_layout({0x80007FFC: 0}, 4096, 8192)

    def test_reject_invalid_depths(self):
        for imem, dmem in ((0, 8192), (4096, -1), (3000, 8192)):
            with self.subTest(depths=(imem, dmem)), self.assertRaises(ValueError):
                mkmem.validate_layout({0x80000000: 0}, imem, dmem)

    def test_byte_lanes_reconstruct_words(self):
        memory = {0x80000000 + i: value for i, value in enumerate([1, 35, 69, 103, 137])}
        words = mkmem.pack_words(memory, 4)
        self.assertEqual(words[0x80000000], 0x67452301)
        self.assertEqual(words[0x80000004], 0x89)
        array, collisions = mkmem.build_array(words, 8192, 4, 0)
        self.assertFalse(collisions)
        self.assertEqual(array[:2], [0x67452301, 0x89])


if __name__ == "__main__":
    unittest.main()
