"""Write Java properties from environment values without shell interpolation."""
import os
from pathlib import Path


def escape(value):
    result = []
    for character in value:
        if character in "\\:=#! ":
            result.append("\\" + character)
        elif character == "\n":
            result.append("\\n")
        elif character == "\r":
            result.append("\\r")
        elif character == "\t":
            result.append("\\t")
        elif not 32 <= ord(character) <= 126:
            units = character.encode("utf-16-be")
            result.extend(f"\\u{int.from_bytes(units[i:i + 2], 'big'):04x}"
                          for i in range(0, len(units), 2))
        else:
            result.append(character)
    return "".join(result)


def write_properties(path, environment):
    values = {"storeFile": "poemath-release.jks",
              "storePassword": environment["KEYSTORE_PASSWORD"],
              "keyAlias": environment["KEY_ALIAS"],
              "keyPassword": environment["KEY_PASSWORD"]}
    if any(not value for value in values.values()):
        raise ValueError("签名配置缺失")
    path.write_text("".join(f"{key}={escape(value)}\n" for key, value in values.items()),
                    encoding="ascii")


if __name__ == "__main__":
    write_properties(Path("android/key.properties"), os.environ)
