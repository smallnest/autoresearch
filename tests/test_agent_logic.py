from __future__ import annotations

import unittest

from autoresearch.logic import get_review_agent, parse_agent_list


class ParseAgentListTests(unittest.TestCase):
    def test_default_agents_for_empty_input(self) -> None:
        self.assertEqual(parse_agent_list(""), ["claude", "codex", "opencode"])
        self.assertEqual(parse_agent_list(None), ["claude", "codex", "opencode"])

    def test_custom_agent_list(self) -> None:
        self.assertEqual(parse_agent_list("claude,codex"), ["claude", "codex"])
        self.assertEqual(parse_agent_list("opencode, claude , codex"), ["opencode", "claude", "codex"])

    def test_single_agent(self) -> None:
        self.assertEqual(parse_agent_list("claude"), ["claude"])

    def test_invalid_agent_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "未知的 agent"):
            parse_agent_list("claude,invalid_agent")

    def test_empty_items_are_rejected(self) -> None:
        for value in (",claude", "claude,", "claude,,codex"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(ValueError, "存在空项"):
                    parse_agent_list(value)

    def test_duplicates_are_kept(self) -> None:
        self.assertEqual(parse_agent_list("claude,claude"), ["claude", "claude"])


class GetReviewAgentTests(unittest.TestCase):
    def test_rotation_for_three_agents(self) -> None:
        self.assertEqual([get_review_agent(i, 3) for i in range(1, 8)], [0, 1, 2, 0, 1, 2, 0])

    def test_rotation_for_two_agents(self) -> None:
        self.assertEqual([get_review_agent(i, 2) for i in range(1, 5)], [0, 1, 0, 1])

    def test_single_agent_always_zero(self) -> None:
        self.assertEqual([get_review_agent(i, 1) for i in range(1, 6)], [0, 0, 0, 0, 0])


if __name__ == "__main__":
    unittest.main()
