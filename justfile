set shell := ["bash", "-uc"]
cached_direnv_watches:
    ( source .env && direnv show_dump $DIRENV_WATCHES ; )

direnv_watches:
    direnv show_dump $DIRENV_WATCHES

mtime file:
    stat -c '%Y' {{ file }}
