"""Очистка команды и отсев выдумок Whisper."""
from conftest import ears


def test_clean_command_strips_punctuation():
    assert ears.clean_command("  привет, мир!  ") == "привет, мир"
    assert ears.clean_command("скажи…") == "скажи"


def test_clean_command_keeps_inner_punctuation():
    # Знак вопроса в конце — часть очистки, как в эталоне.
    assert ears.clean_command("а что если 2+2?") == "а что если 2+2"


def test_real_command_needs_three_characters():
    assert ears.is_real_command("да") is False
    assert ears.is_real_command("давай") is True


def test_hallucinations_are_rejected():
    assert ears.is_real_command("субтитры") is False
    assert ears.is_real_command("спасибо за просмотр") is False
    assert ears.is_real_command("подписывайтесь на канал") is False


def test_norm_folds_yo_and_punctuation():
    assert ears.norm("Ёлка,  пожалуйста!") == "елка пожалуйста"
