"""Стоп-слова: фраза должна целиком состоять из стоп-слов."""
from conftest import ears


def test_single_stop_word():
    assert ears.is_stop("стоп") is True


def test_stop_word_with_fillers():
    assert ears.is_stop("ну стоп") is True
    assert ears.is_stop("Ну всё, хватит") is True


def test_stop_phrase():
    assert ears.is_stop("не надо") is True
    assert ears.is_stop("все хватит") is True


def test_wake_and_stop():
    assert ears.is_stop("Гера, стоп") is True


def test_whisper_mishears_of_the_wake_word_before_a_stop():
    # Whisper регулярно пишет «Гера» как «Гиро» — стоп при этом должен работать.
    assert ears.is_stop("Гиро, стоп") is True
    assert ears.is_stop("герания, стоп") is True
    assert ears.is_stop("Гира, хватит") is True


def test_other_words_are_not_a_stop():
    assert ears.is_stop("отмена будильника") is False
    assert ears.is_stop("расскажи про отмену") is False


def test_empty_text_is_not_a_stop():
    assert ears.is_stop("") is False
    assert ears.is_stop("ну да") is False
