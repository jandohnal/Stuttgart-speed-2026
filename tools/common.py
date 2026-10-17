"""Helpers shared by the converters in tools/: finding files in the original game's folders
(names differ in case) and walking a source tree whose structure decomposed/ mirrors."""
import os


def find_file(folder, name):
    """Path of `name` in `folder` ignoring case (the original mixes Foo.FSH and foo.fsh), or None."""
    if not os.path.isdir(folder):
        return None
    name = name.lower()
    return next((os.path.join(folder, f) for f in sorted(os.listdir(folder)) if f.lower() == name), None)


def source_files(src, extensions, recursive=True):
    """[(path, relative path without extension)] of the files in src with one of the extensions
    (lowercase, with dot), sorted; a single file gives itself with its stem."""
    if os.path.isfile(src):
        return [(src, os.path.splitext(os.path.basename(src))[0])]
    found = []
    for root, dirs, files in os.walk(src):
        dirs.sort()
        for name in sorted(files):
            if name.lower().endswith(tuple(extensions)):
                path = os.path.join(root, name)
                found.append((path, os.path.splitext(os.path.relpath(path, src))[0]))
        if not recursive:
            break
    return found
