"""Wake word только в начале фразы (не больше двух слов перед ним)."""
from conftest import ears


def test_wake_at_the_start():
    match = ears.find_wake("Гера, что нового")
    assert match is not None


def test_wake_with_the_attention_prefix():
    match = ears.find_wake("Эй, Гера")
    assert match is not None


def test_wake_after_two_words():
    match = ears.find_wake("Ну слушай Гера")
    assert match is not None


def test_wake_after_three_words_is_ignored():
    assert ears.find_wake("А ну ты слушай Гера") is None


def test_similar_words_do_not_wake():
    assert ears.find_wake("германия сегодня") is None
    assert ears.find_wake("герой") is None
    assert ears.find_wake("геры") is None


def test_wake_inside_a_word_is_ignored():
    assert ears.find_wake("супергерой") is None


def test_no_wake_without_the_word():
    assert ears.find_wake("просто фраза") is None


def test_wake_with_a_dot():
    """Whisper часто ставит точку — «Гера.» тоже призыв."""
    match = ears.find_wake("Гера. что нового")
    assert match is not None


def test_wake_with_punctuation():
    for text in ("Гера! открой почту", "Гера, открой почту", "Гера? погода",
                 "Гера - погода", "Гера: погода"):
        assert ears.find_wake(text) is not None, text


def test_wake_glued_to_the_next_word():
    """Помехи Whisper склеивают слово с следующим: «ГераОткрой»."""
    match = ears.find_wake("ГераОткрой почту")
    assert match is not None
    assert ears.command_after_wake("ГераОткрой почту") == "Открой почту"


def test_wake_with_a_tail():
    assert ears.find_wake("Герам") is not None
    assert ears.find_wake("Гера.") is not None


def test_wake_with_yo_and_latin():
    assert ears.find_wake("Гёра, привет") is not None
    assert ears.find_wake("Гэра, привет") is not None
    assert ears.find_wake("Гира, привет") is not None
    assert ears.find_wake("Gera, привет") is not None
    assert ears.find_wake("ГЕРА, привет") is not None


def test_wake_glued_to_the_previous_word():
    """«НуГера» — тоже призыв, но не «мегагерой»."""
    assert ears.find_wake("НуГера, погода") is not None


def test_command_after_wake():
    assert ears.command_after_wake("Гера, какая погода") == "какая погода"
    assert ears.command_after_wake("Гера. какая погода") == "какая погода"
    assert ears.command_after_wake("Эй, Гера, какая погода") == "какая погода"
    assert ears.command_after_wake("Гера") == ""
    assert ears.command_after_wake("просто фраза") == ""


def test_wake_word_is_not_lost_in_noise():
    """Шум добавляет к wake-слову лишние буквы и знаки."""
    for text in ("Гераа", "Гера.", "Гера!!!", "Гера..", "Гера-", "Гера_"):
        assert ears.find_wake(text) is not None, text


def test_latin_wake_inside_a_word_is_ignored():
    assert ears.find_wake("superGera") is None
    assert ears.find_wake("genera") is None
    assert ears.find_wake("diagnostika") is None


def test_whisper_mishears_are_accepted():
    """Whisper часто пишет «Гера» как «Гира» или «Гиро»."""
    assert ears.find_wake("Гира, погода") is not None
    assert ears.find_wake("гиро, погода") is not None
    assert ears.find_wake("ГИРО погода") is not None
    assert ears.command_after_wake("гиро, какая погода") == "какая погода"


def test_geroy_is_not_a_wake_word():
    """«Герой» заканчивается на «о», но это не призыв."""
    assert ears.find_wake("герой") is None
    assert ears.find_wake("Герой живёт в Санкт-Петербурге") is None
