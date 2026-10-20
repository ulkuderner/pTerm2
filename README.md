# pTerm2

Mac açık olmadan çalışan iPad terminali. SSH oturumunu kendisi açar; iTerm2 veya Companion’ın çalışmasına gerek yoktur.

Hedef yalnızca iPad, taban iPadOS 17. Lisans GPL-3.

## Ne yapar

- SSH ve tek ekran terminal (SwiftTerm). Anahtarlar Keychain’de durur.
- Varsayılan uzak komut `tmux -CC new -A -s main`. Pencereler sekme, bölmeler pane olur.
- Yerel kabuk: Blink’in ios_system komut sözlüğü, ayrıca `git`, `scp`, `sshfs`, `python3` ve `pip3`.
- `sshfs` bir File Provider alanı açar; bağlanan yer Files uygulamasında görünür.

`libssh2`, `ios_system`, `libgit2` ve CPython 3.13 isteğe bağlıdır. Bağlı değillerse uygulama açılır; Ayarlar hangi parçanın hazır olduğunu gösterir.

## Derleme

```bash
# isteğe bağlı çerçeveler
tools/download_frameworks.sh

# xcodeproj gem’i yoksa
gem install --user-install xcodeproj
ruby tools/generate_project.rb

open iTerm2Pad.xcodeproj
```

Paket testleri:

```bash
swift test --package-path TmuxControl
swift test --package-path SSHClient
swift test --package-path LocalShell
```

Xcode projesi elle düzenlenmez. Kaynak ekleyince veya silince `tools/generate_project.rb` yeniden çalıştırılır ve üretilen proje commit edilir.
