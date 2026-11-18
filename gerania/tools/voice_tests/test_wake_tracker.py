"""Состояние реплики: нашли ли wake-слово, что уже отправили."""
from conftest import ears


def test_tracker_finds_the_wake_word():
    tracker = ears.WakeTracker()
    assert tracker.observe("Гера, какая погода") is True
    assert tracker.woke is True
    assert tracker.command == "какая погода"


def test_tracker_ignores_text_without_the_wake_word():
    tracker = ears.WakeTracker()
    assert tracker.observe("просто фраза") is False
    assert tracker.woke is False
    assert tracker.command == ""


def test_tracker_reports_a_new_command():
    tracker = ears.WakeTracker()
    tracker.observe("Гера, какая пого")
    assert tracker.has_new_command is True
    tracker.dispatched = tracker.command
    assert tracker.has_new_command is False


def test_tracker_compares_commands_without_punctuation():
    tracker = ears.WakeTracker()
    tracker.observe("Гера, какая погода")
    tracker.dispatched = "какая погода"
    assert tracker.has_new_command is False


def test_tracker_notices_a_longer_command():
    tracker = ears.WakeTracker()
    tracker.observe("Гера, какая погода")
    tracker.dispatched = "какая погода"
    tracker.observe("Гера, какая погода в москве")
    assert tracker.has_new_command is True


def test_tracker_reset_clears_the_state():
    tracker = ears.WakeTracker()
    tracker.observe("Гера, какая погода")
    tracker.wake_sent = True
    tracker.dispatched = "какая погода"
    tracker.reset()
    assert tracker.woke is False
    assert tracker.wake_sent is False
    assert tracker.command == ""
    assert tracker.dispatched == ""


def test_tracker_keeps_updating_after_the_wake_word_disappears():
    """Малая модель часто теряет «Гера» в следующих гипотезах."""
    tracker = ears.WakeTracker()
    tracker.observe("Гера, открой")
    assert tracker.observe("Открой Safari и найди погоду") is False
    assert tracker.woke is True
    assert tracker.command == "Открой Safari и найди погоду"


def test_tracker_does_not_update_before_the_wake_word():
    tracker = ears.WakeTracker()
    assert tracker.observe("открой Safari") is False
    assert tracker.command == ""


def test_tracker_does_not_erase_the_command_with_a_bare_wake_word():
    tracker = ears.WakeTracker()
    tracker.observe("Гера, открой Safari")
    tracker.observe("Гера")
    assert tracker.command == "открой Safari"
    assert tracker.has_new_command is True
