"""Скрипт «ушей» должен быть синтаксически верным: иначе Геря молчит в приложении."""
import ast
import re
from pathlib import Path

import pytest
from conftest import ears

SOURCE = Path(ears.__file__)

# Присваивание двумя словами — это всегда опечатка («WAKE_MAX_PREFIX_WOR DS = 2»).
BROKEN_ASSIGNMENT = re.compile(r"^\s*\w+\s+\w+\s*(:[^=]*)?=(?!=)")


def test_script_is_syntactically_valid():
    """Опечатка в скрипте убивает весь голос — ловим её тестом."""
    ast.parse(SOURCE.read_text(encoding="utf-8"))


def test_script_has_no_broken_identifiers():
    """Имя переменной не должно разъезжаться пробелом."""
    for number, line in enumerate(SOURCE.read_text(encoding="utf-8").splitlines(), start=1):
        if BROKEN_ASSIGNMENT.match(line.split("#", 1)[0]):
            pytest.fail(f"строка {number}: испорченное присваивание {line.strip()!r}")


def test_no_replacement_characters():
    """Файл должен быть в UTF-8 без битых символов."""
    assert "�" not in SOURCE.read_text(encoding="utf-8")
